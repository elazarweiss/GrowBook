import 'package:hive/hive.dart';

/// AI-generated tags for a single photo.
/// Stored in a separate Hive box keyed by "{slotKey}_{photoIndex}".
class PhotoTag {
  final String photoPath; // the exact value from BabyEntry.photoPaths[i]
  final List<String> people; // e.g. ['baby', 'with_mom']
  final String mood; // happy | calm | sleeping | crying | silly | surprised
  final String activity; // bath | feeding | play | outdoors | tummy_time | reading | travel | milestone | other
  final bool isMilestone;
  final String? aiCaption; // one warm sentence from Claude

  const PhotoTag({
    required this.photoPath,
    required this.people,
    required this.mood,
    required this.activity,
    required this.isMilestone,
    this.aiCaption,
  });
}

// typeId 2 in GrowBook (0 = BabyEntry, 1 = BabyJourney)
class PhotoTagAdapter extends TypeAdapter<PhotoTag> {
  @override
  final int typeId = 2;

  @override
  PhotoTag read(BinaryReader reader) {
    final photoPath = reader.readString();
    final peopleCount = reader.readInt();
    final people = List.generate(peopleCount, (_) => reader.readString());
    final mood = reader.readString();
    final activity = reader.readString();
    final isMilestone = reader.readBool();
    final hasCaption = reader.readBool();
    final aiCaption = hasCaption ? reader.readString() : null;
    return PhotoTag(
      photoPath: photoPath,
      people: people,
      mood: mood,
      activity: activity,
      isMilestone: isMilestone,
      aiCaption: aiCaption,
    );
  }

  @override
  void write(BinaryWriter writer, PhotoTag obj) {
    writer.writeString(obj.photoPath);
    writer.writeInt(obj.people.length);
    for (final p in obj.people) {
      writer.writeString(p);
    }
    writer.writeString(obj.mood);
    writer.writeString(obj.activity);
    writer.writeBool(obj.isMilestone);
    writer.writeBool(obj.aiCaption != null);
    if (obj.aiCaption != null) writer.writeString(obj.aiCaption!);
  }
}

// ── Chip descriptors ──────────────────────────────────────────────────────────

class TagChip {
  final String label;
  final String emoji;
  final String filterKey; // value to match against

  const TagChip({required this.label, required this.emoji, required this.filterKey});

  bool matches(PhotoTag tag) {
    if (filterKey == 'milestone') return tag.isMilestone;
    if (tag.mood == filterKey) return true;
    if (tag.activity == filterKey) return true;
    if (tag.people.contains(filterKey)) return true;
    return false;
  }
}

const kTagChips = [
  TagChip(label: 'Milestone', emoji: '⭐', filterKey: 'milestone'),
  TagChip(label: 'Bath',      emoji: '🛁', filterKey: 'bath'),
  TagChip(label: 'Outdoors',  emoji: '🌿', filterKey: 'outdoors'),
  TagChip(label: 'Feeding',   emoji: '🍼', filterKey: 'feeding'),
  TagChip(label: 'Play',      emoji: '🎮', filterKey: 'play'),
  TagChip(label: 'Tummy time',emoji: '💪', filterKey: 'tummy_time'),
  TagChip(label: 'Reading',   emoji: '📖', filterKey: 'reading'),
  TagChip(label: 'Travel',    emoji: '✈️', filterKey: 'travel'),
  TagChip(label: 'Happy',     emoji: '😊', filterKey: 'happy'),
  TagChip(label: 'Sleeping',  emoji: '😴', filterKey: 'sleeping'),
  TagChip(label: 'Silly',     emoji: '😂', filterKey: 'silly'),
  TagChip(label: 'Family',    emoji: '👨‍👩‍👶', filterKey: 'family_group'),
  TagChip(label: 'Grandparents', emoji: '👴', filterKey: 'with_grandparents'),
];
