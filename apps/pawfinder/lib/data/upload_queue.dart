import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:pawfinder/data/local_data.dart';

class UploadQueueNotifier extends Notifier<List<String>> {
  static const _hiveKey = 'upload_queue';

  @override
  List<String> build() {
    final box = Hive.box(boxKey);
    final raw = box.get(_hiveKey);
    if (raw is! String) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<String>().toList();
    } catch (_) {
      return [];
    }
  }

  void enqueue(String documentId) {
    if (documentId.isEmpty) return;
    if (state.contains(documentId)) return;
    state = [...state, documentId];
    _persist();
  }

  void markUploaded(List<String> ids) {
    if (ids.isEmpty) return;
    final uploaded = ids.toSet();
    state = state.where((id) => !uploaded.contains(id)).toList();
    _persist();
  }

  void restoreAll(List<String> ids) {
    if (ids.isEmpty) return;
    final merged = <String>[...ids, ...state];
    final seen = <String>{};
    state = merged.where((id) => seen.add(id)).toList();
    _persist();
  }

  void _persist() {
    Hive.box(boxKey).put(_hiveKey, jsonEncode(state));
  }
}

final uploadQueueProvider = NotifierProvider<UploadQueueNotifier, List<String>>(
  UploadQueueNotifier.new,
);
