import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/baby_slot_model.dart';
import '../../core/models/import_proposal_model.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/baby_repository.dart';
import 'baby_import_controller.dart';

class BabyImportScreen extends StatefulWidget {
  final List<ImportProposal> proposals;

  const BabyImportScreen({super.key, required this.proposals});

  @override
  State<BabyImportScreen> createState() => _BabyImportScreenState();
}

class _BabyImportScreenState extends State<BabyImportScreen> {
  late final List<ImportProposal> _proposals;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _proposals = widget.proposals;
  }

  int get _selectedCount => _proposals
      .expand((p) => p.candidates)
      .where((c) => c.selected)
      .length;

  Future<void> _import() async {
    setState(() => _saving = true);
    try {
      await BabyImportController.saveSelected(_proposals);
      BabyImportController.currentSession = null;
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.md, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Review Photos',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warmBrown,
                      ),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 4, AppSpacing.lg, AppSpacing.md),
              child: Text(
                'Tap photos to deselect. Selected photos will be added to the timeline.',
                style:
                    AppTypography.bodySmall.copyWith(color: AppColors.warmTaupe),
              ),
            ),

            // Proposals list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                itemCount: _proposals.length,
                itemBuilder: (context, i) =>
                    _SlotImportCard(proposal: _proposals[i]),
              ),
            ),

            // Bottom import button
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selectedCount > 0 && !_saving ? _import : null,
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
                      : Text(
                          'Import $_selectedCount photo${_selectedCount == 1 ? '' : 's'}',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotImportCard extends StatefulWidget {
  final ImportProposal proposal;
  const _SlotImportCard({required this.proposal});

  @override
  State<_SlotImportCard> createState() => _SlotImportCardState();
}

class _SlotImportCardState extends State<_SlotImportCard> {
  bool get _isUnassigned => widget.proposal.slot.index < 0;

  String get _slotTitle {
    if (_isUnassigned) return 'Unassigned';
    final slot = widget.proposal.slot;
    switch (slot.kind) {
      case BabyAgeKind.week:
        return slot.value == 0 ? 'Birth' : 'Week ${slot.value}';
      case BabyAgeKind.month:
        return 'Month ${slot.value}';
      case BabyAgeKind.year:
        return 'Year ${slot.value}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isUnassigned
                        ? AppColors.surface
                        : AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _slotTitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _isUnassigned
                          ? AppColors.warmTaupe
                          : AppColors.sageGreen,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${widget.proposal.candidates.length} photo${widget.proposal.candidates.length == 1 ? '' : 's'}',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.warmTaupe),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
              itemCount: widget.proposal.candidates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final candidate = widget.proposal.candidates[i];
                return _ThumbnailTile(
                  candidate: candidate,
                  onToggle: () => setState(() {
                    candidate.selected = !candidate.selected;
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ThumbnailTile extends StatelessWidget {
  final ImportCandidate candidate;
  final VoidCallback onToggle;

  const _ThumbnailTile({required this.candidate, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (candidate.file.bytes != null) {
      image = Image.memory(
        candidate.file.bytes!,
        width: 80,
        height: 80,
        fit: BoxFit.cover,
      );
    } else {
      image = Container(
        width: 80,
        height: 80,
        color: AppColors.surface,
        child: const Icon(Icons.image_outlined, color: AppColors.warmTaupe),
      );
    }

    return GestureDetector(
      onTap: onToggle,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Opacity(
              opacity: candidate.selected ? 1.0 : 0.35,
              child: image,
            ),
          ),
          if (candidate.selected)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.sageGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 13, color: Colors.white),
              ),
            ),
          if (!candidate.selected)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.divider),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Entry point widget used by the router ─────────────────────────────────────
// The router creates this; it reads from BabyImportController.currentSession.

class BabyImportEntryPoint extends StatefulWidget {
  const BabyImportEntryPoint({super.key});

  @override
  State<BabyImportEntryPoint> createState() => _BabyImportEntryPointState();
}

class _BabyImportEntryPointState extends State<BabyImportEntryPoint> {
  bool _loading = true;
  List<ImportProposal>? _proposals;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final journey = BabyRepository.instance.getJourney();
    if (journey == null) {
      if (mounted) context.go('/baby/setup');
      return;
    }

    // If there's already a pre-built session (e.g. retry), use it
    if (BabyImportController.currentSession != null) {
      setState(() {
        _proposals = BabyImportController.currentSession;
        _loading = false;
      });
      return;
    }

    final proposals =
        await BabyImportController.pickAndGroup(journey.birthDate);
    if (!mounted) return;

    if (proposals == null) {
      context.pop(); // user cancelled picker
      return;
    }
    if (proposals.isEmpty) {
      setState(() {
        _error = 'No photos could be grouped.';
        _loading = false;
      });
      return;
    }

    setState(() {
      _proposals = proposals;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: AppTypography.body),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      );
    }
    return BabyImportScreen(proposals: _proposals!);
  }
}
