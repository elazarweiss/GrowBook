import 'package:hive/hive.dart';

/// A photo staged in the inbox, waiting for user review before going to timeline.
class InboxPhoto {
  final String id; // == path, used as Hive key
  final String path; // server:... or local path
  final DateTime date;
  final String slotKey; // suggested timeline slot, e.g. "w-2"
  bool? hasBaby; // null = not yet screened by AI
  bool isMilestone;
  String? mood;
  String? activity;
  String? aiCaption;
  List<String> people;

  InboxPhoto({
    required this.id,
    required this.path,
    required this.date,
    required this.slotKey,
    this.hasBaby,
    this.isMilestone = false,
    this.mood,
    this.activity,
    this.aiCaption,
    this.people = const [],
  });

  InboxPhoto copyWithScreening({
    required bool hasBaby,
    bool isMilestone = false,
    String? mood,
    String? activity,
    String? aiCaption,
    List<String> people = const [],
  }) {
    return InboxPhoto(
      id: id,
      path: path,
      date: date,
      slotKey: slotKey,
      hasBaby: hasBaby,
      isMilestone: isMilestone,
      mood: mood,
      activity: activity,
      aiCaption: aiCaption,
      people: people,
    );
  }
}

// typeId 3 in GrowBook (0=BabyEntry, 1=BabyJourney, 2=PhotoTag)
class InboxPhotoAdapter extends TypeAdapter<InboxPhoto> {
  @override
  final int typeId = 3;

  @override
  InboxPhoto read(BinaryReader reader) {
    final id = reader.readString();
    final path = reader.readString();
    final date = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    final slotKey = reader.readString();
    final hasHasBaby = reader.readBool();
    final hasBaby = hasHasBaby ? reader.readBool() : null;
    final isMilestone = reader.readBool();
    final hasMood = reader.readBool();
    final mood = hasMood ? reader.readString() : null;
    final hasActivity = reader.readBool();
    final activity = hasActivity ? reader.readString() : null;
    final hasCaption = reader.readBool();
    final aiCaption = hasCaption ? reader.readString() : null;
    final peopleCount = reader.readInt();
    final people = List.generate(peopleCount, (_) => reader.readString());
    return InboxPhoto(
      id: id,
      path: path,
      date: date,
      slotKey: slotKey,
      hasBaby: hasBaby,
      isMilestone: isMilestone,
      mood: mood,
      activity: activity,
      aiCaption: aiCaption,
      people: people,
    );
  }

  @override
  void write(BinaryWriter writer, InboxPhoto obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.path);
    writer.writeInt(obj.date.millisecondsSinceEpoch);
    writer.writeString(obj.slotKey);
    writer.writeBool(obj.hasBaby != null);
    if (obj.hasBaby != null) writer.writeBool(obj.hasBaby!);
    writer.writeBool(obj.isMilestone);
    writer.writeBool(obj.mood != null);
    if (obj.mood != null) writer.writeString(obj.mood!);
    writer.writeBool(obj.activity != null);
    if (obj.activity != null) writer.writeString(obj.activity!);
    writer.writeBool(obj.aiCaption != null);
    if (obj.aiCaption != null) writer.writeString(obj.aiCaption!);
    writer.writeInt(obj.people.length);
    for (final p in obj.people) { writer.writeString(p); }
  }
}
