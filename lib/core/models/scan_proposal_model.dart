import 'dart:io';
import 'baby_slot_model.dart';

class ScanCandidate {
  /// The local filesystem path of this photo.
  /// On native: the actual file path (used with Image.file).
  /// On web: the path the companion server is serving from.
  final String serverPath;

  /// Non-null on native; null when using the web companion server.
  final File? localFile;

  final DateTime photoDate;
  bool selected;

  ScanCandidate.local(File file, this.photoDate)
      : serverPath = file.path,
        localFile = file,
        selected = true;

  ScanCandidate.remote(this.serverPath, this.photoDate)
      : localFile = null,
        selected = true;
}

class ScanProposal {
  final BabySlot slot;
  final List<ScanCandidate> candidates;
  final bool hasExisting;
  bool importEnabled;

  ScanProposal({
    required this.slot,
    required this.candidates,
    required this.hasExisting,
  }) : importEnabled = !hasExisting;

  int get selectedCount => candidates.where((c) => c.selected).length;

  ScanCandidate? get bestCandidate =>
      candidates.isEmpty ? null : candidates.first;
}
