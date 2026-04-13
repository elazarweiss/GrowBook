import 'dart:io';
import 'package:exif/exif.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/models/baby_entry_model.dart';
import '../../core/models/scan_proposal_model.dart';
import '../../core/utils/baby_timeline_utils.dart';
import '../../data/baby_repository.dart';

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

  // ── Pick folder path (desktop only) ──────────────────────────────────────

  static Future<String?> pickFolder() async {
    return FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select your Camera Uploads folder',
    );
  }

  // ── Main scan ─────────────────────────────────────────────────────────────

  /// Scans [folderPath] for images taken after [birthDate].
  /// Only processes files newer than [sinceDate] if provided.
  /// Reports progress via [onProgress].
  static Future<List<ScanProposal>> scan({
    required String folderPath,
    required DateTime birthDate,
    DateTime? sinceDate,
    void Function(ScanProgress)? onProgress,
  }) async {
    // 1. Collect image files
    final files = <File>[];
    try {
      final dir = Directory(folderPath);
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File && _isImage(entity.path)) {
          // Filter by modification time if sinceDate is provided
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

    // 2. Extract dates and group by slot
    final Map<String, ScanProposal> bySlot = {};
    final Set<String> alreadyImported = _buildImportedPathSet();

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      onProgress?.call(ScanProgress(i, files.length, file.path));

      // Skip already-imported files
      if (alreadyImported.contains(file.path)) continue;

      final photoDate = await _extractDate(file);
      if (photoDate == null) continue;
      // Skip photos taken before birth
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
            ScanCandidate(file: file, photoDate: photoDate),
          );
    }

    onProgress?.call(ScanProgress(files.length, files.length));

    // Sort candidates within each slot by date
    for (final p in bySlot.values) {
      p.candidates.sort((a, b) => a.photoDate.compareTo(b.photoDate));
    }

    // Return sorted by slot index
    return bySlot.values.toList()
      ..sort((a, b) => a.slot.index.compareTo(b.slot.index));
  }

  // ── Save selected candidates ──────────────────────────────────────────────

  static Future<void> saveSelected(List<ScanProposal> proposals) async {
    for (final proposal in proposals) {
      if (!proposal.importEnabled) continue;
      final selected = proposal.candidates.where((c) => c.selected).toList();
      if (selected.isEmpty) continue;

      final paths = selected.map((c) => c.file.path).toList();
      final existing = BabyRepository.instance.getEntry(proposal.slot.key);

      await BabyRepository.instance.saveEntry(BabyEntry(
        slotKey: proposal.slot.key,
        photoPaths: [...?existing?.photoPaths, ...paths],
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

  /// Builds a set of all file paths already imported into any BabyEntry.
  static Set<String> _buildImportedPathSet() {
    // Best-effort dedup — we rely on sinceDate filtering for most cases.
    // Native paths stored in Hive could be compared here if we exposed box iteration.
    return {};
  }

  static Future<DateTime?> _extractDate(File file) async {
    // 1. Try EXIF
    try {
      final bytes = await file.readAsBytes();
      final tags = await readExifFromBytes(bytes);
      final raw = tags['EXIF DateTimeOriginal'] ?? tags['Image DateTime'];
      if (raw != null) {
        final dt = _parseExifDate(raw.toString());
        if (dt != null) return dt;
      }
    } catch (_) {}

    // 2. Try filename date pattern: IMG_20240415_..., 2024-04-15, etc.
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

    // 3. Fall back to file modification date
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
