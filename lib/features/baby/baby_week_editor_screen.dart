import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/baby_slot_model.dart';
import '../../core/models/inbox_photo_model.dart';
import '../../core/theme/app_colors.dart';
import '../../data/baby_repository.dart';
import 'baby_scan_controller.dart';

class BabyWeekEditorScreen extends StatefulWidget {
  final BabySlot slot;
  const BabyWeekEditorScreen({super.key, required this.slot});

  @override
  State<BabyWeekEditorScreen> createState() => _BabyWeekEditorScreenState();
}

class _BabyWeekEditorScreenState extends State<BabyWeekEditorScreen> {
  List<InboxPhoto> _photos = [];
  String? _activeFilter;          // null = all
  final Set<String> _selectedIds = {};
  bool _loadingFromServer = false;
  bool _tagging = false;
  List<_PhotoLayout> _layouts = const [];

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  // ── Data loading ────────────────────────────────────────────────────────────

  Future<void> _loadPhotos() async {
    final existing = BabyRepository.instance.getInboxForSlot(widget.slot.key);
    final featured =
        BabyRepository.instance.getEntry(widget.slot.key)?.photoPaths.toSet() ??
            {};

    setState(() {
      _photos = existing;
      _selectedIds
        ..clear()
        ..addAll(existing.where((p) => featured.contains(p.path)).map((p) => p.id));
      _layouts = _buildLayouts(existing.length);
    });

    if (kIsWeb) await _fetchFromServer();
    _tagPhotos();
  }

  Future<void> _fetchFromServer() async {
    if (mounted) setState(() => _loadingFromServer = true);
    try {
      final incoming =
          await BabyScanController.fetchPhotosForSlot(widget.slot);
      bool added = false;
      for (final photo in incoming) {
        if (BabyRepository.instance.getInboxPhoto(photo.id) == null) {
          await BabyRepository.instance.saveInboxPhoto(photo);
          added = true;
        }
      }
      if (added && mounted) {
        final updated =
            BabyRepository.instance.getInboxForSlot(widget.slot.key);
        setState(() {
          _photos = updated;
          _layouts = _buildLayouts(updated.length);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingFromServer = false);
  }

  Future<void> _tagPhotos() async {
    // Run full tagging only for baby photos that don't yet have mood/activity tags
    final hasUntagged = BabyRepository.instance
        .getInboxForSlot(widget.slot.key)
        .any((p) => p.hasBaby == true && p.mood == null);
    if (!hasUntagged) return;

    if (mounted) setState(() => _tagging = true);
    await BabyScanController.screenInboxSlot(widget.slot.key);
    if (!mounted) return;
    setState(() {
      _photos = BabyRepository.instance.getInboxForSlot(widget.slot.key);
      _tagging = false;
    });
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _pinToTimeline() async {
    final selected =
        _photos.where((p) => _selectedIds.contains(p.id)).toList();
    await BabyRepository.instance.setFeaturedPhotos(
      widget.slot.key,
      selected,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          '${selected.length} photo${selected.length == 1 ? '' : 's'} pinned to ${_slotLabel()}'),
      behavior: SnackBarBehavior.floating,
    ));
    Navigator.of(context).pop();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _slotLabel() {
    final v = widget.slot.value;
    switch (widget.slot.kind) {
      case BabyAgeKind.week:
        return v == 0 ? 'Birth Day' : 'Week $v';
      case BabyAgeKind.month:
        return 'Month $v';
      case BabyAgeKind.year:
        return 'Year $v';
    }
  }

  String _dateRange() {
    final birth = BabyRepository.instance.getJourney()?.birthDate;
    if (birth == null) return '';
    final slot = widget.slot;
    final DateTime start;
    final DateTime end;
    if (slot.kind == BabyAgeKind.week) {
      start = birth.add(Duration(days: slot.value * 7));
      end = start.add(const Duration(days: 6));
    } else if (slot.kind == BabyAgeKind.month) {
      start = birth.add(Duration(days: (slot.value * 30.44).round()));
      end = start.add(const Duration(days: 30));
    } else {
      start = birth.add(Duration(days: slot.value * 365));
      end = start.add(const Duration(days: 364));
    }
    return '${_fmt(start)} – ${_fmt(end)}';
  }

  static String _fmt(DateTime d) {
    const m = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${m[d.month - 1]} ${d.day}';
  }

  List<InboxPhoto> get _visiblePhotos {
    final baby = _photos.where((p) => p.hasBaby != false).toList();
    if (_activeFilter == null) return baby;
    if (_activeFilter == 'milestone') {
      return baby.where((p) => p.isMilestone).toList();
    }
    return baby
        .where((p) => p.mood == _activeFilter || p.activity == _activeFilter)
        .toList();
  }

  Set<String> get _availableFilters {
    final tags = <String>{};
    for (final p in _photos.where((p) => p.hasBaby == true)) {
      if (p.mood != null) tags.add(p.mood!);
      if (p.activity != null && p.activity != 'other') tags.add(p.activity!);
      if (p.isMilestone) tags.add('milestone');
    }
    return tags;
  }

  static String _filterLabel(String f) {
    const labels = {
      'happy': '😊 Happy',
      'calm': '😌 Calm',
      'sleeping': '🌙 Sleeping',
      'crying': '😢 Crying',
      'silly': '😜 Silly',
      'surprised': '😲 Surprised',
      'bath': '🛁 Bath',
      'feeding': '🍼 Feeding',
      'play': '🎈 Play',
      'outdoors': '🌿 Outdoors',
      'tummy_time': '🤸 Tummy time',
      'reading': '📚 Reading',
      'travel': '✈️ Travel',
      'milestone': '⭐ Milestone',
    };
    return labels[f] ?? f;
  }

  static String _moodEmoji(String mood) {
    const map = {
      'happy': '😊', 'calm': '😌', 'sleeping': '🌙',
      'crying': '😢', 'silly': '😜', 'surprised': '😲',
    };
    return map[mood] ?? mood;
  }

  // ── Layout algorithm ─────────────────────────────────────────────────────────

  static const _widths = [88.0, 112.0, 148.0];

  static List<_PhotoLayout> _buildLayouts(int count) {
    if (count == 0) return const [];
    final rand = math.Random(31415); // fixed seed = stable positions
    final layouts = <_PhotoLayout>[];

    // Loose 2-column grid with generous scatter
    for (int i = 0; i < count; i++) {
      final col = i % 2;
      final row = i ~/ 2;
      final w = _widths[rand.nextInt(3)];

      // Horizontal: left column ~0-120, right column ~130-260, with overlap
      final x = col == 0
          ? 12 + rand.nextDouble() * 100
          : 130 + rand.nextDouble() * 110;
      // Vertical: 190px per row with ±55px scatter
      final y = row * 190.0 + rand.nextDouble() * 55 + 12;
      // Artsy tilt: ±14°
      final angle = (rand.nextDouble() - 0.5) * 28 * math.pi / 180;

      layouts.add(_PhotoLayout(x: x, y: y, w: w, angle: angle));
    }
    return layouts;
  }

  double get _canvasHeight {
    if (_layouts.isEmpty) return 320;
    double max = 0;
    for (final l in _layouts) {
      max = math.max(max, l.y + l.w * 1.35 + 44);
    }
    return max + 60;
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final visible = _visiblePhotos;
    final allBaby = _photos.where((p) => p.hasBaby != false).toList();
    final filters = _availableFilters;

    return Scaffold(
      backgroundColor: const Color(0xFFF5EFE6), // warm cream
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5EFE6),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: AppColors.warmBrown,
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _slotLabel(),
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.warmBrown,
              ),
            ),
            Text(
              _dateRange(),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.warmTaupe,
              ),
            ),
          ],
        ),
        actions: [
          if (_tagging || _loadingFromServer)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _tagging ? 'Analyzing…' : 'Loading…',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppColors.warmTaupe),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (filters.isNotEmpty) _buildFilterBar(filters),
          Expanded(
            child: allBaby.isEmpty && !_loadingFromServer
                ? _buildEmpty()
                : _buildCanvas(allBaby, visible),
          ),
          if (_selectedIds.isNotEmpty) _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildFilterBar(Set<String> filters) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          _chip(null, 'All'),
          ...filters.map((f) => _chip(f, _filterLabel(f))),
        ],
      ),
    );
  }

  Widget _chip(String? value, String label) {
    final active = _activeFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _activeFilter = active ? null : value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: active ? AppColors.sageGreen : Colors.transparent,
            border: Border.all(
              color: active
                  ? AppColors.sageGreen
                  : AppColors.warmTaupe.withOpacity(0.35),
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: active ? Colors.white : AppColors.warmTaupe,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas(List<InboxPhoto> allBaby, List<InboxPhoto> visible) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 120),
        child: SizedBox(
          height: _canvasHeight,
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (int i = 0; i < allBaby.length && i < _layouts.length; i++)
                _buildPhotoCard(
                  photo: allBaby[i],
                  layout: _layouts[i],
                  dimmed: !visible.contains(allBaby[i]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoCard({
    required InboxPhoto photo,
    required _PhotoLayout layout,
    required bool dimmed,
  }) {
    final isSelected = _selectedIds.contains(photo.id);
    final w = layout.w;
    final imgH = w * 1.25;
    final hasTag = photo.mood != null || photo.activity != null;

    return Positioned(
      left: layout.x,
      top: layout.y,
      child: GestureDetector(
        onTap: () {
          if (dimmed) {
            setState(() => _activeFilter = null);
            return;
          }
          setState(() {
            if (isSelected) {
              _selectedIds.remove(photo.id);
            } else {
              _selectedIds.add(photo.id);
            }
          });
        },
        child: Opacity(
          opacity: dimmed ? 0.22 : 1.0,
          child: Transform.rotate(
            angle: layout.angle,
            child: Container(
              width: w + 12,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
                border: isSelected
                    ? Border.all(color: AppColors.sageGreen, width: 3)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.20),
                    blurRadius: 14,
                    offset: const Offset(2, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: SizedBox(
                            width: w,
                            height: imgH,
                            child: _buildImage(photo.path, w, imgH),
                          ),
                        ),
                        if (photo.isMilestone)
                          const Positioned(
                            top: 4,
                            left: 4,
                            child: Text('⭐',
                                style: TextStyle(fontSize: 14)),
                          ),
                        if (isSelected)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(
                                color: AppColors.sageGreen,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check,
                                  color: Colors.white, size: 14),
                            ),
                          ),
                        if (photo.hasBaby == null)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: hasTag ? null : 10,
                    child: hasTag
                        ? Padding(
                            padding:
                                const EdgeInsets.fromLTRB(5, 4, 5, 6),
                            child: Text(
                              _tagLine(photo),
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                color: AppColors.warmTaupe,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _tagLine(InboxPhoto photo) {
    final parts = <String>[];
    if (photo.mood != null) parts.add(_moodEmoji(photo.mood!));
    if (photo.activity != null && photo.activity != 'other') {
      parts.add(photo.activity!.replaceAll('_', ' '));
    }
    return parts.join(' · ');
  }

  Widget _buildImage(String path, double w, double h) {
    if (path.startsWith('server:')) {
      return Image.network(
        'http://localhost:7272/photo?path=${Uri.encodeComponent(path.substring(7))}',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    if (path.startsWith('data:')) {
      final comma = path.indexOf(',');
      if (comma != -1) {
        try {
          return Image.memory(
              base64Decode(path.substring(comma + 1)),
              fit: BoxFit.cover);
        } catch (_) {}
      }
    }
    if (!kIsWeb) {
      return Image.file(File(path),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder());
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        color: AppColors.accentSoft,
        child: const Center(
          child: Icon(Icons.photo, color: AppColors.sageGreen, size: 24),
        ),
      );

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined,
              size: 48,
              color: AppColors.warmTaupe.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text('No photos for this week yet',
              style: GoogleFonts.inter(
                  fontSize: 16, color: AppColors.warmTaupe)),
          const SizedBox(height: 6),
          Text(
            kIsWeb
                ? 'Start the scanner to find photos'
                : 'Tap + to add photos manually',
            style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.warmTaupe.withOpacity(0.6)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final count = _selectedIds.length;
    return Container(
      color: const Color(0xFFF5EFE6),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$count selected',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppColors.warmBrown,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _pinToTimeline,
              icon: const Icon(Icons.push_pin_outlined, size: 18),
              label: Text('Pin to ${_slotLabel()}',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.sageGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoLayout {
  final double x, y, w, angle;
  const _PhotoLayout(
      {required this.x,
      required this.y,
      required this.w,
      required this.angle});
}
