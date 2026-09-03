import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shared_preferences_provider.dart';

const _matchPreviewLayoutKey = 'matchPreviewLayout';

enum MatchPreviewLayout {
  horizontal('Horizontal'),
  vertical('Vertical');

  const MatchPreviewLayout(this.label);

  final String label;
}

final matchPreviewLayoutProvider =
    NotifierProvider<MatchPreviewLayoutNotifier, MatchPreviewLayout>(
      MatchPreviewLayoutNotifier.new,
    );

class MatchPreviewLayoutNotifier extends Notifier<MatchPreviewLayout> {
  @override
  MatchPreviewLayout build() {
    final savedValue = ref
        .read(sharedPreferencesProvider)
        .getString(_matchPreviewLayoutKey);
    return MatchPreviewLayout.values.firstWhere(
      (layout) => layout.name == savedValue,
      orElse: () => MatchPreviewLayout.horizontal,
    );
  }

  Future<void> setLayout(MatchPreviewLayout layout) async {
    state = layout;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_matchPreviewLayoutKey, layout.name);
  }
}
