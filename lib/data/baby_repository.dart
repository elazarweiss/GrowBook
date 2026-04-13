import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/models/baby_entry_model.dart';
import '../core/models/baby_journey_model.dart';

class BabyRepository {
  static final instance = BabyRepository._();
  BabyRepository._();

  late Box<BabyEntry> _entries;
  late Box<BabyJourney> _journeys;

  static const _entriesBoxName = 'babyEntries';
  static const _journeyBoxName = 'babyJourney';
  static const _journeyKey = 0;

  Future<void> init() async {
    _entries = await Hive.openBox<BabyEntry>(_entriesBoxName);
    _journeys = await Hive.openBox<BabyJourney>(_journeyBoxName);
  }

  // ── Journey ────────────────────────────────────────────────────────────────

  BabyJourney? getJourney() => _journeys.get(_journeyKey);

  Future<void> saveJourney(BabyJourney journey) =>
      _journeys.put(_journeyKey, journey);

  // ── Entries ────────────────────────────────────────────────────────────────

  BabyEntry? getEntry(String slotKey) => _entries.get(slotKey);

  Future<void> saveEntry(BabyEntry entry) =>
      _entries.put(entry.slotKey, entry);

  /// Reactive listenable for the entries box — use with ValueListenableBuilder
  /// to rebuild the timeline whenever a photo is added.
  ValueListenable<Box<BabyEntry>> get entriesListenable =>
      _entries.listenable();
}
