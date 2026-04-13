import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/models/baby_entry_model.dart';
import '../../core/models/baby_slot_model.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/baby_repository.dart';

class BabyEntryScreen extends StatefulWidget {
  final BabySlot slot;

  const BabyEntryScreen({super.key, required this.slot});

  @override
  State<BabyEntryScreen> createState() => _BabyEntryScreenState();
}

class _BabyEntryScreenState extends State<BabyEntryScreen> {
  late final TextEditingController _captionController;
  String? _photoPath;
  bool _saving = false;
  bool _pickingPhoto = false;

  @override
  void initState() {
    super.initState();
    final existing = BabyRepository.instance.getEntry(widget.slot.key);
    _captionController = TextEditingController(text: existing?.caption ?? '');
    _photoPath =
        existing?.photoPaths.isNotEmpty == true ? existing!.photoPaths.first : null;
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_pickingPhoto) return;
    setState(() => _pickingPhoto = true);

    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (picked == null) return;

      // Copy to stable app documents directory
      final docsDir = await getApplicationDocumentsDirectory();
      final destDir = Directory('${docsDir.path}/baby_photos');
      if (!destDir.existsSync()) destDir.createSync(recursive: true);

      final fileName =
          '${widget.slot.key}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final destPath = '${destDir.path}/$fileName';
      await File(picked.path).copy(destPath);

      if (mounted) setState(() => _photoPath = destPath);
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final entry = BabyEntry(
      slotKey: widget.slot.key,
      photoPaths: _photoPath != null ? [_photoPath!] : [],
      caption: _captionController.text.trim().isNotEmpty
          ? _captionController.text.trim()
          : null,
      updatedAt: DateTime.now(),
    );
    await BabyRepository.instance.saveEntry(entry);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.slot.label.toUpperCase(),
                          style: AppTypography.label.copyWith(
                            color: AppColors.warmTaupe,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _slotTitle(),
                          style: AppTypography.heading3
                              .copyWith(color: AppColors.warmBrown),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: AppColors.warmTaupe,
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Photo picker
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: _pickingPhoto
                        ? const Center(child: CircularProgressIndicator())
                        : _photoPath != null
                            ? Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: Image.file(
                                      File(_photoPath!),
                                      width: double.infinity,
                                      height: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _emptyPhotoHint(),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: AppSpacing.sm,
                                    right: AppSpacing.sm,
                                    child: _changePhotoButton(),
                                  ),
                                ],
                              )
                            : _emptyPhotoHint(),
                  ),
                ),
              ),
            ),

            // Caption field
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
              child: TextField(
                controller: _captionController,
                maxLength: 60,
                decoration: InputDecoration(
                  hintText: 'Add a caption…',
                  hintStyle:
                      TextStyle(color: AppColors.warmTaupe.withOpacity(0.7)),
                  filled: true,
                  fillColor: AppColors.surface,
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.sageGreen),
                  ),
                ),
              ),
            ),

            // Save
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.sageGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.divider,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.pillRadius),
                    ),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyPhotoHint() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 40, color: AppColors.warmTaupe.withOpacity(0.6)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tap to add a photo',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.warmTaupe),
          ),
        ],
      ),
    );
  }

  Widget _changePhotoButton() {
    return GestureDetector(
      onTap: _pickPhoto,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit, size: 12, color: Colors.white),
            SizedBox(width: 4),
            Text('Change', style: TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  String _slotTitle() {
    switch (widget.slot.kind) {
      case BabyAgeKind.week:
        return widget.slot.value == 0
            ? 'Birth Day'
            : 'Week ${widget.slot.value}';
      case BabyAgeKind.month:
        return 'Month ${widget.slot.value}';
      case BabyAgeKind.year:
        return 'Year ${widget.slot.value}';
    }
  }
}
