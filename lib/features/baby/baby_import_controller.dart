import 'dart:convert';
import 'dart:io';
import 'package:exif/exif.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import '../../core/models/baby_entry_model.dart';
import '../../core/models/baby_slot_model.dart';
import '../../core/models/import_proposal_model.dart';
import '../../core/utils/baby_timeline_utils.dart';
import '../../data/baby_repository.dart';

class BabyImportController {
  /// Holds the current import session so the review screen can access it
  /// without serializing through GoRouter.
  static List<ImportProposal>? currentSession;

  /// Opens multi-file picker, reads EXIF dates, groups by slot.
  /// Returns null if the user cancelled.
  static Future<List<ImportProposal>?> pickAndGroup(DateTime birthDate) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true, // required for EXIF + web
    );
    if (result == null || result.files.isEmpty) return null;

    final Map<String, ImportProposal> bySlot = {};
    final List<ImportCandidate> unassigned = [];

    for (final file in result.files) {
      final photoDate = await _extractDate(file);
      if (photoDate != null) {
        final slot = BabyTimelineUtils.slotForDate(birthDate, photoDate);
        bySlot.putIfAbsent(
          slot.key,
          () => ImportProposal(slot: slot, candidates: []),
        );
        bySlot[slot.key]!.candidates
            .add(ImportCandidate(file: file, photoDate: photoDate));
      } else {
        unassigned.add(ImportCandidate(file: file, photoDate: null));
      }
    }

    final proposals = bySlot.values.toList()
      ..sort((a, b) => a.slot.index.compareTo(b.slot.index));

    if (unassigned.isNotEmpty) {
      // Unassigned photos use a sentinel slot (index -1)
      proposals.add(ImportProposal(
        slot: BabySlot(
            index: -1, kind: BabyAgeKind.week, value: -1, label: '?'),
        candidates: unassigned,
      ));
    }

    currentSession = proposals;
    return proposals;
  }

  /// Saves all selected candidates from proposals into Hive.
  static Future<void> saveSelected(List<ImportProposal> proposals) async {
    for (final proposal in proposals) {
      if (proposal.slot.index < 0) continue; // skip unassigned
      final selected = proposal.candidates.where((c) => c.selected).toList();
      if (selected.isEmpty) continue;

      final paths = <String>[];
      for (final candidate in selected) {
        final path = await _storeFile(candidate.file, proposal.slot.key);
        if (path != null) paths.add(path);
      }
      if (paths.isEmpty) continue;

      final existing = BabyRepository.instance.getEntry(proposal.slot.key);
      await BabyRepository.instance.saveEntry(BabyEntry(
        slotKey: proposal.slot.key,
        photoPaths: [...?existing?.photoPaths, ...paths],
        caption: existing?.caption,
        updatedAt: DateTime.now(),
      ));
    }
  }

  // ─── Date extraction ──────────────────────────────────────────────────────

  static Future<DateTime?> _extractDate(PlatformFile file) async {
    // 1. EXIF DateTimeOriginal
    if (file.bytes != null) {
      try {
        final tags = await readExifFromBytes(file.bytes!);
        final raw = tags['EXIF DateTimeOriginal'] ?? tags['Image DateTime'];
        if (raw != null) {
          final dt = _parseExifDate(raw.toString());
          if (dt != null) return dt;
        }
      } catch (_) {}
    }

    // 2. Filename pattern: IMG_20240415_... or 2024-04-15 etc.
    final match = RegExp(r'(\d{4})[_\-]?(\d{2})[_\-]?(\d{2})').firstMatch(file.name);
    if (match != null) {
      final y = int.parse(match[1]!);
      final m = int.parse(match[2]!);
      final d = int.parse(match[3]!);
      if (y > 2000 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        return DateTime(y, m, d);
      }
    }

    return null;
  }

  static DateTime? _parseExifDate(String raw) {
    // EXIF format: "2024:04:15 10:30:00"
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

  // ─── File storage ─────────────────────────────────────────────────────────

  static Future<String?> _storeFile(PlatformFile file, String slotKey) async {
    if (file.bytes == null) return null;

    if (kIsWeb) {
      // Web: store as base64 data URL
      return 'data:image/jpeg;base64,${base64Encode(file.bytes!)}';
    }

    // Native: write bytes to documents directory
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final destDir = Directory('${docsDir.path}/baby_photos');
      if (!destDir.existsSync()) await destDir.create(recursive: true);
      final fileName =
          '${slotKey}_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final destFile = File('${destDir.path}/$fileName');
      await destFile.writeAsBytes(file.bytes!);
      return destFile.path;
    } catch (_) {
      return null;
    }
  }
}
