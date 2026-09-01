import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bearimetric/providers/match_config_provider.dart';
import 'package:bearimetric/providers/scouting_flow_provider.dart';
import 'package:bearimetric/providers/scouting_providers.dart';
import 'package:ui/widgets/forms/match_form_renderer.dart';

class MatchPage extends ConsumerWidget {
  final int index;

  const MatchPage({super.key, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(scoutingSessionProvider);
    final configAsync = ref.watch(matchConfigProvider);
    final teamAsync = ref.watch(teamNumberForSessionProvider);
    final store = ref.read(matchFormStoreProvider);

    return configAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (config) {
        final eventKey = session.event?.key;
        final matchNumber = session.matchNumber;
        final pos = session.position?.posIndex;
        final scoutName = session.scout?.name;

        if (eventKey == null || matchNumber == null || pos == null) {
          return const Center(child: CircularProgressIndicator());
        }

        if (index >= config.pages.length) {
          return const Center(child: CircularProgressIndicator());
        }
        var data = store.load(eventKey, matchNumber, pos);
        if (data == null) {
          data = MatchFormData.blank(
            eventKey: eventKey,
            matchNumber: matchNumber,
            pos: pos,
            season: config.meta.season,
            configVersion: config.meta.version,
            scoutedBy: scoutName,
          );
        } else if (scoutName != null && data.scoutedBy != scoutName) {
          data = data.copyWith(scoutedBy: scoutName);
        }

        final teamNumber = teamAsync.asData?.value;
        if (teamNumber != null && data.teamNumber != teamNumber) {
          data = data.copyWith(teamNumber: teamNumber);
        }

        final hydratedData = _hydrateAllConfiguredFields(config, data);
        if (hydratedData != data) {
          store.save(hydratedData);
        }

        return MatchFormRenderer(
          key: ValueKey('$eventKey:$matchNumber:$pos'),
          page: config.pages[index],
          initialData: hydratedData,
          onChanged: (next) {
            final toSave = next.copyWith(scoutedBy: scoutName);
            store.save(toSave);
          },
          onNextPressed: () {
            ref.read(scoutingFlowControllerProvider).nextMatch();
            context.go('/match/auto');
          },
        );
      },
    );
  }
}

MatchFormData _hydrateAllConfiguredFields(
  MatchConfig config,
  MatchFormData data,
) {
  final sections = <String, Map<String, dynamic>>{
    for (final entry in data.sections.entries)
      entry.key: Map<String, dynamic>.from(entry.value),
  };

  var changed = false;

  for (final page in config.pages) {
    if (page.sectionId.trim().isEmpty) continue;

    final section = Map<String, dynamic>.from(
      sections[page.sectionId] ?? const {},
    );
    var sectionChanged = false;

    for (final component in page.components) {
      final fieldId = component.fieldId.trim();
      if (fieldId.isEmpty || component.type == 'Nxt') continue;
      if (section.containsKey(fieldId)) continue;

      final defaultValue = _defaultFieldValue(component);
      if (defaultValue == null) continue;

      section[fieldId] = defaultValue;
      changed = true;
      sectionChanged = true;
    }

    if (sectionChanged) {
      sections[page.sectionId] = section;
    }
  }

  if (!changed) return data;
  return data.copyWith(sections: sections);
}

dynamic _defaultFieldValue(ComponentConfig component) {
  switch (component.type) {
    case 'volumetric_button':
    case 'int_button':
    case 'int_text_box':
    case 'tristate':
      return 0;
    case 'toggle_switch':
    case 'checkbox':
      return false;
    case 'text_box':
      return '';
    case 'slider':
      return 0.0;
    case 'segmented_button':
      final isMultiSelect = component.parameters['multi_select'] == true;
      return isMultiSelect ? <int>[] : 0;
    case 'dropdown':
      final rawOptions = component.parameters['options'];
      if (rawOptions is! List || rawOptions.isEmpty) return null;
      return rawOptions.first.toString();
    default:
      return null;
  }
}
