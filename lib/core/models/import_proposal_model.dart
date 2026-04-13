import 'package:file_picker/file_picker.dart';
import 'baby_slot_model.dart';

class ImportCandidate {
  final PlatformFile file;
  final DateTime? photoDate;
  bool selected;

  ImportCandidate({
    required this.file,
    required this.photoDate,
    this.selected = true,
  });
}

class ImportProposal {
  final BabySlot slot;
  final List<ImportCandidate> candidates;

  ImportProposal({required this.slot, required this.candidates});
}
