import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/models/baby_entry_model.dart';
import '../../core/models/baby_journey_model.dart';
import '../../core/models/baby_slot_model.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/baby_timeline_utils.dart';
import '../../data/baby_data.dart';
import '../../data/baby_repository.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (BabyRepository.instance.getJourney() == null && mounted) {
        context.go('/baby/setup');
      }
    });
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SafeArea(
            bottom: false,
            child: _buildHeader(journey),
          ),
          Expanded(child: _BabyClotheslineTimeline(journey: journey)),
          const SafeArea(top: false, child: SizedBox(height: 8)),
        ],
      ),
    );
  }

  Widget _buildHeader(BabyJourney journey) {
    final current = journey.currentSlot;
    final ageLabel = _ageDescription(journey);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.md, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  journey.babyName,
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warmBrown,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$ageLabel  ·  ${current.label}',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.warmTaupe),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            color: AppColors.sageGreen,
            tooltip: 'Import photos',
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

// ─── Baby Clothesline Timeline ─────────────────────────────────────────────────

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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToCurrentSlot());
  }

  void _scrollToCurrentSlot() {
    if (!_scrollController.hasClients) return;
    final current = widget.journey.currentSlot;
    final slot = _slots.where((s) => s.key == current.key).firstOrNull ??
        _slots.last;
    final x = BabyTimelineUtils.xForSlot(slot, _slots);
    final viewportWidth = _scrollController.position.viewportDimension;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final target = (x - viewportWidth / 2).clamp(0.0, maxScroll);
    _scrollController.jumpTo(target);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  static String _humanLabel(BabySlot slot) {
    switch (slot.kind) {
      case BabyAgeKind.week:
        if (slot.value == 0) return 'Birth';
        if (slot.value % 4 == 0) return '${slot.value} wk';
        return '';
      case BabyAgeKind.month:
        if (slot.value % 3 != 0) return '';
        if (slot.value == 12) return '1 yr';
        if (slot.value == 24) return '2 yr';
        return '${slot.value} mo';
      case BabyAgeKind.year:
        return '${slot.value} yr';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<BabyEntry>>(
      valueListenable: BabyRepository.instance.entriesListenable,
      builder: (context, box, _) {
        _slots = BabyTimelineUtils.generateSlots(widget.journey.birthDate);
        final currentSlot = widget.journey.currentSlot;
        final totalW = BabyTimelineUtils.totalWidth(_slots);

        final milestoneMap = {
          for (final m in babyMilestones) m.slotKey: m,
        };

        return LayoutBuilder(
          builder: (context, constraints) {
            final double canvasH = constraints.maxHeight;
            final double lineY = canvasH * 0.50;

            return SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: SizedBox(
                width: totalW,
                height: canvasH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // ── Ticks + current-slot indicator ──────────────────────
                    CustomPaint(
                      size: Size(totalW, canvasH),
                      painter: BabyClotheslinePainter(
                        slots: _slots,
                        currentSlot: currentSlot,
                        lineY: lineY,
                      ),
                    ),

                    // ── Clean single-color wire ──────────────────────────────
                    Positioned(
                      left: 0,
                      right: 0,
                      top: lineY - 1,
                      child: IgnorePointer(
                        child: Container(
                          height: 2,
                          color: AppColors.divider,
                        ),
                      ),
                    ),

                    // ── Slot labels below ticks ───────────────────────────────
                    ..._slots.map((slot) {
                      final x = BabyTimelineUtils.xForSlot(slot, _slots);
                      final milestone = milestoneMap[slot.key];
                      final label = _humanLabel(slot);
                      if (label.isEmpty && milestone == null) {
                        return const SizedBox.shrink();
                      }
                      return Positioned(
                        left: x - 24,
                        top: lineY + 14,
                        child: SizedBox(
                          width: 48,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (milestone != null)
                                Text(
                                  milestone.emoji,
                                  style: const TextStyle(fontSize: 10),
                                  textAlign: TextAlign.center,
                                ),
                              if (label.isNotEmpty)
                                Text(
                                  label,
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.warmTaupe,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                            ],
                          ),
                        ),
                      );
                    }),

                    // ── Photo polaroids ───────────────────────────────────────
                    ..._slots.map((slot) {
                      final entry = box.get(slot.key);
                      final x = BabyTimelineUtils.xForSlot(slot, _slots);
                      return BabyPhotoPolaroid(
                        key: ValueKey(slot.key),
                        slot: slot,
                        photoPath: entry?.photoPaths.isNotEmpty == true
                            ? entry!.photoPaths.first
                            : null,
                        caption: entry?.caption,
                        x: x,
                        lineY: lineY,
                        onTap: () => _openEntry(slot),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openEntry(BabySlot slot) {
    context.push('/baby/slot/${slot.key}');
  }
}

extension _IterableExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}
