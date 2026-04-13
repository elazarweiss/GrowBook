import 'package:hive/hive.dart';

class BabyEntry {
  final String slotKey;
  final List<String> photoPaths;
  final String? caption;
  final DateTime? updatedAt;

  const BabyEntry({
    required this.slotKey,
    this.photoPaths = const [],
    this.caption,
    this.updatedAt,
  });

  BabyEntry copyWith({
    List<String>? photoPaths,
    String? caption,
    DateTime? updatedAt,
  }) {
    return BabyEntry(
      slotKey: slotKey,
      photoPaths: photoPaths ?? this.photoPaths,
      caption: caption ?? this.caption,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// typeId 0 in GrowBook
class BabyEntryAdapter extends TypeAdapter<BabyEntry> {
  @override
  final int typeId = 0;

  @override
  BabyEntry read(BinaryReader reader) {
    final slotKey = reader.readString();
    final photoCount = reader.readInt();
    final photoPaths = List.generate(photoCount, (_) => reader.readString());
    final hasCaption = reader.readBool();
    final caption = hasCaption ? reader.readString() : null;
    final hasUpdatedAt = reader.readBool();
    final updatedAt = hasUpdatedAt
        ? DateTime.fromMillisecondsSinceEpoch(reader.readInt())
        : null;
    return BabyEntry(
      slotKey: slotKey,
      photoPaths: photoPaths,
      caption: caption,
      updatedAt: updatedAt,
    );
  }

  @override
  void write(BinaryWriter writer, BabyEntry obj) {
    writer.writeString(obj.slotKey);
    writer.writeInt(obj.photoPaths.length);
    for (final p in obj.photoPaths) {
      writer.writeString(p);
    }
    writer.writeBool(obj.caption != null);
    if (obj.caption != null) writer.writeString(obj.caption!);
    writer.writeBool(obj.updatedAt != null);
    if (obj.updatedAt != null) {
      writer.writeInt(obj.updatedAt!.millisecondsSinceEpoch);
    }
  }
}
