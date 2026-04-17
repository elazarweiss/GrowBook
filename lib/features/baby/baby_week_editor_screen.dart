import 'dart:convert';
import 'dart:io';
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
  String? _activeFilter;
  final Set<String> _selectedIds = {};
  bool _loadingFromServer = false;
  bool _tagging = false;
  // Burst groups that the user has expanded to see all photos
  final Set<String> _expandedBursts = {};

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  // ── Data loading ─────────────────────────────────────────────────────────────

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
    });

    if (kIsWeb) await _fetchFromServer();
    _tagPhotos();
  }

  Future<void> _fetchFromServer() async {
    if (mounted) setState(() => _loadingFromServer = true);
    try {
      final incoming = await BabyScanController.fetchPhotosForSlot(widget.slot);
      bool added = false;
      for (final photo in incoming) {
        if (BabyRepository.instance.getInboxPhoto(photo.id) == null) {
          await BabyRepository.instance.saveInboxPhoto(photo);
          added = true;
        }
      }
      if (added && mounted) {
        setState(() {
          _photos = BabyRepository.instance.getInboxForSlot(widget.slot.key);
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

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<void> _pinToTimeline() async {
    final selected = _photos.where((p) => _selectedIds.contains(p.id)).toList();
    await BabyRepository.instance.setFeaturedPhotos(widget.slot.key, selected);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          '${selected.length} photo${selected.length == 1 ? '' : 's'} pinned to ${_slotLabel()}'),
      behavior: SnackBarBehavior.floating,
    ));
    Navigator.of(context).pop();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

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
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  List<InboxPhoto> get _visiblePhotos {
    final baby = _photos.where((p) => p.hasBaby != false).toList();
    if (_activeFilter == null) return baby;
    if (_activeFilter == 'milestone') return baby.where((p) => p.isMilestone).toList();
    return baby.where((p) => p.mood == _activeFilter || p.activity == _activeFilter).toList();
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
      'tummy_time': '🤸 Tummy',
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

  // ── Day grouping ──────────────────────────────────────────────────────────────

  /// Groups a photo list by calendar day (yyyy-MM-dd), sorted chronologically.
  static Map<String, List<InboxPhoto>> _groupByDay(List<InboxPhoto> photos) {
    final groups = <String, List<InboxPhoto>>{};
    for (final photo in photos) {
      final key =
          '${photo.date.year}-${photo.date.month.toString().padLeft(2, '0')}-${photo.date.day.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(photo);
    }
    return Map.fromEntries(
      groups.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  static String _dayLabel(String dateKey) {
    final parts = dateKey.split('-');
    final dt = DateTime(
        int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${weekdays[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final visible = _visiblePhotos;
    final allBaby = _photos.where((p) => p.hasBaby != false).toList();
    final filters = _availableFilters;

    return Scaffold(
      backgroundColor: const Color(0xFFF5EFE6),
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
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.warmTaupe),
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
                : _buildGrid(allBaby, visible),
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

  // ── Grid grouped by day ───────────────────────────────────────────────────────

  /// Returns the display list for a day, respecting burst collapse state.
  /// Collapsed bursts show only the representative; expanded bursts show all.
  List<InboxPhoto> _displayPhotosForDay(List<InboxPhoto> dayPhotos) {
    final result = <InboxPhoto>[];
    for (final photo in dayPhotos) {
      if (photo.burstId == null) {
        result.add(photo); // standalone
      } else if (photo.burstRepresentative) {
        result.add(photo); // burst cover — always shown
      } else if (_expandedBursts.contains(photo.burstId)) {
        result.add(photo); // expanded burst member
      }
      // else: collapsed burst non-representative — skip
    }
    return result;
  }

  /// How many non-representative photos are hidden in a burst group for a day.
  int _burstHiddenCount(List<InboxPhoto> dayPhotos, String burstId) =>
      dayPhotos.where((p) => p.burstId == burstId && !p.burstRepresentative).length;

  Widget _buildGrid(List<InboxPhoto> allBaby, List<InboxPhoto> visible) {
    final days = _groupByDay(allBaby);

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      child: CustomScrollView(
        slivers: [
          for (final entry in days.entries) ...[
            // Day header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                child: Row(
                  children: [
                    Text(
                      _dayLabel(entry.key),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warmBrown,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${entry.value.length} photo${entry.value.length == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: AppColors.warmTaupe),
                    ),
                  ],
                ),
              ),
            ),
            // Photo grid for this day (burst-aware)
            Builder(builder: (ctx) {
              final displayed = _displayPhotosForDay(entry.value);
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (ctx2, i) {
                      final photo = displayed[i];
                      final isBurstCover = photo.burstId != null &&
                          photo.burstRepresentative;
                      final hiddenCount = isBurstCover
                          ? _burstHiddenCount(entry.value, photo.burstId!)
                          : 0;
                      return _buildPhotoCard(
                        photo: photo,
                        dimmed: !visible.contains(photo),
                        burstHiddenCount: hiddenCount,
                        burstExpanded: photo.burstId != null &&
                            _expandedBursts.contains(photo.burstId),
                      );
                    },
                    childCount: displayed.length,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 0.82,
                  ),
                ),
              );
            }),
          ],
          // Bottom padding so last row clears the pin bar
          const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ],
      ),
    );
  }

  Widget _buildPhotoCard({
    required InboxPhoto photo,
    required bool dimmed,
    int burstHiddenCount = 0,
    bool burstExpanded = false,
  }) {
    final isSelected = _selectedIds.contains(photo.id);
    final hasTag = photo.mood != null || photo.activity != null;
    final isBurstCover = photo.burstId != null && photo.burstRepresentative;

    return GestureDetector(
      onTap: () {
        if (dimmed) {
          setState(() => _activeFilter = null);
          return;
        }
        // Long-press expands burst; tap selects
        setState(() {
          if (isSelected) {
            _selectedIds.remove(photo.id);
          } else {
            _selectedIds.add(photo.id);
          }
        });
      },
      onLongPress: isBurstCover && burstHiddenCount > 0
          ? () => setState(() {
                if (burstExpanded) {
                  _expandedBursts.remove(photo.burstId);
                } else {
                  _expandedBursts.add(photo.burstId!);
                }
              })
          : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: dimmed ? 0.25 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: isSelected
                ? Border.all(color: AppColors.sageGreen, width: 2.5)
                : Border.all(color: Colors.black.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4)),
                      child: _buildImage(photo.path),
                    ),
                    if (photo.isMilestone)
                      const Positioned(
                        top: 4,
                        left: 4,
                        child: Text('⭐', style: TextStyle(fontSize: 12)),
                      ),
                    // Burst badge: "📷+3  hold" when collapsed
                    if (isBurstCover && burstHiddenCount > 0)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withOpacity(0.65),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Center(
                            child: Text(
                              burstExpanded
                                  ? '📷 hold to collapse'
                                  : '📷 +$burstHiddenCount similar',
                              style: const TextStyle(
                                  fontSize: 8, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    if (isSelected)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: AppColors.sageGreen,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check,
                              color: Colors.white, size: 12),
                        ),
                      ),
                    // Spinner overlay for unscreened photos
                    if (photo.hasBaby == null)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.55),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4)),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Tag line
              if (hasTag)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Text(
                    _tagLine(photo),
                    style: GoogleFonts.inter(
                        fontSize: 9, color: AppColors.warmTaupe),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const SizedBox(height: 6),
            ],
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

  Widget _buildImage(String path) {
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
              base64Decode(path.substring(comma + 1)), fit: BoxFit.cover);
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
              size: 48, color: AppColors.warmTaupe.withOpacity(0.4)),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
