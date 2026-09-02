import 'package:hive_ce_flutter/adapters.dart';
import 'package:bearimetric/data/hive_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// the one hive box for all match/strat/queue/schedule data
const boxKey = "localData";

late final SharedPreferences prefs;

Future<void> loadStorage() async {
  await initializeHiveStorage();
  await Hive.openBox(boxKey); // so the code doesn't have to use openBox
  await Hive.openBox(
    'api_cache',
  ); // sticking this here because this is the hive spot ig -jack
  prefs = await SharedPreferences.getInstance();
}
