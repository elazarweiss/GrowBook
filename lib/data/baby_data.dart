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
  BabyMilestoneInfo(slotKey: 'w-0',  label: 'Birth Day',     emoji: '🌟'),
  BabyMilestoneInfo(slotKey: 'w-6',  label: 'First Smile',   emoji: '😊'),
  BabyMilestoneInfo(slotKey: 'm-4',  label: 'Rolling Over',  emoji: '🔄'),
  BabyMilestoneInfo(slotKey: 'm-6',  label: 'First Solids',  emoji: '🥄'),
  BabyMilestoneInfo(slotKey: 'm-9',  label: 'First Crawl',   emoji: '🐣'),
  BabyMilestoneInfo(slotKey: 'm-12', label: 'First Steps',   emoji: '👣'),
  BabyMilestoneInfo(slotKey: 'm-18', label: 'First Words',   emoji: '💬'),
  BabyMilestoneInfo(slotKey: 'y-2',  label: 'Second Year',   emoji: '🎂'),
  BabyMilestoneInfo(slotKey: 'y-3',  label: 'Third Year',    emoji: '🎈'),
];
