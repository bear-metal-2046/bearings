import 'dart:math' show sqrt;

import 'forms.dart';
import 'graph.dart';
import 'program.dart';
import 'sources.dart';
import 'value.dart';

part 'calculation.dart';
part 'analysis_runtime.dart';

const gamePackFieldNamespace = '@field';

GameGraphOutputRef gamePackFieldRef(String id) =>
    (graph: gamePackFieldNamespace, output: id);

String gamePackScoutFieldId(String form, String field) => '$form.$field';

enum GamePackRollup {
  average('Average across this event'),
  yesPercent('% of matches marked Yes');

  const GamePackRollup(this.label);
  final String label;
}

GameGraphOutputRef gamePackRollupRef(String field, GamePackRollup rollup) =>
    gamePackFieldRef('${rollup.name}:$field');

({String field, GamePackRollup rollup})? gamePackRollupOf(String id) {
  final separator = id.indexOf(':');
  if (separator < 0) return null;
  final rollup = GamePackRollup.values
      .where((item) => item.name == id.substring(0, separator))
      .firstOrNull;
  return rollup == null
      ? null
      : (field: id.substring(separator + 1), rollup: rollup);
}

GameGraphOutputRef readGamePackResult(
  Map<String, dynamic> json, {
  String key = 'result',
}) {
  final field = json[key] as String;
  final rollup = json['rollup'] as String?;
  return rollup == null
      ? gamePackFieldRef(field)
      : gamePackRollupRef(field, GamePackRollup.values.byName(rollup));
}

Map<String, String> writeGamePackResult(
  GameGraphOutputRef ref, {
  String key = 'result',
}) {
  if (ref.graph != gamePackFieldNamespace) {
    throw ArgumentError(
      'Only named results can be used outside a calculation.',
    );
  }
  final choice = gamePackRollupOf(ref.output);
  return {
    key: choice?.field ?? ref.output,
    if (choice != null) 'rollup': choice.rollup.name,
  };
}

enum GamePackGrain {
  event('Event'),
  team('Team at event'),
  match('Match'),
  allianceMatch('Alliance in match'),
  teamMatch('Team in match');

  const GamePackGrain(this.label);
  final String label;

  bool canRead(GamePackGrain other) =>
      this == other ||
      other == event ||
      switch (this) {
        teamMatch => true,
        allianceMatch => other == match,
        _ => false,
      };
}

enum GamePackResultOrigin {
  schedule('Match data'),
  scouting('Scouting'),
  official('TBA'),
  calculated('Calculated');

  const GamePackResultOrigin(this.label);
  final String label;
}

typedef GamePackResultInfo = ({
  String label,
  GamePackType type,
  GamePackGrain? grain,
  GamePackResultOrigin origin,
});

class GamePackTbaField {
  GamePackTbaField({
    required this.id,
    required this.label,
    required this.grain,
    required this.type,
    required List<String> paths,
    this.numericText = false,
  }) : paths = List.unmodifiable(paths);

  final String id;
  final String label;
  final GamePackGrain grain;
  final GamePackType type;

  /// Relative to the payload. {alliance}, {robot}, {position}, and {slot}
  /// come from the lineup (red, robot2, 2, and 1 for the second red robot).
  final List<String> paths;
  final bool numericText;

  factory GamePackTbaField.fromJson(Map<String, dynamic> json) =>
      GamePackTbaField(
        id: json['id'] as String,
        label: json['label'] as String,
        grain: GamePackGrain.values.byName(json['grain'] as String),
        type: GamePackType.fromJson(json['type']),
        paths: (json['paths'] as List).cast<String>(),
        numericText: json['numericText'] == true,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'grain': grain.name,
    'type': type.toJson(),
    'paths': paths,
    if (numericText) 'numericText': true,
  };
}

enum GamePackReportChoice {
  latest('Latest report'),
  earliest('First report');

  const GamePackReportChoice(this.label);
  final String label;
}

enum GamePackRecipe {
  average('Average'),
  sum('Sum'),
  count('Count reported values'),
  rate('Percentage true'),
  mostCommon('Most common'),
  series('Values by match'),
  add('Add values'),
  subtract('Subtract values'),
  meanOf('Average of values'),
  any('Any of these'),
  condition('Test a value'),
  excludeValue('Hide a value'),
  text('Join text'),
  latestNote('Latest nonblank note'),
  scale('Scale to official total'),
  rows('Table or match trend'),
  ballotRank('Ballot rank'),
  ballotScore('Standardized ballot score'),
  compare('Compare alliance totals'),
  flagged('Flagged rows'),
  countRows('Count rows'),
  countLabel('Count with label'),
  constant('Fixed value'),
  multiply('Multiply'),
  divide('Divide'),
  fallback('Use fallback'),
  choose('If / then / else'),
  less('Less than'),
  all('All of these'),
  not('Reverse yes or no'),
  empirical('Distribution from values'),
  bernoulli('Yes/no distribution'),
  sample('Draw from a distribution'),
  simulate('Run repeated trials'),
  quantile('Percentile');

  const GamePackRecipe(this.label);
  final String label;

  bool get reducesRows => switch (this) {
    average || sum || count || rate || mostCommon || series => true,
    _ => false,
  };
}

enum GamePackCondition {
  equals('Equals'),
  different('Does not equal'),
  positive('Greater than zero'),
  provided('Is provided');

  const GamePackCondition(this.label);
  final String label;
}

const _number = GamePackType.number;
const _integer = GamePackType.integer;
const _text = GamePackType.text;
const _boolean = GamePackType.boolean;
const _texts = GamePackType.list(_text);
const _official = GamePackResultOrigin.official;
const _match = GamePackGrain.match;
const _allianceMatch = GamePackGrain.allianceMatch;
const _teamMatch = GamePackGrain.teamMatch;
const _team = GamePackGrain.team;
const _event = GamePackGrain.event;

GamePackGrain scoutingGrain(GamePackFormKind kind) => switch (kind) {
  GamePackFormKind.match => _teamMatch,
  GamePackFormKind.strategy => _allianceMatch,
  _ => _team,
};

const _matchFields =
    <String, (String, GamePackType, GamePackGrain, GamePackResultOrigin)>{
      'match_id': ('Match key', _text, _match, GamePackResultOrigin.schedule),
      'match_label': (
        'Match label',
        _text,
        _match,
        GamePackResultOrigin.schedule,
      ),
      'match_level': (
        'Match level',
        _text,
        _match,
        GamePackResultOrigin.schedule,
      ),
      'alliance': (
        'Alliance color',
        _text,
        _allianceMatch,
        GamePackResultOrigin.schedule,
      ),
      'team_key': ('Team key', _text, _team, GamePackResultOrigin.schedule),
      'station': (
        'Station',
        _integer,
        _teamMatch,
        GamePackResultOrigin.schedule,
      ),
      'report_id': (
        'Match report ID',
        _text,
        _teamMatch,
        GamePackResultOrigin.scouting,
      ),
      'official_score': (
        'Official final score',
        _number,
        _allianceMatch,
        _official,
      ),
    };

final _comparisonRows = GamePackType.list(
  GamePackType.record({
    'match': _text,
    'alliance': _text,
    'scouted': _number,
    'official': _number,
    'deviation_percent': _number,
    'flagged': _boolean,
  }),
);

/// The analysis catalog validates and resolves references without lowering recipes
/// to custom graph nodes. Drafts can expose independently valid values as they edit.
class GamePackAnalysis {
  GamePackAnalysis({
    required List<GamePackField> fields,
    required List<GamePackForm> forms,
    List<GamePackTbaField> tbaFields = const [],
    List<GamePackCalculation> calculations = const [],
    Map<String, GamePackReportChoice> reportChoices = const {},
    bool validate = true,
  }) : tbaFields = List.unmodifiable(tbaFields),
       calculations = List.unmodifiable(calculations),
       reportChoices = Map.unmodifiable(reportChoices),
       _forms = {for (final form in forms) form.id: form} {
    final scoutFields = {for (final field in fields) field.id: field};
    for (final form in forms) {
      final pages = <String, String>{};
      final counts = <String, int>{};
      for (final page in form.pages) {
        for (final control in page.controls) {
          final field = scoutFields[control.field];
          if (field == null || pages.containsKey(field.id)) continue;
          pages[field.id] = page.label;
          counts.update(field.label, (count) => count + 1, ifAbsent: () => 1);
        }
      }
      for (final entry in pages.entries) {
        final field = scoutFields[entry.key]!;
        final label = counts[field.label] == 1
            ? field.label
            : '${entry.value} › ${field.label}';
        _scouted[gamePackScoutFieldId(form.id, field.id)] = (
          form,
          field,
          label,
        );
      }
    }
    _tba = {for (final field in tbaFields) field.id: field};
    _calculations = {for (final recipe in calculations) recipe.id: recipe};
    if (!validate) return;
    final ids = _matchFields.keys.toSet();
    for (final field in tbaFields) {
      validateGamePackIdentifier(field.id);
      validateGamePackLabel(field.label);
      if (!ids.add(field.id))
        throw FormatException('Duplicate result: ${field.id}.');
      final needsAlliance = field.paths.any(
        (path) => path.contains('{alliance}'),
      );
      final needsStation = field.paths.any(
        (path) =>
            path.contains('{robot}') ||
            path.contains('{slot}') ||
            path.contains('{position}'),
      );
      if (![_match, _allianceMatch, _teamMatch].contains(field.grain) ||
          needsAlliance && !field.grain.canRead(_allianceMatch) ||
          needsStation && field.grain != _teamMatch ||
          field.paths.isEmpty ||
          field.paths.length > 12 ||
          field.paths.any(
            (path) =>
                path.length > 300 ||
                path.split('.').any((part) => part.isEmpty),
          ) ||
          field.numericText &&
              field.type != _number &&
              field.type != _integer) {
        throw FormatException(
          'Check the TBA path, type and assignment for ${field.label}.',
        );
      }
    }
    if (tbaFields.length > 256 || calculations.length > 512) {
      throw const FormatException(
        'A pack supports 256 TBA mappings and 512 calculations.',
      );
    }
    for (final entry in reportChoices.entries) {
      if (!_forms.containsKey(entry.key))
        throw FormatException('Unknown scouting form: ${entry.key}.');
    }
    for (final calculation in calculations) {
      validateGamePackIdentifier(calculation.id);
      validateGamePackLabel(calculation.label);
      if (!ids.add(calculation.id))
        throw FormatException('Duplicate result: ${calculation.id}.');
      if (calculation.nodes.isEmpty ||
          calculation.nodes.length > 128 ||
          calculation.nodesById.length != calculation.nodes.length ||
          !calculation.nodesById.containsKey(calculation.result)) {
        throw FormatException(
          '${calculation.label} needs a result and 1–128 uniquely named nodes.',
        );
      }
      for (final node in calculation.nodes) {
        validateGamePackIdentifier(node.id);
      }
    }
    for (final calculation in calculations) {
      resultInfo(gamePackFieldRef(calculation.id));
      for (final node in calculation.nodes) {
        nodeInfo(calculation.id, node.id);
      }
    }
  }

  final List<GamePackTbaField> tbaFields;
  final List<GamePackCalculation> calculations;
  final Map<String, GamePackReportChoice> reportChoices;
  final Map<String, GamePackForm> _forms;
  final _scouted = <String, (GamePackForm, GamePackField, String)>{};
  late final Map<String, GamePackTbaField> _tba;
  late final Map<String, GamePackCalculation> _calculations;
  final _metadata = <GameGraphOutputRef, GamePackResultInfo>{};
  final _resolving = <GameGraphOutputRef>{};

  Iterable<GameGraphOutputRef> get namedFieldRefs => [
    ..._matchFields.keys,
    ..._scouted.keys,
    ..._tba.keys,
    ..._calculations.keys,
  ].map(gamePackFieldRef);

  Iterable<GameGraphOutputRef> get fieldRefs sync* {
    for (final ref in namedFieldRefs) {
      yield ref;
      if (_eligibleRollup(tryInfo(ref)) case final rollup?) {
        yield gamePackRollupRef(ref.output, rollup);
      }
    }
  }

  static GamePackRollup? _eligibleRollup(GamePackResultInfo? info) {
    if (info == null ||
        info.grain != _teamMatch ||
        info.origin == GamePackResultOrigin.schedule)
      return null;
    if (info.type == _boolean) return GamePackRollup.yesPercent;
    return _number.accepts(info.type) ? GamePackRollup.average : null;
  }

  final _rollups = <String, GamePackCalculation>{};

  late final Map<GameGraphOutputRef, GamePackResultInfo> catalog =
      Map.unmodifiable({
        for (final ref in fieldRefs)
          if (tryInfo(ref) case final info?) ref: info,
      });

  GamePackResultInfo? tryInfo(GameGraphOutputRef ref) {
    try {
      return resultInfo(ref);
    } on FormatException {
      return null;
    }
  }

  GamePackResultInfo nodeInfo(String calculation, String node) =>
      resultInfo((graph: calculation, output: node));

  GamePackCalculation? calculationById(String id) {
    if (_calculations[id] case final current?) return current;
    final choice = gamePackRollupOf(id);
    if (choice == null) return null;
    if (_rollups[id] case final current?) return current;
    final ref = gamePackFieldRef(choice.field);
    final source = resultInfo(ref);
    if (_eligibleRollup(source) != choice.rollup) {
      throw FormatException(
        '${source.label} cannot use ${choice.rollup.label.toLowerCase()}.',
      );
    }
    final label = source.label.split(' · ').first;
    return _rollups[id] = GamePackCalculation.recipe(
      id: id,
      label: choice.rollup == GamePackRollup.average
          ? 'Average $label'
          : '$label (% Yes)',
      operation: choice.rollup == GamePackRollup.average
          ? GamePackRecipe.average
          : GamePackRecipe.rate,
      grain: _team,
      inputs: {'value': ref},
      rowGrain: _teamMatch,
      scheduleRows: true,
    );
  }

  GamePackCalculationNode _node(GameGraphOutputRef ref) =>
      calculationById(ref.graph)?.nodesById[ref.output] ??
      (throw FormatException('Unknown calculation node: ${ref.output}.'));

  GameGraphOutputRef _sourceRef(GameGraphOutputRef ref) {
    if (ref.graph == gamePackFieldNamespace) return ref;
    final node = _node(ref);
    return node is GamePackInputNode && node.field != null
        ? gamePackFieldRef(node.field!)
        : ref;
  }

  GamePackResultInfo resultInfo(GameGraphOutputRef ref) {
    if (_metadata[ref] case final info?) return info;
    if (!_resolving.add(ref))
      throw FormatException('Calculation cycle at ${ref.output}.');
    try {
      return _metadata[ref] = _resolveInfo(ref);
    } finally {
      _resolving.remove(ref);
    }
  }

  GamePackResultInfo _resolveInfo(GameGraphOutputRef ref) {
    final id = ref.output;
    if (ref.graph != gamePackFieldNamespace) {
      return switch (_node(ref)) {
        GamePackInputNode(:final field) =>
          field == null
              ? (throw const FormatException('Choose an input field.'))
              : resultInfo(gamePackFieldRef(field)),
        final GamePackStepNode node => (
          label: node.operation.label,
          type: _recipeType(_Step(ref.graph, node)),
          grain: node.grain,
          origin: GamePackResultOrigin.calculated,
        ),
      };
    }
    if (_matchFields[id] case (
      final label,
      final type,
      final grain,
      final origin,
    )) {
      return (label: label, type: type, grain: grain, origin: origin);
    }
    if (_scouted[id] case (final form, final field, final label)) {
      return (
        label: '$label · ${form.label}',
        type: field.type,
        grain: scoutingGrain(form.kind),
        origin: GamePackResultOrigin.scouting,
      );
    }
    if (_tba[id] case final field?) {
      return (
        label: field.label,
        type: field.type,
        grain: field.grain,
        origin: _official,
      );
    }
    final calculation = calculationById(id);
    if (calculation == null) throw FormatException('Unknown field: $id.');
    final result = nodeInfo(id, calculation.result);
    return (
      label: calculation.label,
      type: result.type,
      grain: result.grain,
      origin: GamePackResultOrigin.calculated,
    );
  }

  GamePackType _recipeType(_Step recipe) {
    final op = recipe.operation;
    Never fail(String reason) =>
        throw FormatException('${recipe.label}: $reason');
    if (op == GamePackRecipe.scale) {
      const supported = {'scouted', 'official', 'extra'};
      for (final port in recipe.inputs.keys) {
        if (!supported.contains(port)) fail('unsupported input "$port".');
      }
    }
    final inputs = recipe.inputs.map(
      (key, ref) => MapEntry(key, resultInfo(ref)),
    );
    if (op != GamePackRecipe.constant && inputs.isEmpty || inputs.length > 32)
      fail('choose 1–32 inputs.');
    GamePackResultInfo input(String key) => inputs[key] ?? fail('choose $key.');
    void accepts(GamePackType type, GamePackResultInfo info) {
      if (!type.accepts(info.type)) fail('${info.label} must be $type.');
    }

    void compatible(GamePackGrain grain, Iterable<GamePackResultInfo> values) {
      for (final info in values) {
        if (info.grain case final source? when !grain.canRead(source)) {
          fail(
            '${info.label} is ${source.label.toLowerCase()}, unavailable for ${grain.label.toLowerCase()}.',
          );
        }
      }
    }

    if (op.reducesRows || op == GamePackRecipe.rows) {
      final row = recipe.node.rowGrain ?? inputs.values.first.grain;
      if (row == null || !row.canRead(recipe.grain))
        fail('choose a compatible row scope.');
      compatible(row, inputs.values);
      if (op == GamePackRecipe.rows) {
        recipe.inputs.keys.forEach(validateGamePackIdentifier);
        return GamePackType.list(
          GamePackType.record(
            inputs.map((key, info) => MapEntry(key, info.type)),
          ),
        );
      }
      final value = input('value');
      if (op == GamePackRecipe.rate) accepts(_boolean, value);
      if (op == GamePackRecipe.mostCommon &&
          ![_text, _boolean, _integer, _number].contains(value.type)) {
        fail('choose a number, text, or yes/no field.');
      }
      if (op == GamePackRecipe.average || op == GamePackRecipe.sum)
        accepts(_number, value);
      return switch (op) {
        GamePackRecipe.series => GamePackType.list(value.type),
        GamePackRecipe.count => _integer,
        GamePackRecipe.mostCommon => value.type,
        _ => _number,
      };
    }

    if (op == GamePackRecipe.scale || op == GamePackRecipe.compare) {
      accepts(_number, input('scouted'));
      accepts(_number, input('official'));
      if (input('scouted').grain != _teamMatch ||
          input('official').grain != _allianceMatch) {
        fail(
          'choose a scouted team-match number and an official alliance-match number.',
        );
      }
      if (inputs['extra'] case final extra?) {
        accepts(_number, extra);
        compatible(_allianceMatch, [extra]);
      }
      if (inputs['scouted_other'] case final other?) {
        accepts(_number, other);
        compatible(_teamMatch, [other]);
      }
      if (op == GamePackRecipe.scale) {
        if (recipe.grain != _teamMatch)
          fail('use Team in match for a scaled result.');
        return _number;
      }
      if (recipe.grain != _event ||
          !recipe.node.threshold.isFinite ||
          recipe.node.threshold < 0 ||
          recipe.node.minimumReports < 1)
        fail('choose a valid event comparison and threshold.');
      return _comparisonRows;
    }

    if (op == GamePackRecipe.ballotRank || op == GamePackRecipe.ballotScore) {
      final ballot = input('value');
      accepts(_texts, ballot);
      if (recipe.grain != _team || ballot.grain != _allianceMatch)
        fail('choose an alliance ballot for a team result.');
      return op == GamePackRecipe.ballotRank ? _integer : _number;
    }
    if (op == GamePackRecipe.latestNote) {
      if (recipe.grain != _team) fail('use Team at event for a latest note.');
      for (final entry in recipe.inputs.entries) {
        accepts(_text, input(entry.key));
        final ref = _sourceRef(entry.value);
        final scouted = _scouted[ref.output];
        if (ref.graph != gamePackFieldNamespace ||
            scouted == null ||
            ![_team, _teamMatch].contains(scoutingGrain(scouted.$1.kind))) {
          fail('choose text answers from team scouting forms.');
        }
      }
      return _text;
    }

    compatible(recipe.grain, inputs.values);
    switch (op) {
      case GamePackRecipe.constant:
        final value = recipe.node.comparisonValue;
        return switch (value) {
          bool() => _boolean,
          int() => _integer,
          num() when value.isFinite => _number,
          String() => _text,
          _ => fail('enter a number, text, or yes/no value.'),
        };
      case GamePackRecipe.any || GamePackRecipe.all || GamePackRecipe.not:
        for (final info in inputs.values) {
          accepts(_boolean, info);
        }
        if (op == GamePackRecipe.not) input('value');
        return _boolean;
      case GamePackRecipe.add ||
          GamePackRecipe.meanOf ||
          GamePackRecipe.multiply:
        for (final info in inputs.values) {
          accepts(_number, info);
        }
        return _number;
      case GamePackRecipe.subtract ||
          GamePackRecipe.divide ||
          GamePackRecipe.less:
        accepts(_number, input('left'));
        accepts(_number, input('right'));
        return op == GamePackRecipe.less ? _boolean : _number;
      case GamePackRecipe.fallback || GamePackRecipe.choose:
        final first = input(op == GamePackRecipe.choose ? 'then' : 'value');
        final second = input(op == GamePackRecipe.choose ? 'else' : 'fallback');
        if (op == GamePackRecipe.choose) accepts(_boolean, input('condition'));
        if (first.type.accepts(second.type)) return first.type;
        if (second.type.accepts(first.type)) return second.type;
        fail('both alternatives must have compatible types.');
      case GamePackRecipe.empirical:
        final type = input('value').type;
        if (type.kind != GamePackTypeKind.list)
          fail('choose a list of values.');
        return GamePackType.distribution(type.element!);
      case GamePackRecipe.bernoulli:
        accepts(_number, input('value'));
        return const GamePackType.distribution(_boolean);
      case GamePackRecipe.sample:
        final type = input('value').type;
        if (type.kind != GamePackTypeKind.distribution)
          fail('choose a distribution.');
        return type.element!;
      case GamePackRecipe.simulate:
        if (recipe.node.trials < 1 || recipe.node.trials > 1000) {
          fail('choose 1–1000 trials.');
        }
        return GamePackType.list(input('value').type);
      case GamePackRecipe.quantile:
        accepts(const GamePackType.list(_number), input('value'));
        final fraction = recipe.node.comparisonValue;
        if (fraction is! num ||
            !fraction.isFinite ||
            fraction < 0 ||
            fraction > 1) {
          fail('choose a percentile between 0 and 1.');
        }
        return _number;
      case GamePackRecipe.excludeValue:
        final value = input('value');
        if (recipe.node.comparisonValue == null ||
            !value.type.acceptsValue(
              GamePackValue.of(recipe.node.comparisonValue),
            )) {
          fail('choose a value to exclude.');
        }
        return value.type;
      case GamePackRecipe.condition:
        final value = input('value');
        if (recipe.node.condition == GamePackCondition.positive)
          accepts(_number, value);
        if ([
              GamePackCondition.equals,
              GamePackCondition.different,
            ].contains(recipe.node.condition) &&
            (recipe.node.comparisonValue == null ||
                !value.type.acceptsValue(
                  GamePackValue.of(recipe.node.comparisonValue),
                ))) {
          fail('choose a comparison value of type ${value.type}.');
        }
        return _boolean;
      case GamePackRecipe.text:
        accepts(_texts, input('value'));
        return _text;
      case GamePackRecipe.flagged:
        accepts(_comparisonRows, input('value'));
        return _comparisonRows;
      case GamePackRecipe.countRows:
        if (input('value').type.kind != GamePackTypeKind.list)
          fail('choose a list or table.');
        return _integer;
      case GamePackRecipe.countLabel:
        accepts(_integer, input('value'));
        return _text;
      default:
        fail('unsupported operation.');
    }
  }
}
