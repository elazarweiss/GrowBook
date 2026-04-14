import 'dart:convert';
import 'dart:io';
import 'package:exif/exif.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../../core/models/baby_entry_model.dart';
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
    if (kIsWeb) return null; // not applicable on web
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

      bySlot[slot.key]!.candidates.add(
            ScanCandidate.local(file, photoDate),
          );
    }

    onProgress?.call(ScanProgress(files.length, files.length));

    for (final p in bySlot.values) {
      p.candidates.sort((a, b) => a.photoDate.compareTo(b.photoDate));
    }

    return bySlot.values.toList()
      ..sort((a, b) => a.slot.index.compareTo(b.slot.index));
  }

  // ── Save selected candidates ──────────────────────────────────────────────

  static Future<void> saveSelected(List<ScanProposal> proposals) async {
    for (final proposal in proposals) {
      if (!proposal.importEnabled) continue;
      final selected = proposal.candidates.where((c) => c.selected).toList();
      if (selected.isEmpty) continue;

      List<String> newPaths;

      if (kIsWeb) {
        // Fetch each photo from the companion server and store as base64
        newPaths = [];
        for (final c in selected) {
          try {
            final url =
                '$_serverBase/photo?path=${Uri.encodeComponent(c.serverPath)}';
            final r = await http.get(Uri.parse(url));
            if (r.statusCode == 200) {
              newPaths.add('data:image/jpeg;base64,${base64Encode(r.bodyBytes)}');
            }
          } catch (_) {}
        }
      } else {
        newPaths = selected.map((c) => c.serverPath).toList();
      }

      if (newPaths.isEmpty) continue;

      final existing = BabyRepository.instance.getEntry(proposal.slot.key);
      await BabyRepository.instance.saveEntry(BabyEntry(
        slotKey: proposal.slot.key,
        photoPaths: [...?existing?.photoPaths, ...newPaths],
        caption: existing?.caption,
        updatedAt: DateTime.now(),
      ));
    }

    await BabyRepository.instance.saveLastScanAt(DateTime.now());
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
