import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/models/baby_entry_model.dart';
import '../core/models/baby_journey_model.dart';
import '../core/models/photo_tag_model.dart';

class BabyRepository {
  static final instance = BabyRepository._();
  BabyRepository._();

  late Box<BabyEntry> _entries;
  late Box<BabyJourney> _journeys;
  late Box<dynamic> _settings;
  late Box<PhotoTag> _photoTags;

  static const _entriesBoxName = 'babyEntries';
  static const _journeyBoxName = 'babyJourney';
  static const _settingsBoxName = 'growbookSettings';
  static const _photoTagsBoxName = 'photoTags';
  static const _journeyKey = 0;

  // Settings keys
  static const _keyFolderPath = 'cameraFolderPath';
  static const _keyLastScanAt = 'lastScanAt';

  Future<void> init() async {
    _entries = await Hive.openBox<BabyEntry>(_entriesBoxName);
    _journeys = await Hive.openBox<BabyJourney>(_journeyBoxName);
    _settings = await Hive.openBox(_settingsBoxName);
    _photoTags = await Hive.openBox<PhotoTag>(_photoTagsBoxName);

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

  // ── Entries ────────────────────────────────────────────────────────────────

  BabyEntry? getEntry(String slotKey) => _entries.get(slotKey);

  Future<void> saveEntry(BabyEntry entry) =>
      _entries.put(entry.slotKey, entry);

  /// Reactive listenable for the entries box.
  ValueListenable<Box<BabyEntry>> get entriesListenable =>
      _entries.listenable();

  // ── Photo tags ─────────────────────────────────────────────────────────────

  /// Key format: "{slotKey}_{photoIndex}"
  static String _tagKey(String slotKey, int photoIndex) =>
      '${slotKey}_$photoIndex';

  PhotoTag? getPhotoTag(String slotKey, int photoIndex) =>
      _photoTags.get(_tagKey(slotKey, photoIndex));

  Future<void> savePhotoTag(String slotKey, int photoIndex, PhotoTag tag) =>
      _photoTags.put(_tagKey(slotKey, photoIndex), tag);

  /// Returns a list of tags (nullable) indexed 1:1 with photoPaths.
  List<PhotoTag?> getPhotoTags(String slotKey, int count) =>
      List.generate(count, (i) => _photoTags.get(_tagKey(slotKey, i)));

  /// Reactive listenable for the photo tags box.
  ValueListenable<Box<PhotoTag>> get photoTagsListenable =>
      _photoTags.listenable();
}
