import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/models/inbox_photo_model.dart';
import '../../core/theme/app_colors.dart';
import '../../data/baby_repository.dart';

// Filter options
enum _InboxFilter { baby, all, unscreened }

class BabyInboxScreen extends StatefulWidget {
  const BabyInboxScreen({super.key});

  @override
  State<BabyInboxScreen> createState() => _BabyInboxScreenState();
}

class _BabyInboxScreenState extends State<BabyInboxScreen> {
  _InboxFilter _filter = _InboxFilter.baby;
  final Set<String> _selected = {};
  bool _promoting = false;

  List<InboxPhoto> _filtered(List<InboxPhoto> all) {
    switch (_filter) {
      case _InboxFilter.baby:
        return all.where((p) => p.hasBaby != false).toList();
      case _InboxFilter.unscreened:
        return all.where((p) => p.hasBaby == null).toList();
      case _InboxFilter.all:
        return all;
    }
  }

  // Group photos by slotKey, sorted by slot index
  Map<String, List<InboxPhoto>> _grouped(List<InboxPhoto> photos) {
    final map = <String, List<InboxPhoto>>{};
    for (final p in photos) {
      map.putIfAbsent(p.slotKey, () => []).add(p);
    }
    // Sort each group by date
    for (final list in map.values) {
      list.sort((a, b) => a.date.compareTo(b.date));
    }
    // Sort keys by slot index
    final sorted = map.keys.toList()
      ..sort((a, b) => _slotIndex(a).compareTo(_slotIndex(b)));
    return {for (final k in sorted) k: map[k]!};
  }

  int _slotIndex(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return 9999;
    final v = int.tryParse(parts[1]) ?? 0;
    switch (parts[0]) {
      case 'w': return v;
      case 'm': return 12 + (v - 3);
      case 'y': return 12 + 22 + (v - 2);
      default: return 9999;
    }
  }

  String _slotLabel(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return key;
    final v = int.tryParse(parts[1]) ?? 0;
    switch (parts[0]) {
      case 'w': return v == 0 ? 'Birth Day' : 'Week $v';
      case 'm': return 'Month $v';
      case 'y': return 'Year $v';
      default: return key;
    }
  }

  Future<void> _addToTimeline() async {
    if (_selected.isEmpty) return;
    setState(() => _promoting = true);

    final allPhotos = BabyRepository.instance.getAllInbox();
    final toPromote = allPhotos.where((p) => _selected.contains(p.id)).toList();

    for (final photo in toPromote) {
      await BabyRepository.instance.promoteToTimeline(photo);
    }

    final count = toPromote.length;
    setState(() {
      _selected.clear();
      _promoting = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count photo${count == 1 ? '' : 's'} added to timeline'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<InboxPhoto>>(
      valueListenable: BabyRepository.instance.inboxListenable,
      builder: (context, box, _) {
        final all = box.values.toList();
        final filtered = _filtered(all);
        final grouped = _grouped(filtered);
        final total = filtered.length;
        final unscreenedCount = all.where((p) => p.hasBaby == null).length;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(context, total, unscreenedCount),
                _buildFilterBar(),
                Expanded(
                  child: total == 0
                      ? _buildEmpty()
                      : _buildGrid(grouped),
                ),
                if (_selected.isNotEmpty) _buildBottomBar(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, int total, int unscreenedCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/baby'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Inbox',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warmBrown,
                  ),
                ),
                if (unscreenedCount > 0)
                  Text(
                    '$unscreenedCount being screened by AI…',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.warmTaupe,
                    ),
                  ),
              ],
            ),
          ),
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _selected.clear()),
              child: Text(
                'Deselect all',
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.sageGreen),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          _filterChip('Baby photos', _InboxFilter.baby),
          const SizedBox(width: 8),
          _filterChip('All', _InboxFilter.all),
          const SizedBox(width: 8),
          _filterChip('Unscreened', _InboxFilter.unscreened),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _InboxFilter value) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.sageGreen : AppColors.background,
          border: Border.all(
            color: active ? AppColors.sageGreen : AppColors.warmTaupe.withOpacity(0.4),
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            color: active ? Colors.white : AppColors.warmTaupe,
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined, size: 48, color: AppColors.warmTaupe.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(
            'No photos here',
            style: GoogleFonts.inter(fontSize: 16, color: AppColors.warmTaupe),
          ),
          const SizedBox(height: 4),
          Text(
            'Scan your camera folder to import photos',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.warmTaupe.withOpacity(0.6)),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(Map<String, List<InboxPhoto>> grouped) {
    final slotKeys = grouped.keys.toList();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: slotKeys.length,
      itemBuilder: (context, i) {
        final slotKey = slotKeys[i];
        final photos = grouped[slotKey]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                _slotLabel(slotKey),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.warmTaupe,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
                childAspectRatio: 1,
              ),
              itemCount: photos.length,
              itemBuilder: (context, j) => _buildThumb(photos[j]),
            ),
          ],
        );
      },
    );
  }

  Widget _buildThumb(InboxPhoto photo) {
    final isSelected = _selected.contains(photo.id);
    final isUnscreened = photo.hasBaby == null;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selected.remove(photo.id);
          } else {
            _selected.add(photo.id);
          }
        });
      },
      onLongPress: () => _showFullscreen(photo),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildImage(photo.path),
          // Unscreened shimmer overlay
          if (isUnscreened)
            Container(
              color: Colors.white.withOpacity(0.5),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          // Non-baby dimming
          if (photo.hasBaby == false)
            Container(color: Colors.black.withOpacity(0.5)),
          // Selection overlay
          if (isSelected)
            Container(
              color: AppColors.sageGreen.withOpacity(0.35),
              child: const Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.check_circle, color: Colors.white, size: 20),
                ),
              ),
            ),
          // Milestone star
          if (photo.isMilestone && !isSelected)
            const Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Text('⭐', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImage(String path) {
    if (path.startsWith('server:')) {
      final serverPath = path.substring(7);
      return Image.network(
        'http://localhost:7272/photo?path=${Uri.encodeComponent(serverPath)}',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: AppColors.warmTaupe.withOpacity(0.15)),
      );
    }
    if (path.startsWith('data:')) {
      final commaIdx = path.indexOf(',');
      if (commaIdx != -1) {
        try {
          final bytes = base64Decode(path.substring(commaIdx + 1));
          return Image.memory(bytes, fit: BoxFit.cover);
        } catch (_) {}
      }
    }
    if (!kIsWeb) {
      return Image.file(File(path), fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: AppColors.warmTaupe.withOpacity(0.15)));
    }
    return Container(color: AppColors.warmTaupe.withOpacity(0.15));
  }

  void _showFullscreen(InboxPhoto photo) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: _buildImage(photo.path),
            ),
            // Tags overlay
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: _buildTagsOverlay(photo),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagsOverlay(InboxPhoto photo) {
    final tags = <String>[];
    if (photo.mood != null) tags.add(photo.mood!);
    if (photo.activity != null && photo.activity != 'other') tags.add(photo.activity!);
    if (photo.isMilestone) tags.add('milestone ⭐');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (photo.aiCaption != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '✨ ${photo.aiCaption}',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
            ),
          ),
        if (tags.isNotEmpty)
          Wrap(
            spacing: 4,
            children: tags.map((t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(t, style: GoogleFonts.inter(color: Colors.white, fontSize: 12)),
            )).toList(),
          ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final count = _selected.length;
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$count photo${count == 1 ? '' : 's'} selected',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.warmBrown,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: _promoting ? null : _addToTimeline,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.sageGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _promoting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Add to timeline', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
