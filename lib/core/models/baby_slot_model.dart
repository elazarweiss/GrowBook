enum BabyAgeKind { week, month, year }

class BabySlot {
  final int index;
  final BabyAgeKind kind;
  final int value;
  final String label;

  const BabySlot({
    required this.index,
    required this.kind,
    required this.value,
    required this.label,
  });

  String get key {
    switch (kind) {
      case BabyAgeKind.week:
        return 'w-$value';
      case BabyAgeKind.month:
        return 'm-$value';
      case BabyAgeKind.year:
        return 'y-$value';
    }
  }

  @override
  String toString() => 'BabySlot($key, index: $index)';
}
