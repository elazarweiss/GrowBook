import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/baby_journey_model.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/baby_repository.dart';
import '../../shared/widgets/cream_scaffold.dart';
import '../../shared/widgets/serif_text.dart';

class BabySetupScreen extends StatefulWidget {
  const BabySetupScreen({super.key});

  @override
  State<BabySetupScreen> createState() => _BabySetupScreenState();
}

class _BabySetupScreenState extends State<BabySetupScreen> {
  final _nameController = TextEditingController();
  DateTime? _birthDate;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      helpText: "Baby's birth date",
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppColors.sageGreen,
            onPrimary: Colors.white,
            surface: AppColors.background,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _birthDate == null) return;

    setState(() => _saving = true);
    await BabyRepository.instance.saveJourney(
      BabyJourney(babyName: name, birthDate: _birthDate!),
    );
    if (mounted) context.go('/baby');
  }

  @override
  Widget build(BuildContext context) {
    final ready = _nameController.text.trim().isNotEmpty && _birthDate != null;

    return CreamScaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),
              const SerifText("Welcome to\nyour baby's journey", fontSize: 28),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Tell us a little about your little one.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.warmTaupe),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Name field
              Text("Baby's name", style: AppTypography.label),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'e.g. Lily',
                  filled: true,
                  fillColor: AppColors.surface,
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
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),

              // Birth date picker
              Text("Birth date", style: AppTypography.label),
              const SizedBox(height: AppSpacing.xs),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm + 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 16, color: AppColors.warmTaupe),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        _birthDate != null
                            ? '${_birthDate!.day}/${_birthDate!.month}/${_birthDate!.year}'
                            : 'Tap to choose',
                        style: AppTypography.body.copyWith(
                          color: _birthDate != null
                              ? AppColors.darkOlive
                              : AppColors.warmTaupe,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: ready && !_saving ? _save : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.sageGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.divider,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
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
                          "Start ${_nameController.text.trim().isNotEmpty ? "${_nameController.text.trim()}'s" : "Baby's"} Journey",
                          style: AppTypography.label.copyWith(
                            color: Colors.white,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
