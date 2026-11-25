import 'package:services/providers/grove_provider.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:bearimetric/data/hive_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'scouting_store.dart';

late final SharedPreferences prefs;

Future<void> loadStorage() async {
  await initializeHiveStorage();
  await initializeGroveStorage(persistOnWeb: true);
  await Hive.openBox<String>(scoutingBoxName);
  prefs = await SharedPreferences.getInstance();
}
