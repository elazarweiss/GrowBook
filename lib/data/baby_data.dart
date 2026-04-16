/// Developmental milestone suggestions — shown as pins on the clothesline
/// even before the user has added a photo for that slot.
class BabyMilestoneInfo {
  final String slotKey;
  final String label;
  final String emoji;

  const BabyMilestoneInfo({
    required this.slotKey,
    required this.label,
    required this.emoji,
  });
}

const List<BabyMilestoneInfo> babyMilestones = [
  BabyMilestoneInfo(slotKey: 'w-0',  label: 'Birth Day',        emoji: '🌟'),
  BabyMilestoneInfo(slotKey: 'w-4',  label: 'First Smile',      emoji: '😊'),
  BabyMilestoneInfo(slotKey: 'w-8',  label: 'Holds Head Up',    emoji: '💪'),
  BabyMilestoneInfo(slotKey: 'w-11', label: 'Tracks Objects',   emoji: '👀'),
  BabyMilestoneInfo(slotKey: 'm-4',  label: 'Rolls Over',       emoji: '🔄'),
  BabyMilestoneInfo(slotKey: 'm-6',  label: 'First Solids',     emoji: '🥄'),
  BabyMilestoneInfo(slotKey: 'm-8',  label: 'Sits Alone',       emoji: '🪑'),
  BabyMilestoneInfo(slotKey: 'm-9',  label: 'First Crawl',      emoji: '🐣'),
  BabyMilestoneInfo(slotKey: 'm-12', label: 'First Steps',      emoji: '👣'),
  BabyMilestoneInfo(slotKey: 'm-15', label: 'First Words',      emoji: '💬'),
  BabyMilestoneInfo(slotKey: 'm-24', label: 'Second Birthday',  emoji: '🎂'),
  BabyMilestoneInfo(slotKey: 'y-3',  label: 'Third Year',       emoji: '🎈'),
];

/// O(1) lookup: slotKey → milestone info.
final Map<String, BabyMilestoneInfo> kMilestonesBySlot = {
  for (final m in babyMilestones) m.slotKey: m,
};
