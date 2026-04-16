import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/models/baby_entry_model.dart';
import '../../core/models/baby_journey_model.dart';
import '../../core/models/baby_slot_model.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/baby_timeline_utils.dart';
import '../../data/baby_data.dart';
import '../../data/baby_repository.dart';
import 'baby_scan_controller.dart';
import 'widgets/baby_clothesline_painter.dart';
import 'widgets/baby_photo_polaroid.dart';

class BabyOverviewScreen extends StatefulWidget {
  const BabyOverviewScreen({super.key});

  @override
  State<BabyOverviewScreen> createState() => _BabyOverviewScreenState();
}

class _BabyOverviewScreenState extends State<BabyOverviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (BabyRepository.instance.getJourney() == null) {
        context.go('/baby/setup');
        return;
      }
      // Background auto-scan: silently pick up new photos if server is running
      if (kIsWeb) {
        final folder = BabyRepository.instance.cameraFolderPath;
        if (folder != null) {
          final running = await BabyScanController.checkServerRunning();
          if (running) _autoScanBackground();
        }
      }
    });
  }

  Future<void> _autoScanBackground() async {
    try {
      final journey = BabyRepository.instance.getJourney();
      if (journey == null) return;
      final lastScan = BabyRepository.instance.lastScanAt;
      final proposals = await BabyScanController.scan(
        folderPath: BabyRepository.instance.cameraFolderPath ?? '',
        birthDate: journey.birthDate,
        sinceDate: lastScan,
      );
      if (proposals.isEmpty) return;
      // Auto-select all candidates
      for (final p in proposals) {
        for (final c in p.candidates) {
          c.selected = true;
        }
      }
      await BabyScanController.saveSelected(proposals);
      BabyScanController.screenInbox();
    } catch (_) {
      // Best-effort — never surface errors to user
    }
  }

  @override
  Widget build(BuildContext context) {
    final journey = BabyRepository.instance.getJourney();
    if (journey == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: ValueListenableBuilder(
              valueListenable: BabyRepository.instance.inboxListenable,
              builder: (context, _, __) => _buildHeader(journey),
            ),
          ),
          Expanded(child: _BabyClotheslineTimeline(journey: journey)),
        ],
      ),
    );
  }

  Widget _buildHeader(BabyJourney journey) {
    final ageLabel = _ageDescription(journey);
    final hasFolderConfigured =
        BabyRepository.instance.cameraFolderPath != null;
    final inboxCount = BabyRepository.instance.inboxBabyCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 4, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  journey.babyName,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warmBrown,
                  ),
                ),
                const SizedBox(width: 10),
                Text(ageLabel,
                    style: GoogleFonts.inter(
                        fontSize: 13, color: AppColors.warmTaupe)),
              ],
            ),
          ),
          // Inbox button with badge
          Tooltip(
            message: 'Review inbox photos',
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                IconButton(
                  icon: const Icon(Icons.inbox_outlined),
                  color: inboxCount > 0 ? AppColors.warmBrown : AppColors.warmTaupe,
                  onPressed: () => context.push('/baby/inbox'),
                ),
                if (inboxCount > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        inboxCount > 99 ? '99+' : '$inboxCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Auto-scan button
          Tooltip(
            message: hasFolderConfigured
                ? 'Scan camera folder for new photos'
                : 'Set up auto-import from camera folder',
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                IconButton(
                  icon: const Icon(Icons.auto_awesome_outlined),
                  color: AppColors.sageGreen,
                  onPressed: () => context.push('/baby/scan'),
                ),
                if (hasFolderConfigured)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.sageGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Manual multi-file import
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            color: AppColors.warmTaupe,
            tooltip: 'Pick photos manually',
            onPressed: () => context.push('/baby/import'),
          ),
        ],
      ),
    );
  }

  String _ageDescription(BabyJourney journey) {
    final days = journey.ageInDays;
    if (days < 84) return '${(days / 7).floor()} weeks old';
    final months = (days / 30.44).floor();
    if (months <= 24) return '$months months old';
    return '${(days / 365).floor()} years old';
  }
}

// ─── Clothesline Timeline ──────────────────────────────────────────────────────

class _BabyClotheslineTimeline extends StatefulWidget {
  final BabyJourney journey;
  const _BabyClotheslineTimeline({required this.journey});

  @override
  State<_BabyClotheslineTimeline> createState() =>
      _BabyClotheslineTimelineState();
}

class _BabyClotheslineTimelineState extends State<_BabyClotheslineTimeline> {
  late final ScrollController _scrollController;
  late List<BabySlot> _slots;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _slots = BabyTimelineUtils.generateSlots(widget.journey.birthDate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrentSlot());
  }

  void _scrollToCurrentSlot() {
    if (!_scrollController.hasClients) return;
    final current = widget.journey.currentSlot;
    final slot =
        _slots.where((s) => s.key == current.key).firstOrNull ?? _slots.last;
    final x = BabyTimelineUtils.xForSlot(slot, _slots);
    final vw = _scrollController.position.viewportDimension;
    final maxS = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo((x - vw / 2).clamp(0.0, maxS));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<BabyEntry>>(
      valueListenable: BabyRepository.instance.entriesListenable,
      builder: (context, box, _) {
        _slots = BabyTimelineUtils.generateSlots(widget.journey.birthDate);
        final currentSlot = widget.journey.currentSlot;
        final totalW = BabyTimelineUtils.totalWidth(_slots);
        final milestoneKeys = kMilestonesBySlot.keys.toSet();

        return LayoutBuilder(builder: (context, constraints) {
          final double canvasH = constraints.maxHeight;
          final double canvasW = math.max(totalW, constraints.maxWidth);
          // Wire sits at 48% — even split between above and below polaroids
          final double lineY = canvasH * 0.48;

          return ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              width: canvasW,
              height: canvasH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // ── Wire (full canvas width, edge to edge) ───────────────
                  Positioned(
                    left: 0,
                    right: 0,
                    top: lineY - 1,
                    child: IgnorePointer(
                      child: Container(height: 2, color: AppColors.divider),
                    ),
                  ),

                  // ── Ticks + current-slot ring ─────────────────────────────
                  CustomPaint(
                    size: Size(canvasW, canvasH),
                    painter: BabyClotheslinePainter(
                      slots: _slots,
                      currentSlot: currentSlot,
                      lineY: lineY,
                      milestoneKeys: milestoneKeys,
                    ),
                  ),

                  // ── Phase section labels (higher, colored) ─────────────────
                  ..._phaseLabels(_slots, lineY),

                  // ── Photo polaroids (multi per slot) ──────────────────────
                  ..._buildPolaroids(context, box, canvasH, lineY),
                ],
              ),
            ),
          ),  // SingleChildScrollView
          );  // ScrollConfiguration
        });
      },
    );
  }

  List<Widget> _buildPolaroids(
    BuildContext context,
    Box<BabyEntry> box,
    double canvasH,
    double lineY,
  ) {
    final widgets = <Widget>[];

    for (final slot in _slots) {
      final entry = box.get(slot.key);
      final milestone = kMilestonesBySlot[slot.key];
      final x = BabyTimelineUtils.xForSlot(slot, _slots);

      final hasPhotos = entry != null && entry.photoPaths.isNotEmpty;

      if (!hasPhotos) {
        // Ghost card for milestone slots only
        if (milestone != null) {
          widgets.add(BabyPhotoPolaroid(
            key: ValueKey('ghost-${slot.key}'),
            slot: slot,
            photoPath: null,
            caption: null,
            photoCount: 0,
            onTap: () => context.push('/baby/slot/${slot.key}'),
            x: x,
            lineY: lineY,
            canvasH: canvasH,
            photoIndex: 0,
            xOffset: 0,
            yFactor: 0.70,
            milestone: milestone,
          ));
        }
        continue;
      }

      final count = entry.photoPaths.length.clamp(1, 3);
      for (int i = 0; i < count; i++) {
        final layout = BabyPhotoPolaroid.layouts[i];
        widgets.add(BabyPhotoPolaroid(
          key: ValueKey('${slot.key}-$i'),
          slot: slot,
          photoPath: entry.photoPaths[i],
          caption: i == 0 ? entry.caption : null,
          photoCount: entry.photoPaths.length,
          onTap: () => context.push('/baby/slot/${slot.key}'),
          x: x,
          lineY: lineY,
          canvasH: canvasH,
          photoIndex: i,
          xOffset: layout.xOffset,
          yFactor: layout.yFactor,
          isAboveOverride: layout.isAbove,
          sizeFactor: i == 2 ? 0.82 : 1.0,
          milestone: i == 0 ? milestone : null,
        ));
      }
    }

    return widgets;
  }

  static List<Widget> _phaseLabels(List<BabySlot> slots, double lineY) {
    final phases = [
      ('NEWBORN', BabyAgeKind.week, 0, AppColors.babyBlush),
      ('INFANT', BabyAgeKind.month, 3, AppColors.babyMint),
      ('TODDLER', BabyAgeKind.year, 2, AppColors.babySunrise),
    ];
    return phases.map((rec) {
      final (label, kind, value, color) = rec;
      final slot =
          slots.where((s) => s.kind == kind && s.value == value).firstOrNull;
      if (slot == null) return const SizedBox.shrink();
      final x = BabyTimelineUtils.xForSlot(slot, slots);
      return Positioned(
        left: x - 4,
        top: lineY - 52,
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            color: color.withOpacity(0.85),
          ),
        ),
      );
    }).toList();
  }
}

extension _IterableExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}
