import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/models/baby_entry_model.dart';
import 'core/models/baby_journey_model.dart';
import 'core/models/photo_tag_model.dart';
import 'data/baby_repository.dart';
import 'app.dart';

// Hive typeId registry:
// 0 = BabyEntryAdapter
// 1 = BabyJourneyAdapter
// 2 = PhotoTagAdapter

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(BabyEntryAdapter());
  Hive.registerAdapter(BabyJourneyAdapter());
  Hive.registerAdapter(PhotoTagAdapter());
  await BabyRepository.instance.init();
  runApp(const GrowBookApp());
}
