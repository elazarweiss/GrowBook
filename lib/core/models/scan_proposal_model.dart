import 'dart:io';
import 'baby_slot_model.dart';

class ScanCandidate {
  final File file;
  final DateTime photoDate;
  bool selected;

  ScanCandidate({
    required this.file,
    required this.photoDate,
    this.selected = true,
  });
}

class ScanProposal {
  final BabySlot slot;
  final List<ScanCandidate> candidates;
  final bool hasExisting; // slot already has a photo in Hive

  // selected = should we import any candidates?
  bool importEnabled;

  ScanProposal({
    required this.slot,
    required this.candidates,
    required this.hasExisting,
  }) : importEnabled = !hasExisting; // default: import only new slots

  int get selectedCount => candidates.where((c) => c.selected).length;

  // Best candidate to show as preview (first chronologically)
  ScanCandidate? get bestCandidate =>
      candidates.isEmpty ? null : candidates.first;
}
