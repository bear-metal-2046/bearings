import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'match_config_provider.g.dart';

@Riverpod(keepAlive: true)
Future<MatchConfig> matchConfig(Ref ref) async {
  final json = jsonDecode(
    await rootBundle.loadString('packages/ui/assets/forms/ui_creator.json'),
  );
  return MatchConfig.fromJson(Map<String, dynamic>.from(json as Map));
}
