import 'dart:convert';
import 'dart:io';
import 'package:exif/exif.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../../core/models/baby_slot_model.dart';
import '../../core/models/inbox_photo_model.dart';
import '../../core/models/scan_proposal_model.dart';
import '../../core/utils/baby_timeline_utils.dart';
import '../../data/baby_repository.dart';

const _serverBase = 'http://localhost:7272';

class ScanProgress {
  final int processed;
  final int total;
  final String? currentFile;

  const ScanProgress(this.processed, this.total, [this.currentFile]);

  double get fraction => total == 0 ? 0 : processed / total;
}

class BabyScanController {
  static const _imageExtensions = {
    '.jpg', '.jpeg', '.png', '.heic', '.heif', '.webp', '.bmp',
  };

  // ── Scan cache (5-minute TTL, avoids re-walking disk on every slot open) ──
  static Map<String, List<InboxPhoto>>? _scanCache;
  static DateTime? _scanCacheTime;
  static const _cacheTtl = Duration(minutes: 5);

  static bool get _cacheValid =>
      _scanCache != null &&
      _scanCacheTime != null &&
      DateTime.now().difference(_scanCacheTime!) < _cacheTtl;

  static void invalidateCache() {
    _scanCache = null;
    _scanCacheTime = null;
  }

  /// Warm up the scan cache in the background — call once on app start.
  static Future<void> warmupCache() async {
    if (_cacheValid) return;
    try {
      await _fetchAndCacheScan();
    } catch (_) {}
  }

  static Future<Map<String, List<InboxPhoto>>> _fetchAndCacheScan() async {
    final response = await http
        .get(Uri.parse('$_serverBase/scan'))
        .timeout(const Duration(seconds: 60));
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final groups = json['groups'] as Map<String, dynamic>? ?? {};

    final cache = <String, List<InboxPhoto>>{};
    for (final entry in groups.entries) {
      final slotKey = entry.key;
      final photos = entry.value as List<dynamic>;
      cache[slotKey] = photos.map((p) {
        final serverPath = p['path'] as String;
        final date =
            DateTime.tryParse(p['date'] as String? ?? '') ?? DateTime.now();
        final id = 'server:$serverPath';
        return InboxPhoto(id: id, path: id, date: date, slotKey: slotKey);
      }).toList();
    }

    _scanCache = cache;
    _scanCacheTime = DateTime.now();
    return cache;
  }

  // ── Check if companion server is running (web only) ───────────────────────

  static Future<bool> checkServerRunning() async {
    try {
      final r = await http
          .get(Uri.parse('$_serverBase/status'))
          .timeout(const Duration(seconds: 2));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Pick folder (native only) ─────────────────────────────────────────────

  static Future<String?> pickFolder() async {
    if (kIsWeb) return null;
    return FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select your Camera Uploads folder',
    );
  }

  // ── Main scan ─────────────────────────────────────────────────────────────

  static Future<List<ScanProposal>> scan({
    required String folderPath,
    required DateTime birthDate,
    DateTime? sinceDate,
    void Function(ScanProgress)? onProgress,
  }) async {
    if (kIsWeb) {
      return _scanViaServer(birthDate, onProgress);
    }
    return _scanLocal(folderPath, birthDate, sinceDate, onProgress);
  }

  // ── Web: call companion server ────────────────────────────────────────────

  static Future<List<ScanProposal>> _scanViaServer(
    DateTime birthDate,
    void Function(ScanProgress)? onProgress,
  ) async {
    onProgress?.call(const ScanProgress(0, 0));

    final response = await http.get(Uri.parse('$_serverBase/scan'));
    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['error'] != null) {
      throw Exception(json['error'] as String);
    }

    final groups = json['groups'] as Map<String, dynamic>? ?? {};
    final Map<String, ScanProposal> bySlot = {};

    for (final entry in groups.entries) {
      final slotKey = entry.key;
      final photos = entry.value as List<dynamic>;
      if (photos.isEmpty) continue;

      final slot = BabyTimelineUtils.slotForKey(slotKey);
      final hasExisting =
          BabyRepository.instance.getEntry(slotKey)?.photoPaths.isNotEmpty ==
              true;

      final proposal = ScanProposal(
        slot: slot,
        candidates: [],
        hasExisting: hasExisting,
      );

      for (final p in photos) {
        final path = p['path'] as String;
        final dt = DateTime.tryParse(p['date'] as String? ?? '') ?? birthDate;
        proposal.candidates.add(ScanCandidate.remote(path, dt));
      }

      bySlot[slotKey] = proposal;
    }

    onProgress?.call(const ScanProgress(1, 1));

    return bySlot.values.toList()
      ..sort((a, b) => a.slot.index.compareTo(b.slot.index));
  }

  // ── Native: scan local filesystem ─────────────────────────────────────────

  static Future<List<ScanProposal>> _scanLocal(
    String folderPath,
    DateTime birthDate,
    DateTime? sinceDate,
    void Function(ScanProgress)? onProgress,
  ) async {
    final files = <File>[];
    try {
      final dir = Directory(folderPath);
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File && _isImage(entity.path)) {
          if (sinceDate != null) {
            final stat = entity.statSync();
            if (stat.modified.isBefore(sinceDate)) continue;
          }
          files.add(entity);
        }
      }
    } catch (_) {
      return [];
    }

    files.sort((a, b) => a.path.compareTo(b.path));

    final Map<String, ScanProposal> bySlot = {};

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      onProgress?.call(ScanProgress(i, files.length, file.path));

      final photoDate = await _extractDate(file);
      if (photoDate == null) continue;
      if (photoDate.isBefore(birthDate)) continue;

      final slot = BabyTimelineUtils.slotForDate(birthDate, photoDate);

      bySlot.putIfAbsent(slot.key, () {
        final hasExisting =
            BabyRepository.instance.getEntry(slot.key)?.photoPaths.isNotEmpty ==
                true;
        return ScanProposal(
          slot: slot,
          candidates: [],
          hasExisting: hasExisting,
        );
      });

      bySlot[slot.key]!.candidates.add(ScanCandidate.local(file, photoDate));
    }

    onProgress?.call(ScanProgress(files.length, files.length));

    for (final p in bySlot.values) {
      p.candidates.sort((a, b) => a.photoDate.compareTo(b.photoDate));
    }

    return bySlot.values.toList()
      ..sort((a, b) => a.slot.index.compareTo(b.slot.index));
  }

  // ── Save selected candidates to inbox ────────────────────────────────────

  static Future<void> saveSelected(List<ScanProposal> proposals) async {
    for (final proposal in proposals) {
      if (!proposal.importEnabled) continue;
      final selected = proposal.candidates.where((c) => c.selected).toList();
      if (selected.isEmpty) continue;

      for (final candidate in selected) {
        final storedPath = kIsWeb
            ? 'server:${candidate.serverPath}'
            : candidate.serverPath;
        final photo = InboxPhoto(
          id: storedPath,
          path: storedPath,
          date: candidate.photoDate,
          slotKey: proposal.slot.key,
        );
        await BabyRepository.instance.saveInboxPhoto(photo);
      }
    }

    await BabyRepository.instance.saveLastScanAt(DateTime.now());
    invalidateCache(); // force fresh scan next time a slot opens
  }

  // ── Fetch photos for a single slot from server ───────────────────────────

  /// Returns photos for the given slot — uses cache, scans only if needed.
  static Future<List<InboxPhoto>> fetchPhotosForSlot(BabySlot slot) async {
    try {
      final cache = _cacheValid ? _scanCache! : await _fetchAndCacheScan();
      return cache[slot.key] ?? [];
    } catch (_) {
      return [];
    }
  }

  // ── Background AI screening ───────────────────────────────────────────────

  /// Call after saveSelected() — fire and forget.
  /// Posts unscreened inbox photo paths to /analyze, then updates each
  /// InboxPhoto with has_baby flag and tags.
  static Future<void> screenInbox() async {
    final unscreened = BabyRepository.instance.getUnscreenedInbox();
    if (unscreened.isEmpty) return;

    // Map server path (stripped) → InboxPhoto for matching results
    final Map<String, InboxPhoto> pathToPhoto = {};
    for (final photo in unscreened) {
      final serverPath = photo.path.startsWith('server:')
          ? photo.path.substring(7)
          : photo.path;
      pathToPhoto[serverPath] = photo;
    }

    try {
      final response = await http.post(
        Uri.parse('$_serverBase/analyze'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'paths': pathToPhoto.keys.toList()}),
      ).timeout(const Duration(minutes: 10));

      if (response.statusCode != 200) return;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tagMap = json['tags'] as Map<String, dynamic>? ?? {};

      for (final entry in pathToPhoto.entries) {
        final serverPath = entry.key;
        final photo = entry.value;
        final tagData = tagMap[serverPath] as Map<String, dynamic>?;

        final screened = photo.copyWithScreening(
          hasBaby: tagData != null
              ? (tagData['has_baby'] as bool? ?? false)
              : false,
          isMilestone: tagData?['is_milestone'] as bool? ?? false,
          mood: (tagData?['mood'] as String?)?.toLowerCase(),
          activity: (tagData?['activity'] as String?)?.toLowerCase(),
          aiCaption: tagData?['caption'] as String?,
          people: List<String>.from(tagData?['people'] as List? ?? []),
        );
        await BabyRepository.instance.saveInboxPhoto(screened);
      }
    } catch (_) {
      // Screening is best-effort; silently ignore failures
    }
  }

  /// Screen only unscreened inbox photos for a specific slot.
  static Future<void> screenInboxSlot(String slotKey) async {
    final unscreened = BabyRepository.instance
        .getUnscreenedInbox()
        .where((p) => p.slotKey == slotKey)
        .toList();
    if (unscreened.isEmpty) return;

    final Map<String, InboxPhoto> pathToPhoto = {};
    for (final photo in unscreened) {
      final serverPath = photo.path.startsWith('server:')
          ? photo.path.substring(7)
          : photo.path;
      pathToPhoto[serverPath] = photo;
    }

    try {
      final response = await http.post(
        Uri.parse('$_serverBase/analyze'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'paths': pathToPhoto.keys.toList()}),
      ).timeout(const Duration(minutes: 5));

      if (response.statusCode != 200) return;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tagMap = json['tags'] as Map<String, dynamic>? ?? {};

      for (final entry in pathToPhoto.entries) {
        final tagData = tagMap[entry.key] as Map<String, dynamic>?;
        final screened = entry.value.copyWithScreening(
          hasBaby: tagData != null ? (tagData['has_baby'] as bool? ?? false) : false,
          isMilestone: tagData?['is_milestone'] as bool? ?? false,
          mood: (tagData?['mood'] as String?)?.toLowerCase(),
          activity: (tagData?['activity'] as String?)?.toLowerCase(),
          aiCaption: tagData?['caption'] as String?,
          people: List<String>.from(tagData?['people'] as List? ?? []),
        );
        await BabyRepository.instance.saveInboxPhoto(screened);
      }
    } catch (_) {}
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static bool _isImage(String path) {
    final lower = path.toLowerCase();
    return _imageExtensions.any((ext) => lower.endsWith(ext));
  }

  static Future<DateTime?> _extractDate(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final tags = await readExifFromBytes(bytes);
      final raw = tags['EXIF DateTimeOriginal'] ?? tags['Image DateTime'];
      if (raw != null) {
        final dt = _parseExifDate(raw.toString());
        if (dt != null) return dt;
      }
    } catch (_) {}

    final name = file.path.split(Platform.pathSeparator).last;
    final match =
        RegExp(r'(\d{4})[_\-]?(\d{2})[_\-]?(\d{2})').firstMatch(name);
    if (match != null) {
      final y = int.parse(match[1]!);
      final m = int.parse(match[2]!);
      final d = int.parse(match[3]!);
      if (y > 2000 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        return DateTime(y, m, d);
      }
    }

    try {
      return file.statSync().modified;
    } catch (_) {
      return null;
    }
  }

  static DateTime? _parseExifDate(String raw) {
    try {
      final parts = raw.split(' ');
      final dateParts = parts[0].split(':');
      if (dateParts.length < 3) return null;
      return DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
      );
    } catch (_) {
      return null;
    }
  }
}
