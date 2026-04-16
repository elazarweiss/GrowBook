import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/models/baby_entry_model.dart';
import '../core/models/baby_journey_model.dart';
import '../core/models/photo_tag_model.dart';
import '../core/models/inbox_photo_model.dart';

class BabyRepository {
  static final instance = BabyRepository._();
  BabyRepository._();

  late Box<BabyEntry> _entries;
  late Box<BabyJourney> _journeys;
  late Box<dynamic> _settings;
  late Box<PhotoTag> _photoTags;
  late Box<InboxPhoto> _inbox;

  static const _entriesBoxName = 'babyEntries';
  static const _journeyBoxName = 'babyJourney';
  static const _settingsBoxName = 'growbookSettings';
  static const _photoTagsBoxName = 'photoTags';
  static const _inboxBoxName = 'inboxPhotos';
  static const _journeyKey = 0;

  // Settings keys
  static const _keyFolderPath = 'cameraFolderPath';
  static const _keyLastScanAt = 'lastScanAt';
  static const _keyDataVersion = 'dataVersion';
  static const _currentDataVersion = 2;

  Future<void> init() async {
    _entries = await Hive.openBox<BabyEntry>(_entriesBoxName);
    _journeys = await Hive.openBox<BabyJourney>(_journeyBoxName);
    _settings = await Hive.openBox(_settingsBoxName);
    _photoTags = await Hive.openBox<PhotoTag>(_photoTagsBoxName);
    _inbox = await Hive.openBox<InboxPhoto>(_inboxBoxName);

    // Data migration: clear old timeline entries from pre-inbox flow
    final version = _settings.get(_keyDataVersion) as int? ?? 1;
    if (version < _currentDataVersion) {
      await _entries.clear();
      await _photoTags.clear();
      await _inbox.clear();
      await _settings.put(_keyDataVersion, _currentDataVersion);
    }

    // Dev shortcut: pre-seed Refael's data so setup screen is skipped.
    // Remove this block when opening the app to other babies.
    if (_journeys.get(_journeyKey) == null) {
      await _journeys.put(
        _journeyKey,
        BabyJourney(
          babyName: 'Refael',
          birthDate: DateTime(2026, 3, 28),
        ),
      );
    }
  }

  // ── Camera folder settings ─────────────────────────────────────────────────

  String? get cameraFolderPath => _settings.get(_keyFolderPath) as String?;

  Future<void> saveCameraFolderPath(String path) =>
      _settings.put(_keyFolderPath, path);

  Future<void> clearCameraFolderPath() => _settings.delete(_keyFolderPath);

  DateTime? get lastScanAt {
    final ms = _settings.get(_keyLastScanAt) as int?;
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  Future<void> saveLastScanAt(DateTime dt) =>
      _settings.put(_keyLastScanAt, dt.millisecondsSinceEpoch);

  // ── Journey ────────────────────────────────────────────────────────────────

  BabyJourney? getJourney() => _journeys.get(_journeyKey);

  Future<void> saveJourney(BabyJourney journey) =>
      _journeys.put(_journeyKey, journey);

  // ── Timeline entries ───────────────────────────────────────────────────────

  BabyEntry? getEntry(String slotKey) => _entries.get(slotKey);

  Future<void> saveEntry(BabyEntry entry) =>
      _entries.put(entry.slotKey, entry);

  ValueListenable<Box<BabyEntry>> get entriesListenable =>
      _entries.listenable();

  // ── Photo tags ─────────────────────────────────────────────────────────────

  static String _tagKey(String slotKey, int photoIndex) =>
      '${slotKey}_$photoIndex';

  PhotoTag? getPhotoTag(String slotKey, int photoIndex) =>
      _photoTags.get(_tagKey(slotKey, photoIndex));

  Future<void> savePhotoTag(String slotKey, int photoIndex, PhotoTag tag) =>
      _photoTags.put(_tagKey(slotKey, photoIndex), tag);

  List<PhotoTag?> getPhotoTags(String slotKey, int count) =>
      List.generate(count, (i) => _photoTags.get(_tagKey(slotKey, i)));

  ValueListenable<Box<PhotoTag>> get photoTagsListenable =>
      _photoTags.listenable();

  // ── Inbox ──────────────────────────────────────────────────────────────────

  Future<void> saveInboxPhoto(InboxPhoto photo) =>
      _inbox.put(photo.id, photo);

  InboxPhoto? getInboxPhoto(String id) => _inbox.get(id);

  Future<void> removeInboxPhoto(String id) => _inbox.delete(id);

  List<InboxPhoto> getAllInbox() => _inbox.values.toList();

  List<InboxPhoto> getUnscreenedInbox() =>
      _inbox.values.where((p) => p.hasBaby == null).toList();

  List<InboxPhoto> getBabyInbox() =>
      _inbox.values.where((p) => p.hasBaby != false).toList();

  int get inboxBabyCount =>
      _inbox.values.where((p) => p.hasBaby != false).length;

  ValueListenable<Box<InboxPhoto>> get inboxListenable =>
      _inbox.listenable();

  // ── Promote inbox photo to timeline ───────────────────────────────────────

  Future<void> promoteToTimeline(InboxPhoto photo) async {
    final existing = getEntry(photo.slotKey);
    final newPaths = [...?existing?.photoPaths, photo.path];
    await saveEntry(BabyEntry(
      slotKey: photo.slotKey,
      photoPaths: newPaths,
      caption: existing?.caption,
      updatedAt: DateTime.now(),
    ));
    // Copy AI tags to PhotoTag box
    if (photo.mood != null || photo.isMilestone || photo.aiCaption != null) {
      final idx = newPaths.length - 1;
      await savePhotoTag(
        photo.slotKey,
        idx,
        PhotoTag(
          photoPath: photo.path,
          people: photo.people,
          mood: photo.mood ?? 'calm',
          activity: photo.activity ?? 'other',
          isMilestone: photo.isMilestone,
          aiCaption: photo.aiCaption,
        ),
      );
    }
    await removeInboxPhoto(photo.id);
  }

  // ── Clear all (start fresh) ────────────────────────────────────────────────

  Future<void> clearAll() async {
    await _entries.clear();
    await _photoTags.clear();
    await _inbox.clear();
  }
}
