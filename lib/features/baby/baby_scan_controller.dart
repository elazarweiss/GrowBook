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
        return InboxPhoto(
          id: id,
          path: id,
          date: date,
          slotKey: slotKey,
          burstId: p['burst_id'] as String?,
          burstRepresentative: p['burst_representative'] as bool? ?? true,
        );
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

  // ── Import-time screening (user-opted-in, thumbnail mode) ───────────────────

  /// Screen all candidates in [proposals] using tiny thumbnails (300px).
  /// ~5x cheaper and faster than full-resolution screening.
  /// Returns the set of server paths confirmed to contain a baby.
  /// Called only when user explicitly chooses "Baby photos only" import mode.
  static Future<Set<String>> screenProposalsForBaby(
      List<ScanProposal> proposals) async {
    final paths = <String>[];
    for (final p in proposals) {
      for (final c in p.candidates) {
        paths.add(c.serverPath);
      }
    }
    if (paths.isEmpty) return {};

    try {
      final response = await http.post(
        Uri.parse('$_serverBase/screen'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'paths': paths, 'thumb': true}),
      ).timeout(const Duration(minutes: 20));

      if (response.statusCode != 200) return {};

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final results = json['results'] as Map<String, dynamic>? ?? {};
      return results.entries
          .where((e) => e.value == true)
          .map((e) => e.key)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  // ── Pin time: tag selected photos then persist to timeline ──────────────────

  /// Run full AI tagging on [selected] photos, then pin them to the timeline.
  /// This is the main AI trigger: called only when user commits to pinning.
  /// Typically 1-3 photos → ~5-6 second wait, then done.
  static Future<void> tagAndPin(
      String slotKey, List<InboxPhoto> selected) async {
    if (selected.isEmpty) return;

    final Map<String, InboxPhoto> pathToPhoto = {};
    for (final photo in selected) {
      final serverPath = photo.path.startsWith('server:')
          ? photo.path.substring(7)
          : photo.path;
      pathToPhoto[serverPath] = photo;
    }

    List<InboxPhoto> toPin = selected;

    try {
      final response = await http.post(
        Uri.parse('$_serverBase/analyze'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'paths': pathToPhoto.keys.toList()}),
      ).timeout(const Duration(minutes: 2));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final tagMap = json['tags'] as Map<String, dynamic>? ?? {};

        toPin = [];
        for (final entry in pathToPhoto.entries) {
          final tagData = tagMap[entry.key] as Map<String, dynamic>?;
          toPin.add(entry.value.copyWithScreening(
            hasBaby: true,
            isMilestone: tagData?['is_milestone'] as bool? ?? false,
            mood: (tagData?['mood'] as String?)?.toLowerCase(),
            activity: (tagData?['activity'] as String?)?.toLowerCase(),
            aiCaption: tagData?['caption'] as String?,
            people: List<String>.from(tagData?['people'] as List? ?? []),
          ));
        }
      }
    } catch (_) {
      // Tag failure is non-fatal — pin without tags
    }

    await BabyRepository.instance.setFeaturedPhotos(slotKey, toPin);
  }

  // ── On-demand per-day analysis (week editor ✨ button) ───────────────────────

  /// Screen + fully tag all photos in [photos] (a single day's worth).
  /// Uses thumbnail screening first, then full-res tagging for baby photos.
  /// Saves results back to Hive. Returns the updated list.
  static Future<List<InboxPhoto>> screenAndTagDay(
      List<InboxPhoto> photos) async {
    if (photos.isEmpty) return photos;

    // Step 1: Thumbnail screen for unscreened photos
    final unscreened =
        photos.where((p) => p.hasBaby == null).toList();
    if (unscreened.isNotEmpty) {
      final pathToPhoto = <String, InboxPhoto>{};
      for (final p in unscreened) {
        final sp = p.path.startsWith('server:') ? p.path.substring(7) : p.path;
        pathToPhoto[sp] = p;
      }
      try {
        final r = await http.post(
          Uri.parse('$_serverBase/screen'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'paths': pathToPhoto.keys.toList(), 'thumb': true}),
        ).timeout(const Duration(minutes: 5));
        if (r.statusCode == 200) {
          final results =
              (jsonDecode(r.body)['results'] as Map<String, dynamic>?) ?? {};
          for (final entry in pathToPhoto.entries) {
            final hasBaby = results[entry.key] as bool? ?? false;
            final updated = InboxPhoto(
              id: entry.value.id,
              path: entry.value.path,
              date: entry.value.date,
              slotKey: entry.value.slotKey,
              hasBaby: hasBaby,
              burstId: entry.value.burstId,
              burstRepresentative: entry.value.burstRepresentative,
            );
            await BabyRepository.instance.saveInboxPhoto(updated);
          }
        }
      } catch (_) {}
    }

    // Step 2: Full tag for baby photos that aren't yet tagged
    final babyUntagged = BabyRepository.instance
        .getInboxForSlot(photos.first.slotKey)
        .where((p) =>
            photos.any((orig) => orig.id == p.id) &&
            p.hasBaby == true &&
            p.mood == null)
        .toList();

    if (babyUntagged.isNotEmpty) {
      final pathToPhoto = <String, InboxPhoto>{};
      for (final p in babyUntagged) {
        final sp = p.path.startsWith('server:') ? p.path.substring(7) : p.path;
        pathToPhoto[sp] = p;
      }
      try {
        final r = await http.post(
          Uri.parse('$_serverBase/analyze'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'paths': pathToPhoto.keys.toList()}),
        ).timeout(const Duration(minutes: 5));
        if (r.statusCode == 200) {
          final tagMap =
              (jsonDecode(r.body)['tags'] as Map<String, dynamic>?) ?? {};
          for (final entry in pathToPhoto.entries) {
            final tagData = tagMap[entry.key] as Map<String, dynamic>?;
            final screened = entry.value.copyWithScreening(
              hasBaby: true,
              isMilestone: tagData?['is_milestone'] as bool? ?? false,
              mood: (tagData?['mood'] as String?)?.toLowerCase(),
              activity: (tagData?['activity'] as String?)?.toLowerCase(),
              aiCaption: tagData?['caption'] as String?,
              people:
                  List<String>.from(tagData?['people'] as List? ?? []),
            );
            await BabyRepository.instance.saveInboxPhoto(screened);
          }
        }
      } catch (_) {}
    }

    // Return fresh data from Hive for this slot filtered to this day's photos
    final allSlot =
        BabyRepository.instance.getInboxForSlot(photos.first.slotKey);
    final ids = photos.map((p) => p.id).toSet();
    return allSlot.where((p) => ids.contains(p.id)).toList();
  }

  // ── Phase 2: full tags per slot (called from week editor) ────────────────────

  /// Full-tag baby photos for one slot that haven't been tagged yet.
  /// Requires hasBaby == true and mood == null (not yet tagged).
  static Future<void> screenInboxSlot(String slotKey) async {
    final untagged = BabyRepository.instance
        .getInboxForSlot(slotKey)
        .where((p) => p.hasBaby == true && p.mood == null)
        .toList();
    if (untagged.isEmpty) return;

    final Map<String, InboxPhoto> pathToPhoto = {};
    for (final photo in untagged) {
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
          hasBaby: true,  // already confirmed
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
