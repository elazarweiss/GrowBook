import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/baby_slot_model.dart';
import '../../core/models/scan_proposal_model.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/baby_repository.dart';
import 'baby_scan_controller.dart';

// ─── Entry point (launched by router) ────────────────────────────────────────

class BabyScanEntryPoint extends StatefulWidget {
  const BabyScanEntryPoint({super.key});

  @override
  State<BabyScanEntryPoint> createState() => _BabyScanEntryPointState();
}

class _BabyScanEntryPointState extends State<BabyScanEntryPoint> {
  _Phase _phase = _Phase.pickOrScan;
  String? _folderPath;
  ScanProgress _progress = const ScanProgress(0, 0);
  List<ScanProposal> _proposals = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _folderPath = BabyRepository.instance.cameraFolderPath;
    if (_folderPath != null) {
      _startScan(_folderPath!);
    }
  }

  Future<void> _pickAndScan() async {
    final path = await BabyScanController.pickFolder();
    if (path == null) {
      if (mounted) context.pop();
      return;
    }
    await BabyRepository.instance.saveCameraFolderPath(path);
    _startScan(path);
  }

  Future<void> _startScan(String path) async {
    setState(() {
      _phase = _Phase.scanning;
      _folderPath = path;
    });
    final journey = BabyRepository.instance.getJourney();
    if (journey == null) return;

    try {
      final proposals = await BabyScanController.scan(
        folderPath: path,
        birthDate: journey.birthDate,
        sinceDate: BabyRepository.instance.lastScanAt,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );

      if (!mounted) return;
      if (proposals.isEmpty) {
        setState(() {
          _phase = _Phase.empty;
          _proposals = [];
        });
      } else {
        setState(() {
          _phase = _Phase.results;
          _proposals = proposals;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.pickOrScan:
        return _PickFolderView(onPick: _pickAndScan);
      case _Phase.scanning:
        return _ScanningView(
          folderPath: _folderPath!,
          progress: _progress,
        );
      case _Phase.results:
        return _ScanResultsView(
          proposals: _proposals,
          folderPath: _folderPath!,
          onRescan: () => _startScan(_folderPath!),
        );
      case _Phase.empty:
        return _EmptyResultView(
          folderPath: _folderPath!,
          onRescan: () => _startScan(_folderPath!),
        );
      case _Phase.error:
        return _ErrorView(
          message: _error ?? 'Unknown error',
          onRetry: () => _startScan(_folderPath!),
        );
    }
  }
}

enum _Phase { pickOrScan, scanning, results, empty, error }

// ─── Pick folder view ─────────────────────────────────────────────────────────

class _PickFolderView extends StatelessWidget {
  final VoidCallback onPick;
  const _PickFolderView({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('Auto-Import',
                  style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.warmBrown)),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              color: AppColors.warmTaupe,
              onPressed: () => context.pop(),
            )
          ]),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Icon(Icons.folder_open_outlined,
                    size: 56, color: AppColors.sageGreen),
                const SizedBox(height: 16),
                Text(
                  'Point GrowBook to your\nCamera Uploads folder',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warmBrown,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'GrowBook will scan your photos, read their dates,\n'
                  'and automatically fill your baby\'s timeline.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: AppColors.warmTaupe, height: 1.5),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Choose Folder'),
                    onPressed: onPick,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.sageGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _TipRow(
              icon: Icons.history,
              text:
                  'GrowBook remembers your folder and only scans new photos each time.'),
          const SizedBox(height: 12),
          _TipRow(
              icon: Icons.check_circle_outline,
              text:
                  'You review suggestions before anything is saved to the timeline.'),
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TipRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.sageGreen),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppColors.warmTaupe, height: 1.4)),
        ),
      ],
    );
  }
}

// ─── Scanning progress view ───────────────────────────────────────────────────

class _ScanningView extends StatelessWidget {
  final String folderPath;
  final ScanProgress progress;

  const _ScanningView({required this.folderPath, required this.progress});

  @override
  Widget build(BuildContext context) {
    final pct = progress.total == 0
        ? null
        : progress.fraction;

    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_search, size: 64, color: AppColors.sageGreen),
          const SizedBox(height: 24),
          Text('Scanning photos…',
              style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warmBrown)),
          const SizedBox(height: 8),
          Text(
            folderPath,
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.warmTaupe),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 32),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: AppColors.divider,
              color: AppColors.sageGreen,
              minHeight: 6,
            ),
          ),
          if (progress.total > 0) ...[
            const SizedBox(height: 10),
            Text(
              '${progress.processed} / ${progress.total} photos',
              style:
                  GoogleFonts.inter(fontSize: 12, color: AppColors.warmTaupe),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Results view ─────────────────────────────────────────────────────────────

class _ScanResultsView extends StatefulWidget {
  final List<ScanProposal> proposals;
  final String folderPath;
  final VoidCallback onRescan;

  const _ScanResultsView({
    required this.proposals,
    required this.folderPath,
    required this.onRescan,
  });

  @override
  State<_ScanResultsView> createState() => _ScanResultsViewState();
}

class _ScanResultsViewState extends State<_ScanResultsView> {
  bool _saving = false;

  int get _newSlots =>
      widget.proposals.where((p) => p.importEnabled && !p.hasExisting).length;
  int get _updateSlots =>
      widget.proposals.where((p) => p.importEnabled && p.hasExisting).length;
  int get _totalPhotos => widget.proposals
      .where((p) => p.importEnabled)
      .fold(0, (sum, p) => sum + p.candidates.length);

  Future<void> _import() async {
    setState(() => _saving = true);
    await BabyScanController.saveSelected(widget.proposals);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Photos found',
                        style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.warmBrown)),
                    const SizedBox(height: 3),
                    Text(
                      _summarySentence(),
                      style: GoogleFonts.inter(
                          fontSize: 13, color: AppColors.warmTaupe),
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

        const SizedBox(height: 12),

        // Slot grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 4),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            itemCount: widget.proposals.length,
            itemBuilder: (context, i) => _SlotCard(
              proposal: widget.proposals[i],
              onToggle: () => setState(() {
                widget.proposals[i].importEnabled =
                    !widget.proposals[i].importEnabled;
              }),
            ),
          ),
        ),

        // Bottom action bar
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_newSlots > 0)
                      Text('$_newSlots new slot${_newSlots > 1 ? 's' : ''}',
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.sageGreen)),
                    if (_updateSlots > 0)
                      Text('$_updateSlots update${_updateSlots > 1 ? 's' : ''}',
                          style: GoogleFonts.inter(
                              fontSize: 13, color: AppColors.warmTaupe)),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: _totalPhotos > 0 && !_saving ? _import : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.sageGreen,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.divider,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
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
                    : Text('Import $_totalPhotos photo${_totalPhotos == 1 ? '' : 's'}',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _summarySentence() {
    final total = widget.proposals
        .fold(0, (sum, p) => sum + p.candidates.length);
    final slots = widget.proposals.length;
    return '$total photo${total > 1 ? 's' : ''} across $slots slot${slots > 1 ? 's' : ''}';
  }
}

// ─── Slot card ────────────────────────────────────────────────────────────────

class _SlotCard extends StatelessWidget {
  final ScanProposal proposal;
  final VoidCallback onToggle;

  const _SlotCard({required this.proposal, required this.onToggle});

  String get _label {
    final slot = proposal.slot;
    switch (slot.kind) {
      case BabyAgeKind.week:
        return slot.value == 0 ? 'Birth' : 'Week ${slot.value}';
      case BabyAgeKind.month:
        return '${slot.value} mo';
      case BabyAgeKind.year:
        return '${slot.value} yr';
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = proposal.importEnabled;
    final best = proposal.bestCandidate;

    return GestureDetector(
      onTap: onToggle,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1.0 : 0.45,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: enabled ? AppColors.sageGreen : AppColors.divider,
              width: enabled ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              Expanded(
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                  child: best != null
                      ? Image.file(best.file,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => _placeholder())
                      : _placeholder(),
                ),
              ),

              // Footer
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_label,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.warmBrown)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '${proposal.candidates.length} photo${proposal.candidates.length > 1 ? 's' : ''}',
                          style: GoogleFonts.inter(
                              fontSize: 10, color: AppColors.warmTaupe),
                        ),
                        const Spacer(),
                        if (proposal.hasExisting)
                          _Badge('UPDATE', AppColors.babySunrise)
                        else
                          _Badge('NEW', AppColors.sageGreen),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.accentSoft,
        child: const Center(
            child: Icon(Icons.image_outlined,
                size: 32, color: AppColors.sageGreen)),
      );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.8)),
      );
}

// ─── Empty and error views ────────────────────────────────────────────────────

class _EmptyResultView extends StatelessWidget {
  final String folderPath;
  final VoidCallback onRescan;

  const _EmptyResultView(
      {required this.folderPath, required this.onRescan});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline,
              size: 64, color: AppColors.babyMint),
          const SizedBox(height: 20),
          Text('All caught up!',
              style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warmBrown)),
          const SizedBox(height: 8),
          Text(
            'No new photos found since the last scan.',
            textAlign: TextAlign.center,
            style:
                GoogleFonts.inter(fontSize: 14, color: AppColors.warmTaupe),
          ),
          const SizedBox(height: 32),
          TextButton(
              onPressed: onRescan, child: const Text('Scan all photos again')),
          const SizedBox(height: 8),
          TextButton(
              onPressed: () => context.pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: AppColors.moodAnxious),
          const SizedBox(height: 20),
          Text('Scan failed',
              style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warmBrown)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.warmTaupe)),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.sageGreen,
                foregroundColor: Colors.white),
            child: const Text('Retry'),
          ),
          const SizedBox(height: 8),
          TextButton(
              onPressed: () => context.pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }
}
