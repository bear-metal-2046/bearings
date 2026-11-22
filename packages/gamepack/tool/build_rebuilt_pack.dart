import 'dart:convert';
import 'dart:io';

import 'package:gamepack/gamepack.dart';

import 'rebuilt_analysis.dart';

typedef _Json = Map<String, dynamic>;

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run packages/gamepack/tool/build_rebuilt_pack.dart <output.json>',
    );
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent.parent.parent;
  final pack = buildRebuiltPack(
    jsonDecode(
      File('${root.path}/packages/gamepack/tool/fixtures/match_layout.json')
          .readAsStringSync(),
    ) as _Json,
    jsonDecode(
      File('${root.path}/packages/gamepack/tool/fixtures/pit_layout.json')
          .readAsStringSync(),
    ) as _Json,
  );
  File(arguments.single).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(pack.toJson())}\n',
  );
}

GamePackDefinition buildRebuiltPack(_Json matchSchema, _Json pitSchema) {
  final fields = <GamePackField>[];
  final forms = <GamePackForm>[];
  GamePackControl bind(
    GamePackField field,
    GamePackControlType type, [
    GamePackPlacement? placement,
  ]) {
    fields.add(field);
    return GamePackControl(field: field.id, type: type, placement: placement);
  }

  forms.add(
    GamePackForm(
      id: 'match',
      label: 'Match scouting',
      kind: GamePackFormKind.match,
      pages: (matchSchema['pages'] as List).cast<_Json>().map((page) {
        final pageId = page['sectionId'] as String;
        final label = page['title'] as String;
        final rowScale = pageId == 'tele' ? 2 : 1;
        final controls = <GamePackControl>[];
        for (final component in (page['components'] as List).cast<_Json>()) {
          if (component['fieldId'] == '') continue;
          final id = '${pageId}_${component['fieldId']}';
          final title = component['alias'] as String;
          final params = component['parameters'] as _Json;
          final grid = component['layout'] as _Json;
          final location = GamePackPlacement(
            (grid['x'] as num).toInt(),
            ((grid['y'] as num) * rowScale).toInt(),
            (grid['w'] as num).toInt(),
            ((grid['h'] as num) * rowScale).toInt(),
          );
          final (
            valueType,
            control,
            initial,
            lower,
            upper,
          ) = switch (component['type']) {
            'checkbox' || 'toggle_switch' => (
              GamePackType.boolean,
              GamePackControlType.toggle,
              false,
              null,
              null,
            ),
            'int_button' => (
              GamePackType.integer,
              GamePackControlType.stepper,
              0,
              0,
              null,
            ),
            'volumetric_button' => (
              GamePackType.integer,
              GamePackControlType.counter,
              0,
              0,
              null,
            ),
            'slider' => (
              GamePackType.number,
              GamePackControlType.slider,
              null,
              0,
              100,
            ),
            'text_box' => (
              GamePackType.text,
              GamePackControlType.multiline,
              null,
              null,
              null,
            ),
            'segmented_button' when params['multi_select'] == true => (
              const GamePackType.list(GamePackType.text),
              GamePackControlType.multiChoice,
              null,
              null,
              null,
            ),
            'segmented_button' => (
              GamePackType.text,
              GamePackControlType.segmented,
              null,
              null,
              null,
            ),
            _ => throw FormatException(
              'Unsupported legacy match control ${component['type']}.',
            ),
          };
          controls.add(
            bind(
              GamePackField(
                id,
                title,
                type: valueType,
                isRequired: false,
                choices: (params['options'] as List? ?? []).cast<String>(),
                defaultValue: initial,
                minimum: lower,
                maximum: upper,
              ),
              control,
              location,
            ),
          );
        }
        final columns = (page['width'] as num).toInt();
        if (pageId == 'endgame') {
          controls.add(
            bind(
              const GamePackField(
                'endgame_fouls',
                'Fouls',
                type: GamePackType.integer,
                minimum: 0,
                defaultValue: 0,
                isRequired: false,
              ),
              GamePackControlType.stepper,
              GamePackPlacement(0, 5, columns, 1),
            ),
          );
        }
        return GamePackFormPage.grid(
          id: pageId,
          label: label,
          columns: columns,
          rows: ((page['height'] as num) * rowScale).toInt(),
          controls: controls,
        );
      }).toList(),
    ),
  );

  forms.add(
    GamePackForm(
      id: 'strategy',
      label: 'Strategy scouting',
      kind: GamePackFormKind.strategy,
      pages: [
        GamePackFormPage.scrolling(
          id: 'rankings',
          label: 'Strategy',
          sections: [
            GamePackSection.controls(
              id: 'rankings',
              label: 'Alliance rankings',
              controls: [
                for (final (id, label) in rebuiltRankings)
                  bind(
                    GamePackField(
                      id,
                      label,
                      type: const GamePackType.list(GamePackType.text),
                    ),
                    GamePackControlType.ranking,
                  ),
              ],
            ),
            GamePackSection.controls(
              id: 'human_player',
              label: 'Human player',
              controls: [
                for (final phase in ['auto', 'tele'])
                  bind(
                    GamePackField(
                      '${phase}_human_player',
                      phase == 'auto'
                          ? 'Auto Human Player'
                          : 'Tele Human Player',
                      type: GamePackType.integer,
                      defaultValue: 0,
                      minimum: 0,
                    ),
                    GamePackControlType.stepper,
                  ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  forms.add(
    GamePackForm(
      id: 'pit',
      label: 'Pit scouting',
      kind: GamePackFormKind.pit,
      pages: [
        GamePackFormPage.scrolling(
          id: 'pit',
          label: 'Pit scouting',
          sections: [
            for (final section in (pitSchema['sections'] as List).cast<_Json>())
              GamePackSection.controls(
                id: section['id'] as String,
                label: section['displayName'] as String,
                controls: [
                  for (final control
                      in (section['fields'] as List).cast<_Json>())
                    _pitControl(control, bind),
                ],
              ),
          ],
        ),
      ],
    ),
  );

  forms.add(
    GamePackForm(
      id: 'observation',
      label: 'Observations',
      kind: GamePackFormKind.observation,
      pages: [
        GamePackFormPage.scrolling(
          id: 'observation',
          label: 'Observation',
          sections: [
            GamePackSection.controls(
              id: 'notes',
              label: 'Notes',
              controls: [
                bind(
                  GamePackField(
                    'observation_note',
                    'Notes',
                    type: GamePackType.text,
                  ),
                  GamePackControlType.multiline,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  final analysis = buildRebuiltAnalysis(fields, forms);
  return GamePackDefinition.typed(
    name: '2026 REBUILT',
    season: 2026,
    fields: fields,
    forms: forms,
    tbaFields: analysis.tbaFields,
    calculations: analysis.calculations,
    results: analysis.results,
  );
}

GamePackControl _pitControl(
  _Json control,
  GamePackControl Function(GamePackField, GamePackControlType) bind,
) {
  final legacyId = control['id'] as String;
  final fieldId =
      'pit_${legacyId.replaceAllMapped(RegExp('[A-Z]'), (match) => '_${match[0]!.toLowerCase()}')}';
  final params = control['params'] as _Json;
  final (type, widget) = switch (control['type']) {
    'number' => (GamePackType.number, GamePackControlType.number),
    'single_select' => (GamePackType.text, GamePackControlType.choice),
    'radio' => (GamePackType.text, GamePackControlType.segmented),
    'multi_select' => (
      const GamePackType.list(GamePackType.text),
      GamePackControlType.multiChoice,
    ),
    'slider' => (GamePackType.number, GamePackControlType.slider),
    'multiline_text' => (GamePackType.text, GamePackControlType.multiline),
    _ => throw FormatException(
      'Unsupported legacy pit control ${control['type']}.',
    ),
  };
  return bind(
    GamePackField(
      fieldId,
      control['displayName'] as String,
      type: type,
      isRequired: control['required'] == true,
      defaultValue: control['defaultValue'],
      choices: (params['options'] as List? ?? []).cast<String>(),
      minimum: params['min'] as num?,
      maximum: params['max'] as num?,
    ),
    widget,
  );
}
