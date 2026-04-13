import '../models/baby_slot_model.dart';

abstract final class BabyTimelineUtils {
  // Slot widths in logical pixels
  static const double weekSlotWidth = 100.0;
  static const double monthSlotWidth = 72.0;
  static const double yearSlotWidth = 88.0;

  // Lookahead: always show this many slots beyond the current one
  static const int _lookahead = 4;

  /// Generates the full ordered list of slots from birth to current age
  /// plus [_lookahead] future slots.
  static List<BabySlot> generateSlots(DateTime birthDate) {
    final slots = <BabySlot>[];
    final now = DateTime.now();
    final int ageInDays = now.difference(birthDate).inDays;

    // Phase 1: weekly slots for weeks 0–11 (days 0–83)
    for (int w = 0; w <= 11; w++) {
      slots.add(BabySlot(
        index: slots.length,
        kind: BabyAgeKind.week,
        value: w,
        label: '${w}w',
      ));
    }

    // Phase 2: monthly slots for months 3–24
    for (int m = 3; m <= 24; m++) {
      slots.add(BabySlot(
        index: slots.length,
        kind: BabyAgeKind.month,
        value: m,
        label: '${m}m',
      ));
    }

    // Phase 3: yearly slots for years 2+
    // Generate up to the current age + lookahead buffer (max 18 years)
    final int maxYear = ((ageInDays / 365) + 2).ceil().clamp(2, 18);
    for (int y = 2; y <= maxYear; y++) {
      slots.add(BabySlot(
        index: slots.length,
        kind: BabyAgeKind.year,
        value: y,
        label: '${y}y',
      ));
    }

    // Trim: only keep slots up to (current slot index + lookahead)
    final current = slotForDate(birthDate, now);
    final cutoff = (current.index + _lookahead).clamp(0, slots.length - 1);
    return slots.sublist(0, cutoff + 1);
  }

  /// Returns the x-position (left edge center) for a slot given the full list.
  static double xForSlot(BabySlot slot, List<BabySlot> allSlots) {
    double x = 0;
    for (int i = 0; i < slot.index && i < allSlots.length; i++) {
      x += _widthFor(allSlots[i].kind);
    }
    // Center within the slot
    return x + _widthFor(slot.kind) / 2;
  }

  /// Total canvas width for the given slot list.
  static double totalWidth(List<BabySlot> slots) {
    if (slots.isEmpty) return 400;
    double w = 0;
    for (final s in slots) {
      w += _widthFor(s.kind);
    }
    // Add a half-slot padding on each side
    return w + _widthFor(slots.last.kind);
  }

  /// Returns the BabySlot that corresponds to [targetDate] given [birthDate].
  static BabySlot slotForDate(DateTime birthDate, DateTime targetDate) {
    final int ageInDays = targetDate.difference(birthDate).inDays.clamp(0, 999999);

    if (ageInDays < 84) {
      // weeks 0–11
      final w = (ageInDays / 7).floor().clamp(0, 11);
      return BabySlot(index: w, kind: BabyAgeKind.week, value: w, label: '${w}w');
    }

    final int ageInMonths = (ageInDays / 30.44).floor();
    if (ageInMonths <= 24) {
      // months 3–24 — slot index = 12 (weeks 0-11) + (month - 3)
      final m = ageInMonths.clamp(3, 24);
      final idx = 12 + (m - 3);
      return BabySlot(index: idx, kind: BabyAgeKind.month, value: m, label: '${m}m');
    }

    // years 2+ — slot index = 12 (weeks) + 22 (months 3-24) + (year - 2)
    final int ageInYears = (ageInDays / 365).floor();
    final y = ageInYears.clamp(2, 18);
    final idx = 12 + 22 + (y - 2);
    return BabySlot(index: idx, kind: BabyAgeKind.year, value: y, label: '${y}y');
  }

  /// Parses a slotKey string (e.g. "w-3", "m-6", "y-2") back into a BabySlot.
  static BabySlot slotForKey(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return BabySlot(index: 0, kind: BabyAgeKind.week, value: 0, label: '0w');
    final kindChar = parts[0];
    final value = int.tryParse(parts[1]) ?? 0;
    switch (kindChar) {
      case 'w':
        return BabySlot(
          index: value,
          kind: BabyAgeKind.week,
          value: value,
          label: '${value}w',
        );
      case 'm':
        final idx = 12 + (value - 3);
        return BabySlot(
          index: idx,
          kind: BabyAgeKind.month,
          value: value,
          label: '${value}m',
        );
      case 'y':
        final idx = 12 + 22 + (value - 2);
        return BabySlot(
          index: idx,
          kind: BabyAgeKind.year,
          value: value,
          label: '${value}y',
        );
      default:
        return BabySlot(index: 0, kind: BabyAgeKind.week, value: 0, label: '0w');
    }
  }

  static double _widthFor(BabyAgeKind kind) {
    switch (kind) {
      case BabyAgeKind.week:
        return weekSlotWidth;
      case BabyAgeKind.month:
        return monthSlotWidth;
      case BabyAgeKind.year:
        return yearSlotWidth;
    }
  }
}
