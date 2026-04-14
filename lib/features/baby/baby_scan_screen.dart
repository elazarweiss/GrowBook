import 'package:flutter/foundation.dart' show kIsWeb;
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
  bool _checkingServer = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // On web, auto-check if server is running and scan immediately if so
      _autoConnectIfServerRunning();
    } else {
      _folderPath = BabyRepository.instance.cameraFolderPath;
      if (_folderPath != null) {
        _startScan(_folderPath!);
      }
    }
  }

  Future<void> _autoConnectIfServerRunning() async {
    setState(() => _checkingServer = true);
    final running = await BabyScanController.checkServerRunning();
    if (!mounted) return;
    setState(() => _checkingServer = false);
    if (running) {
      _startWebScan();
    }
    // else: show the server setup screen
  }

  Future<void> _startWebScan() async {
    _startScan('companion-server');
  }

  Future<void> _pickAndScan() async {
    final path = await BabyScanController.pickFolder();
    if (path == null) return;
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
    if (_checkingServer) {
      return const Center(child: CircularProgressIndicator());
    }
    switch (_phase) {
      case _Phase.pickOrScan:
        return kIsWeb
            ? _ServerSetupView(onConnect: _startWebScan)
            : _PickFolderView(onPick: _pickAndScan);
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
          onRetry: kIsWeb ? _startWebScan : () => _startScan(_folderPath!),
        );
    }
  }
}

enum _Phase { pickOrScan, scanning, results, empty, error }

// ─── Web: server setup view ───────────────────────────────────────────────────

class _ServerSetupView extends StatefulWidget {
  final VoidCallback onConnect;
  const _ServerSetupView({required this.onConnect});

  @override
  State<_ServerSetupView> createState() => _ServerSetupViewState();
}

class _ServerSetupViewState extends State<_ServerSetupView> {
  bool _connecting = false;
  String? _connectError;

  Future<void> _tryConnect() async {
    setState(() {
      _connecting = true;
      _connectError = null;
    });
    final ok = await BabyScanController.checkServerRunning();
    if (!mounted) return;
    if (ok) {
      widget.onConnect();
    } else {
      setState(() {
        _connecting = false;
        _connectError = 'Scanner not found on port 7272.\nMake sure growbook_scanner.py is running.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
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

          const SizedBox(height: 20),

          // How it works card
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.auto_awesome, color: AppColors.sageGreen, size: 22),
                  const SizedBox(width: 10),
                  Text('How automatic import works',
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warmBrown)),
                ]),
                const SizedBox(height: 16),
                _Step(
                  number: '1',
                  text: 'Run growbook_scanner.py from the project folder — it\'s a small Python script that watches your Camera Uploads folder.',
                ),
                const SizedBox(height: 10),
                _Step(
                  number: '2',
                  text: 'Come back here and click "Scan Now". GrowBook will read the photo dates and sort them into Refael\'s timeline automatically.',
                ),
                const SizedBox(height: 10),
                _Step(
                  number: '3',
                  text: 'Review the suggestions, deselect anything you don\'t want, then import. Done!',
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Command to run
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Run this in a terminal:',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: const Color(0xFF94A3B8))),
                const SizedBox(height: 8),
                Text(
                  'python growbook_scanner.py',
                  style: GoogleFonts.robotoMono(
                      fontSize: 14,
                      color: const Color(0xFF7DD3FC),
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          if (_connectError != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.moodAnxious.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_outlined,
                      color: AppColors.moodAnxious, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_connectError!,
                        style: GoogleFonts.inter(
                            fontSize: 12, color: AppColors.moodAnxious)),
                  ),
                ],
              ),
            ),
          ],

          const Spacer(),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _connecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(_connecting ? 'Connecting…' : 'Scan Now'),
              onPressed: _connecting ? null : _tryConnect,
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
    );
  }
}

class _Step extends StatelessWidget {
  final String number;
  final String text;
  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: AppColors.sageGreen,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(number,
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppColors.warmTaupe, height: 1.45)),
        ),
      ],
    );
  }
}

// ─── Native: pick folder view ─────────────────────────────────────────────────

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
                  'and automatically fill Refael\'s timeline.',
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
    final pct = progress.total == 0 ? null : progress.fraction;
    final isWebScan = folderPath == 'companion-server';

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
            isWebScan ? 'Reading your Camera Uploads folder…' : folderPath,
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
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.warmTaupe),
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
      .fold(0, (sum, p) => sum + p.selectedCount);

  Future<void> _import() async {
    setState(() => _saving = true);
    await BabyScanController.saveSelected(widget.proposals);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
            itemBuilder: (context, i) => GestureDetector(
              onTap: () async {
                await showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) =>
                      _SlotPhotoSheet(proposal: widget.proposals[i]),
                );
                setState(() {}); // refresh counts after sheet changes
              },
              child: _SlotCard(proposal: widget.proposals[i]),
            ),
          ),
        ),

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
                      Text(
                          '$_updateSlots update${_updateSlots > 1 ? 's' : ''}',
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
                    : Text(
                        'Import $_totalPhotos photo${_totalPhotos == 1 ? '' : 's'}',
                        style:
                            GoogleFonts.inter(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _summarySentence() {
    final total = widget.proposals.fold(0, (sum, p) => sum + p.candidates.length);
    final slots = widget.proposals.length;
    return '$total photo${total > 1 ? 's' : ''} across $slots slot${slots > 1 ? 's' : ''}';
  }
}

// ─── Slot card ────────────────────────────────────────────────────────────────

class _SlotCard extends StatelessWidget {
  final ScanProposal proposal;

  const _SlotCard({required this.proposal});

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
    final selected = proposal.selectedCount;
    final total = proposal.candidates.length;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1.0 : 0.38,
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
            // Thumbnail with selection badge
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(12)),
                    child: best != null ? _thumbnail(best) : _placeholder(),
                  ),
                  // "X of Y" badge
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$selected/$total',
                        style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                      ),
                    ),
                  ),
                  // Tap hint
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.45),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'tap to review',
                          style: GoogleFonts.inter(
                              fontSize: 8,
                              color: Colors.white.withOpacity(0.9)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Footer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
    );
  }

  Widget _thumbnail(ScanCandidate candidate) {
    if (kIsWeb) {
      final url =
          'http://localhost:7272/photo?path=${Uri.encodeComponent(candidate.serverPath)}';
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : _placeholder(),
      );
    }
    return Image.file(
      candidate.localFile!,
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.accentSoft,
        child: const Center(
            child: Icon(Icons.image_outlined,
                size: 32, color: AppColors.sageGreen)),
      );
}

// ─── Per-photo selection sheet ────────────────────────────────────────────────

class _SlotPhotoSheet extends StatefulWidget {
  final ScanProposal proposal;
  const _SlotPhotoSheet({required this.proposal});

  @override
  State<_SlotPhotoSheet> createState() => _SlotPhotoSheetState();
}

class _SlotPhotoSheetState extends State<_SlotPhotoSheet> {
  ScanProposal get p => widget.proposal;

  int get _selected => p.candidates.where((c) => c.selected).length;

  String get _slotLabel {
    switch (p.slot.kind) {
      case BabyAgeKind.week:
        return p.slot.value == 0 ? 'Birth' : 'Week ${p.slot.value}';
      case BabyAgeKind.month:
        return '${p.slot.value} months old';
      case BabyAgeKind.year:
        return '${p.slot.value} year${p.slot.value > 1 ? 's' : ''} old';
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_slotLabel,
                              style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.warmBrown)),
                          Text(
                            '$_selected of ${p.candidates.length} selected',
                            style: GoogleFonts.inter(
                                fontSize: 12, color: AppColors.warmTaupe),
                          ),
                        ],
                      ),
                    ),
                    // Import toggle
                    Row(
                      children: [
                        Text('Import',
                            style: GoogleFonts.inter(
                                fontSize: 12, color: AppColors.warmTaupe)),
                        Switch(
                          value: p.importEnabled,
                          onChanged: (v) =>
                              setState(() => p.importEnabled = v),
                          activeColor: AppColors.sageGreen,
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: AppColors.warmTaupe,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Select all / none
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        for (final c in p.candidates) {
                          c.selected = true;
                        }
                      }),
                      child: Text('Select all',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: AppColors.sageGreen)),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        for (final c in p.candidates) {
                          c.selected = false;
                        }
                      }),
                      child: Text('Select none',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: AppColors.warmTaupe)),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Photo grid
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(10),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: p.candidates.length,
                  itemBuilder: (ctx, i) {
                    final c = p.candidates[i];
                    return GestureDetector(
                      onTap: () =>
                          setState(() => c.selected = !c.selected),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Photo
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _photoWidget(c),
                          ),
                          // Dimmed overlay when deselected
                          if (!c.selected)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                  color: Colors.black.withOpacity(0.52)),
                            ),
                          // Checkmark circle
                          Positioned(
                            top: 5,
                            right: 5,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: c.selected
                                    ? AppColors.sageGreen
                                    : Colors.white.withOpacity(0.75),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 1.5),
                              ),
                              child: c.selected
                                  ? const Icon(Icons.check,
                                      size: 13, color: Colors.white)
                                  : null,
                            ),
                          ),
                          // Date label at bottom
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(8)),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 3),
                                color: Colors.black.withOpacity(0.45),
                                child: Text(
                                  _shortDate(c.photoDate),
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                      fontSize: 8,
                                      color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Done button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.sageGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text(
                      _selected == 0
                          ? 'Skip this slot'
                          : 'Done — $_selected photo${_selected == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _photoWidget(ScanCandidate c) {
    if (kIsWeb) {
      final url =
          'http://localhost:7272/photo?path=${Uri.encodeComponent(c.serverPath)}';
      return Image.network(url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _photoPlaceholder());
    }
    return Image.file(c.localFile!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _photoPlaceholder());
  }

  Widget _photoPlaceholder() => Container(
        color: AppColors.accentSoft,
        child: const Center(
            child: Icon(Icons.broken_image_outlined,
                color: AppColors.sageGreen, size: 24)),
      );

  String _shortDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year.toString().substring(2)}';
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

  const _EmptyResultView({required this.folderPath, required this.onRescan});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: AppColors.babyMint),
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
              onPressed: () => context.pop(), child: const Text('Close')),
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
              style:
                  GoogleFonts.inter(fontSize: 12, color: AppColors.warmTaupe)),
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
              onPressed: () => context.pop(), child: const Text('Close')),
        ],
      ),
    );
  }
}
