import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/models/baby_entry_model.dart';
import '../../core/models/baby_slot_model.dart';
import '../../core/theme/app_colors.dart';
import '../../data/baby_data.dart';
import '../../data/baby_repository.dart';

class BabyEntryScreen extends StatefulWidget {
  final BabySlot slot;
  const BabyEntryScreen({super.key, required this.slot});

  @override
  State<BabyEntryScreen> createState() => _BabyEntryScreenState();
}

class _BabyEntryScreenState extends State<BabyEntryScreen> {
  late final TextEditingController _captionController;
  late List<String> _photoPaths;
  late final PageController _pageController;
  int _currentPage = 0;
  bool _saving = false;
  bool _pickingPhoto = false;

  BabyMilestoneInfo? get _milestone => babyMilestones
      .where((m) => m.slotKey == widget.slot.key)
      .cast<BabyMilestoneInfo?>()
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    final existing = BabyRepository.instance.getEntry(widget.slot.key);
    _captionController = TextEditingController(text: existing?.caption ?? '');
    _photoPaths = List.from(existing?.photoPaths ?? []);
    _pageController = PageController();
  }

  @override
  void dispose() {
    _captionController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    if (_pickingPhoto) return;
    setState(() => _pickingPhoto = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 88,
      );
      if (picked == null) return;

      String path;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        path = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      } else {
        final docsDir = await getApplicationDocumentsDirectory();
        final destDir = Directory('${docsDir.path}/baby_photos');
        if (!destDir.existsSync()) destDir.createSync(recursive: true);
        final fileName =
            '${widget.slot.key}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final destPath = '${destDir.path}/$fileName';
        await File(picked.path).copy(destPath);
        path = destPath;
      }

      if (mounted) {
        setState(() {
          _photoPaths.add(path);
          _currentPage = _photoPaths.length - 1;
        });
        // Jump to the new photo after frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            _pageController.jumpToPage(_currentPage);
          }
        });
      }
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  void _removeCurrentPhoto() {
    if (_photoPaths.isEmpty) return;
    setState(() {
      _photoPaths.removeAt(_currentPage);
      _currentPage = (_currentPage).clamp(0, (_photoPaths.length - 1).clamp(0, 999));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients && _photoPaths.isNotEmpty) {
        _pageController.jumpToPage(_currentPage);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await BabyRepository.instance.saveEntry(BabyEntry(
      slotKey: widget.slot.key,
      photoPaths: _photoPaths,
      caption: _captionController.text.trim().isNotEmpty
          ? _captionController.text.trim()
          : null,
      updatedAt: DateTime.now(),
    ));
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final milestone = _milestone;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(
                child: Container(
                  width: 36,
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
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (milestone != null)
                          Text(
                            '${milestone.emoji}  ${milestone.label}',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.warmBrown,
                            ),
                          )
                        else
                          Text(
                            _slotTitle(),
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.warmBrown,
                            ),
                          ),
                        Text(
                          _slotSubtitle(),
                          style: GoogleFonts.inter(
                              fontSize: 12, color: AppColors.warmTaupe),
                        ),
                      ],
                    ),
                  ),
                  if (_photoPaths.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      color: AppColors.warmTaupe,
                      tooltip: 'Remove this photo',
                      onPressed: _removeCurrentPhoto,
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: AppColors.warmTaupe,
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Photo gallery (PageView) ─────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _photoPaths.isEmpty
                    ? _emptyState()
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: _photoPaths.length,
                          onPageChanged: (i) =>
                              setState(() => _currentPage = i),
                          itemBuilder: (context, i) =>
                              _buildPhotoPage(_photoPaths[i]),
                        ),
                      ),
              ),
            ),

            // ── Page indicator + thumbnails ──────────────────────────────
            if (_photoPaths.length > 1)
              _ThumbnailStrip(
                paths: _photoPaths,
                current: _currentPage,
                onTap: (i) {
                  setState(() => _currentPage = i);
                  _pageController.animateToPage(i,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut);
                },
              ),

            // ── Add photos button ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: _pickingPhoto
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_photo_alternate_outlined,
                          size: 18),
                  label: Text(_photoPaths.isEmpty
                      ? 'Add a photo'
                      : 'Add another photo'),
                  onPressed: _pickingPhoto ? null : _addPhoto,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.sageGreen,
                    side: const BorderSide(color: AppColors.sageGreen),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),

            // ── Caption ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: TextField(
                controller: _captionController,
                maxLength: 80,
                decoration: InputDecoration(
                  hintText: 'Add a note…',
                  hintStyle: TextStyle(
                      color: AppColors.warmTaupe.withOpacity(0.7)),
                  filled: true,
                  fillColor: AppColors.surface,
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.divider)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.divider)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.sageGreen)),
                ),
              ),
            ),

            // ── Save ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.sageGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.divider,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(
                          _photoPaths.isEmpty
                              ? 'Save'
                              : 'Save  (${_photoPaths.length} photo${_photoPaths.length > 1 ? 's' : ''})',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoPage(String path) {
    Widget img;
    if (kIsWeb || path.startsWith('data:')) {
      final comma = path.indexOf(',');
      img = comma != -1
          ? Image.memory(base64Decode(path.substring(comma + 1)),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity)
          : _emptyState();
    } else {
      img = Image.file(File(path),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity);
    }
    return img;
  }

  Widget _emptyState() {
    return GestureDetector(
      onTap: _addPhoto,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_photo_alternate_outlined,
                  size: 48, color: AppColors.sageGreen.withOpacity(0.7)),
              const SizedBox(height: 10),
              Text('Tap to add a photo',
                  style: GoogleFonts.inter(
                      fontSize: 14, color: AppColors.warmTaupe)),
            ],
          ),
        ),
      ),
    );
  }

  String _slotTitle() {
    switch (widget.slot.kind) {
      case BabyAgeKind.week:
        return widget.slot.value == 0 ? 'Birth Day' : 'Week ${widget.slot.value}';
      case BabyAgeKind.month:
        return 'Month ${widget.slot.value}';
      case BabyAgeKind.year:
        return 'Year ${widget.slot.value}';
    }
  }

  String _slotSubtitle() {
    switch (widget.slot.kind) {
      case BabyAgeKind.week:
        return widget.slot.value == 0
            ? 'Day of birth'
            : '${widget.slot.value * 7} days old';
      case BabyAgeKind.month:
        return '${widget.slot.value} months old';
      case BabyAgeKind.year:
        return '${widget.slot.value} year${widget.slot.value > 1 ? 's' : ''} old';
    }
  }
}

// ─── Thumbnail strip ──────────────────────────────────────────────────────────

class _ThumbnailStrip extends StatelessWidget {
  final List<String> paths;
  final int current;
  final void Function(int) onTap;

  const _ThumbnailStrip(
      {required this.paths, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final selected = i == current;
          return GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? AppColors.sageGreen : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _thumbImage(paths[i]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _thumbImage(String path) {
    if (kIsWeb || path.startsWith('data:')) {
      final comma = path.indexOf(',');
      if (comma != -1) {
        return Image.memory(base64Decode(path.substring(comma + 1)),
            fit: BoxFit.cover);
      }
      return Container(color: AppColors.accentSoft);
    }
    return Image.file(File(path), fit: BoxFit.cover);
  }
}

extension _IterableExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}
