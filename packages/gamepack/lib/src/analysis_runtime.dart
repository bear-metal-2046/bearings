part of 'analysis.dart';

typedef _Address = (
  GameGraphOutputRef,
  String?,
  String?,
  String?,
  int?,
  String,
);
typedef _Factor = ({GamePackValue value, num? official, num total});

typedef GamePackNodePreview = ({GamePackValue value, String? explanation});

typedef _Slot = ({String alliance, int station});
typedef _Scale = ({
  GameGraphOutputRef scouted,
  GameGraphOutputRef official,
  GameGraphOutputRef? extra,
  bool requirePositive,
});

/// One immutable event snapshot. All consumers share its roster indexes and
/// resolved values, including the factor used by multiple robots in an alliance.
class GamePackAnalysisSession {
  GamePackAnalysisSession({
    required this.analysis,
    required this.event,
    required Map<String, GamePackValue> sources,
    Map<String, GamePackValue> schedule = const {},
    this.seed = 0,
    this.trace = false,
  }) : _schedule = Map.unmodifiable(schedule) {
    for (final row in _list(sources['tba'])) {
      if (row.atPath('match').data case final String match)
        _archive[match] = row;
    }
    for (final row in _list(sources['observations'])) {
      if (row.atPath('event').data != event) continue;
      _reports.add(row);
      if (row.atPath('team').data case final String team) {
        _byTeam.putIfAbsent(team, () => []).add(row);
      }
      if (row.atPath('match').data case final String match) {
        _byMatch.putIfAbsent(match, () => []).add(row);
      }
    }
    for (final match in {
      ..._archive.keys,
      ..._schedule.keys,
      ..._byMatch.keys,
    }) {
      final slots = _slots[match] = {};
      for (final (palette, side) in ['red', 'blue'].indexed) {
        final scheduled = _schedule[match]?.atPath('alliances.$side.team_keys');
        final archived = _archive[match]?.atPath(
          'payload.alliances.$side.team_keys',
        );
        final teams = _list(scheduled).isNotEmpty
            ? _list(scheduled)
            : _list(archived);
        for (final (slot, team) in teams.indexed) {
          if (team.data case final String id) {
            slots[id] = (alliance: side, station: palette * 3 + slot);
          }
        }
      }
      for (final row in _byMatch[match] ?? const <GamePackValue>[]) {
        if ((
              row.atPath('team').data,
              row.atPath('alliance').data,
              row.atPath('station').data,
            )
            case (
              final String team,
              final String alliance,
              final int station,
            )) {
          if (slots.values.every((slot) => slot.station != station)) {
            slots.putIfAbsent(
              team,
              () => (alliance: alliance, station: station),
            );
          }
        }
      }
    }
  }

  final GamePackAnalysis analysis;
  final String event;
  final int seed;
  final bool trace;
  final Map<String, GamePackValue> _schedule;
  final _reportCache = <(String, String?, String?, String?), GamePackValue>{};
  final _rowCache =
      <
        (GamePackGrain, String?, String?, String?, bool, String?),
        List<GamePackScope>
      >{};
  late final _orderedMatches = _slots.keys.toList()..sort(_matchOrder);
  final _archive = <String, GamePackValue>{};
  final _reports = <GamePackValue>[];
  final _byTeam = <String, List<GamePackValue>>{};
  final _byMatch = <String, List<GamePackValue>>{};
  final _slots = <String, Map<String, _Slot>>{};
  final _values = <_Address, GameGraphEvaluation>{};
  final _trialValues = <_Address, GameGraphEvaluation>{};
  final _explanations = <_Address, String>{};
  final _factors = <(_Scale, String, String), _Factor>{};
  final _ballots = <GameGraphOutputRef, Map<String, GamePackValue>>{};
  final _forming = <_Address>{};
  String _trial = '';
  int _remaining = 150000;

  GamePackScope? resolveScope(GamePackScope scope, GamePackGrain? grain) {
    if (scope.event != event)
      throw ArgumentError('Wrong event for GamePack analysis.');
    final supplied = _enrich(scope);
    return grain == null ? supplied : _project(supplied, grain);
  }

  List<GamePackScope> contexts(
    GamePackGrain grain, {
    bool includeUnscouted = true,
  }) => List.unmodifiable(
    _rows(GamePackScope(event: event), grain, scheduleRows: includeUnscouted),
  );

  Iterable<GamePackValue> reportsFor(String form) =>
      _reports.where((report) => report.atPath('form').data == form);

  _Address _address(GameGraphOutputRef ref, GamePackScope scope) =>
      (ref, scope.match, scope.team, scope.alliance, scope.station, _trial);

  GamePackNodePreview previewNode(
    String calculation,
    String node,
    GamePackScope scope,
  ) {
    final ref = (graph: calculation, output: node);
    final value = evaluate(ref, scope: scope).result;
    final key = resolveScope(scope, analysis.resultInfo(ref).grain);
    return (
      value: value,
      explanation: key == null ? null : _explanations[_address(ref, key)],
    );
  }

  GameGraphEvaluation evaluate(GameGraphOutputRef ref, {GamePackScope? scope}) {
    final context = scope ?? GamePackScope(event: event);
    final key = resolveScope(context, analysis.resultInfo(ref).grain);
    if (key == null)
      return GameGraphEvaluation(GamePackValue.missing, const {});
    final identity = _address(ref, key);
    final cache = _trial.isEmpty ? _values : _trialValues;
    if (cache[identity] case final value?) return value;
    final outer = _forming.isEmpty;
    if (outer) _remaining = 150000;
    _spend();
    if (!_forming.add(identity))
      throw FormatException('Calculation cycle at ${ref.output}.');
    try {
      final value = ref.graph == gamePackFieldNamespace
          ? _resolve(ref.output, key)
          : switch (analysis._node(ref)) {
              GamePackInputNode(:final field) => _value(
                gamePackFieldRef(field!),
                key,
              ),
              final GamePackStepNode step => _calculate(
                _Step(ref.graph, step),
                key,
              ),
            };
      return cache[identity] = GameGraphEvaluation(value, const {});
    } finally {
      _forming.remove(identity);
      if (outer) _trialValues.clear();
    }
  }

  void _spend() {
    if (--_remaining < 0)
      throw const GameGraphLimitExceeded(
        'The calculation exceeded its work limit.',
      );
  }

  void _explain(_Step recipe, GamePackScope scope, String detail) {
    if (trace && _trial.isEmpty) {
      _explanations[_address((
            graph: recipe.owner,
            output: recipe.node.id,
          ), scope)] =
          detail;
    }
  }

  GamePackScope _enrich(GamePackScope scope) {
    final slot = _slots[scope.match]?[scope.team];
    final alliance = slot?.alliance ?? scope.alliance;
    final station = slot?.station ?? scope.station;
    if (alliance == scope.alliance && station == scope.station) return scope;
    return GamePackScope(
      event: event,
      match: scope.match,
      team: scope.team,
      alliance: alliance,
      station: station,
    );
  }

  GamePackScope? _project(GamePackScope scope, GamePackGrain grain) =>
      switch (grain) {
        _event => GamePackScope(event: event),
        _team when scope.team != null => GamePackScope(
          event: event,
          team: scope.team,
        ),
        _match when scope.match != null => GamePackScope(
          event: event,
          match: scope.match,
        ),
        _allianceMatch when scope.match != null && scope.alliance != null =>
          GamePackScope(
            event: event,
            match: scope.match,
            alliance: scope.alliance,
          ),
        _teamMatch when scope.match != null && scope.team != null => scope,
        _ => null,
      };

  GamePackValue _resolve(String id, GamePackScope scope) {
    if (_matchFields.containsKey(id)) return _metadata(id, scope);
    if (analysis._scouted[id] case (final form, final field, _)) {
      final report = _report(scope, form);
      return report.atPath('answers.${field.id}');
    }
    if (analysis._tba[id] case final field?) return _mapped(field, scope);
    return _value((
      graph: id,
      output: analysis.calculationById(id)!.result,
    ), scope);
  }

  GamePackValue _metadata(String id, GamePackScope scope) {
    final payload = _archive[scope.match]?.atPath('payload');
    final schedule = _schedule[scope.match];
    GamePackValue info(String path) {
      final official = payload?.atPath(path) ?? GamePackValue.missing;
      return official.isKnown ? official : schedule?.atPath(path) ?? official;
    }

    return switch (id) {
      'team_key' => _optional(scope.team),
      'match_id' => _optional(scope.match),
      'station' => _optional(scope.station),
      'alliance' => _optional(scope.alliance),
      'report_id' => _matchReport(scope).atPath('id'),
      'match_level' => info('comp_level'),
      'official_score' => _nonnegativeScore(
        info('alliances.${scope.alliance}.score'),
      ),
      'match_label' => _matchLabel(scope.match!, info),
      _ => GamePackValue.missing,
    };
  }

  GamePackValue _matchLabel(String key, GamePackValue Function(String) info) {
    final level = info('comp_level');
    final number = info('match_number');
    final set = info('set_number');
    if (!number.isKnown) return GamePackValue.of(key);
    final label = level.data == 'qm'
        ? '${number.data}'
        : '${level.data ?? ''} ${set.data ?? ''} ${number.data}'.trim();
    return _derived(label, [level, number, set]);
  }

  GamePackValue _mapped(GamePackTbaField field, GamePackScope scope) {
    final payload = _archive[scope.match]?.atPath('payload');
    if (payload == null) return GamePackValue.missing;
    final values = <GamePackValue>[];
    for (final path in field.paths) {
      var resolved = path;
      if (resolved.contains('{alliance}')) {
        if (scope.alliance == null) continue;
        resolved = resolved.replaceAll('{alliance}', scope.alliance!);
      }
      if (resolved.contains('{robot}') ||
          resolved.contains('{slot}') ||
          resolved.contains('{position}')) {
        if (scope.station == null || scope.station! < 0 || scope.station! >= 6)
          continue;
        final station = scope.station! % 3;
        resolved = resolved
            .replaceAll('{robot}', 'robot${station + 1}')
            .replaceAll('{position}', '${station + 1}')
            .replaceAll('{slot}', '$station');
      }
      var value = payload.atPath(resolved);
      if (value.data case final String text when field.numericText) {
        final parsed = field.type == _integer
            ? int.tryParse(text.trim())
            : num.tryParse(text.trim());
        value = _derived(parsed, [value]);
      }
      values.add(value);
      if (value.isKnown && field.type.acceptsValue(value)) {
        return value.withEvidence(values.expand((item) => item.allEvidence));
      }
    }
    return _absent(values);
  }

  GamePackValue _report(GamePackScope scope, GamePackForm form) =>
      _reportCache.putIfAbsent((
        form.id,
        scope.match,
        scope.team,
        scope.alliance,
      ), () => _selectReport(scope, form));

  GamePackValue _selectReport(GamePackScope scope, GamePackForm form) {
    final rows = scope.match == null
        ? _byTeam[scope.team]
        : _byMatch[scope.match];
    GamePackValue? selected;
    final latest =
        analysis.reportChoices[form.id] != GamePackReportChoice.earliest;
    for (final row in rows ?? const <GamePackValue>[]) {
      if (row.atPath('form').data != form.id) continue;
      if (scope.team != null && row.atPath('team').data != scope.team) continue;
      if (scope.team == null &&
          scope.alliance != null &&
          row.atPath('alliance').data != scope.alliance)
        continue;
      final order = selected == null ? 0 : _timeOrder(row, selected);
      if (selected == null || (latest ? order > 0 : order < 0)) selected = row;
    }
    return selected ?? GamePackValue.missing;
  }

  GamePackValue _matchReport(GamePackScope scope) {
    final form = analysis._forms.values
        .where((form) => form.kind == GamePackFormKind.match)
        .firstOrNull;
    return form == null ? GamePackValue.missing : _report(scope, form);
  }

  List<GamePackScope> _rows(
    GamePackScope scope,
    GamePackGrain grain, {
    required bool scheduleRows,
    GamePackForm? form,
  }) => _rowCache.putIfAbsent(
    (grain, scope.match, scope.team, scope.alliance, scheduleRows, form?.id),
    () => _collectRows(
      scope,
      grain,
      scheduleRows: scheduleRows,
      form: form,
    ).toList(),
  );

  Iterable<GamePackScope> _collectRows(
    GamePackScope scope,
    GamePackGrain grain, {
    required bool scheduleRows,
    GamePackForm? form,
  }) sync* {
    if (grain == _event) {
      yield GamePackScope(event: event);
      return;
    }
    if (grain == _team && scope.team != null) {
      yield GamePackScope(event: event, team: scope.team);
      return;
    }
    if (grain == _team) {
      final teams = {
        ..._byTeam.keys,
        if (scheduleRows)
          for (final slots in _slots.values) ...slots.keys,
      };
      final order = teams.toList()..sort();
      for (final team in order) {
        yield GamePackScope(event: event, team: team);
      }
      return;
    }

    final matches = scope.match == null ? _orderedMatches : [scope.match!];
    for (final match in matches) {
      final reports = _byMatch[match] ?? const <GamePackValue>[];
      final relevant = reports.where((row) {
        if (form != null) return row.atPath('form').data == form.id;
        final kind = row.atPath('kind').data;
        return grain == _teamMatch
            ? kind == 'match'
            : kind == 'match' || kind == 'strategy';
      });
      if (!scheduleRows && relevant.isEmpty) continue;
      if (grain == _match) {
        yield GamePackScope(event: event, match: match);
        continue;
      }
      if (grain == _allianceMatch) {
        final sides =
            scheduleRows
                  ? const ['red', 'blue']
                  : [
                      ...relevant
                          .map((row) => row.atPath('alliance').data)
                          .whereType<String>()
                          .toSet(),
                    ]
              ..sort();
        for (final side in sides) {
          if (scope.alliance == null || scope.alliance == side) {
            yield GamePackScope(event: event, match: match, alliance: side);
          }
        }
        continue;
      }
      final teams = scheduleRows
          ? {
              ...?_slots[match]?.keys,
              ...relevant
                  .map((row) => row.atPath('team').data)
                  .whereType<String>(),
            }
          : relevant
                .map((row) => row.atPath('team').data)
                .whereType<String>()
                .toSet();
      final ordered = teams.toList()
        ..sort((left, right) {
          final a = _slots[match]?[left]?.station ?? 8;
          final b = _slots[match]?[right]?.station ?? 8;
          return a == b ? left.compareTo(right) : a.compareTo(b);
        });
      for (final team in ordered) {
        if (scope.team != null && scope.team != team) continue;
        final row = _enrich(
          GamePackScope(event: event, match: match, team: team),
        );
        if (scope.alliance == null || scope.alliance == row.alliance) yield row;
      }
    }
  }

  int _matchOrder(String a, String b) {
    GamePackValue payload(String key) =>
        _archive[key]?.atPath('payload') ?? GamePackValue.missing;
    Object? metadata(String key, String path) =>
        payload(key).atPath(path).data ?? _schedule[key]?.atPath(path).data;
    num? numeric(Object? value) => switch (value) {
      final num number => number,
      final String text => num.tryParse(text),
      _ => null,
    };
    num? time(String key) => numeric(metadata(key, 'time'));
    final at = time(a);
    final bt = time(b);
    if (at != null || bt != null) {
      if (at == null) return 1;
      if (bt == null) return -1;
      final byTime = at.compareTo(bt);
      if (byTime != 0) return byTime;
    }
    int number(String key, String part, [int fallback = 0]) =>
        numeric(metadata(key, part))?.toInt() ?? fallback;
    String level(String key) => metadata(key, 'comp_level')?.toString() ?? '';
    const levels = ['pm', 'qm', 'ef', 'qf', 'sf', 'f'];
    var order = levels.indexOf(level(a)).compareTo(levels.indexOf(level(b)));
    if (order != 0) return order;
    order = number(a, 'set_number').compareTo(number(b, 'set_number'));
    if (order != 0) return order;
    int suffix(String name) =>
        int.tryParse(RegExp(r'\d+$').stringMatch(name) ?? '') ?? 0;
    order = number(
      a,
      'match_number',
      suffix(a),
    ).compareTo(number(b, 'match_number', suffix(b)));
    return order == 0 ? a.compareTo(b) : order;
  }

  GamePackValue _value(GameGraphOutputRef ref, GamePackScope scope) =>
      evaluate(ref, scope: scope).result;

  GamePackValue _calculate(_Step recipe, GamePackScope scope) {
    final operation = recipe.operation;
    GamePackValue input(String id) => _value(recipe.inputs[id]!, scope);
    if (operation.reducesRows || operation == GamePackRecipe.rows) {
      final main = recipe.inputs.values.first;
      final grain = recipe.node.rowGrain ?? analysis.resultInfo(main).grain!;
      final source = analysis._sourceRef(main);
      final selectedForm =
          operation.reducesRows && source.graph == gamePackFieldNamespace
          ? analysis._scouted[source.output]?.$1
          : null;
      final rows = _rows(
        scope,
        grain,
        scheduleRows: recipe.node.scheduleRows,
        form: selectedForm,
      );
      if (operation == GamePackRecipe.rows) {
        return GamePackValue.list(
          rows.map(
            (row) => GamePackValue.record(
              recipe.inputs.map((key, ref) => MapEntry(key, _value(ref, row))),
            ),
          ),
        );
      }
      final data = rows
          .map((row) => _value(recipe.inputs['value']!, row))
          .toList();
      return _reduce(recipe, data, scope, grain);
    }
    switch (operation) {
      case GamePackRecipe.latestNote:
        return _latestNote(recipe, scope);
      case GamePackRecipe.ballotRank || GamePackRecipe.ballotScore:
        return _ballot(recipe, scope);
      case GamePackRecipe.scale:
        return _scale(recipe, scope);
      case GamePackRecipe.compare:
        return _compare(recipe, scope);
      case GamePackRecipe.flagged:
        return GamePackValue.list(
          _list(input('value'))
              .where((row) => row.atPath('flagged').data == true),
        ).withEvidence(input('value').evidence);
      case GamePackRecipe.countRows:
        final value = input('value');
        return value.isKnown ? _derived(_list(value).length, [value]) : value;
      case GamePackRecipe.countLabel:
        final value = input('value');
        return value.isKnown
            ? _derived(
                '${value.data} ${value.data == 1 ? recipe.node.singular : recipe.node.plural}',
                [value],
              )
            : value;
      case GamePackRecipe.excludeValue:
        final value = input('value');
        return value.isKnown && value.data == recipe.node.comparisonValue
            ? GamePackValue.missing.withEvidence(value.allEvidence)
            : value;
      case GamePackRecipe.condition:
        final value = input('value');
        if (!value.isKnown &&
            recipe.node.condition != GamePackCondition.provided &&
            !recipe.node.missingAsZero)
          return value;
        final accepted = switch (recipe.node.condition) {
          GamePackCondition.equals =>
            value.isKnown && value.data == recipe.node.comparisonValue,
          GamePackCondition.different =>
            value.isKnown && value.data != recipe.node.comparisonValue,
          GamePackCondition.positive =>
            value.data is num && (value.data as num) > 0,
          GamePackCondition.provided => value.isKnown,
        };
        return _derived(accepted, [value]);
      case GamePackRecipe.text:
        final value = input('value');
        return value.isKnown
            ? _derived(
                _list(value)
                    .map((item) => item.data)
                    .whereType<String>()
                    .join(', '),
                [value],
              )
            : value;
      case GamePackRecipe.constant:
        return GamePackValue.of(recipe.node.comparisonValue);
      case GamePackRecipe.fallback:
        final value = input('value');
        return value.isKnown
            ? value
            : input('fallback').withEvidence(value.allEvidence);
      case GamePackRecipe.choose:
        final condition = input('condition');
        return condition.isKnown
            ? input(condition.data == true ? 'then' : 'else')
                  .withEvidence(condition.allEvidence)
            : condition;
      case GamePackRecipe.not:
        final value = input('value');
        return value.isKnown ? _derived(value.data != true, [value]) : value;
      case GamePackRecipe.any || GamePackRecipe.all:
        final values = recipe.inputs.values
            .map((ref) => _value(ref, scope))
            .toList();
        final any = operation == GamePackRecipe.any;
        if (values.any((value) => value.data == any))
          return _derived(any, values);
        final absent = values.where((value) => !value.isKnown);
        if (absent.isEmpty) return _derived(!any, values);
        return any && recipe.node.missingAsZero
            ? _derived(false, values)
            : _absent(absent);
      case GamePackRecipe.add ||
          GamePackRecipe.meanOf ||
          GamePackRecipe.multiply:
        final values = recipe.inputs.values
            .map((ref) => _value(ref, scope))
            .toList();
        final numbers = values.map((value) => value.data).whereType<num>();
        if (numbers.isEmpty ||
            operation != GamePackRecipe.meanOf &&
                !recipe.node.missingAsZero &&
                numbers.length != values.length) {
          return _absent(values);
        }
        final result = switch (operation) {
          GamePackRecipe.multiply => values.fold<num>(
            1,
            (product, value) => product * _numberOf(value),
          ),
          GamePackRecipe.meanOf => _mean(numbers),
          _ => _sum(numbers),
        };
        return _derived(result, values);
      case GamePackRecipe.subtract ||
          GamePackRecipe.divide ||
          GamePackRecipe.less:
        final a = input('left');
        final b = input('right');
        if (!a.isKnown || !b.isKnown) return _absent([a, b]);
        final left = _numberOf(a);
        final right = _numberOf(b);
        final result = switch (operation) {
          GamePackRecipe.subtract => left - right,
          GamePackRecipe.less => left < right,
          _ => right == 0 ? null : left / right,
        };
        return _derived(result, [a, b]);
      case GamePackRecipe.empirical:
        final value = input('value');
        final items = _list(value).where((item) => item.isKnown).toList();
        return items.isEmpty
            ? _absent([value])
            : _derived(GamePackDistribution(items), [value]);
      case GamePackRecipe.bernoulli:
        final value = input('value');
        if (!value.isKnown) return value;
        final chance = _numberOf(value).toDouble();
        if (chance < 0 || chance > 1) return _derived(null, [value]);
        return _derived(
          GamePackDistribution(
            [GamePackValue.of(false), GamePackValue.of(true)],
            weights: [1 - chance, chance],
          ),
          [value],
        );
      case GamePackRecipe.sample:
        final value = input('value');
        if (value.data is! GamePackDistribution) return value;
        return _draw(
          value.data as GamePackDistribution,
          recipe,
          scope,
        ).withEvidence(value.allEvidence);
      case GamePackRecipe.simulate:
        final original = _trial;
        try {
          final values = <GamePackValue>[];
          for (var i = 0; i < recipe.node.trials; i++) {
            _spend();
            _trial = '$original/${recipe.owner}.${recipe.node.id}.$i';
            values.add(input('value'));
          }
          _explainTrials(recipe, scope, original, values.length);
          return GamePackValue.list(values);
        } finally {
          _trial = original;
        }
      case GamePackRecipe.quantile:
        final value = input('value');
        final numbers = _list(
          value,
        ).map((item) => item.data).whereType<num>().toList()..sort();
        if (numbers.isEmpty) return _absent([value]);
        final index =
            (numbers.length - 1) * (recipe.node.comparisonValue as num);
        final low = index.floor();
        final high = index.ceil();
        return _derived(
          numbers[low] + (numbers[high] - numbers[low]) * (index - low),
          [value],
        );
      default:
        throw StateError('Unsupported recipe ${operation.name}.');
    }
  }

  void _explainTrials(
    _Step recipe,
    GamePackScope scope,
    String original,
    int count,
  ) {
    _trial = original;
    _explain(recipe, scope, '$count trials · seed $seed');
  }

  GamePackValue _draw(
    GamePackDistribution dist,
    _Step recipe,
    GamePackScope scope,
  ) {
    // Modular arithmetic stays exact in browsers and native builds.
    var state = seed % 2147483646 + 1;
    final key =
        '${recipe.owner}.${recipe.node.id}.${scope.match}.${scope.team}.${scope.alliance}.$_trial';
    for (final unit in key.codeUnits) {
      state = (state * 48271 + unit) % 2147483647;
    }
    for (var i = 0; i < 3; i++) {
      state = (state * 48271) % 2147483647;
    }
    final point = state / 2147483647;
    final weights = dist.weights;
    if (weights == null)
      return dist.values[(point * dist.values.length).floor()];
    final total = _sum(weights);
    var target = point * total;
    for (final (index, weight) in weights.indexed) {
      target -= weight;
      if (target < 0) return dist.values[index];
    }
    return dist.values.last;
  }

  GamePackValue _reduce(
    _Step recipe,
    List<GamePackValue> values,
    GamePackScope scope,
    GamePackGrain rowScope,
  ) {
    final operation = recipe.operation;
    if (operation == GamePackRecipe.series) return GamePackValue.list(values);
    final known = values
        .where(
          (value) =>
              value.isKnown &&
              (!recipe.node.positiveOnly ||
                  value.data is num && (value.data as num) > 0),
        )
        .toList();
    if (operation == GamePackRecipe.count)
      return _derived(known.length, values);
    // Missing values may add zeros. Known nonpositive values excluded by the
    // filter never increase the denominator.
    final count =
        known.length +
        (recipe.node.missingAsZero && !recipe.node.positiveOnly
            ? values.where((value) => !value.isKnown).length
            : 0);
    final unit = switch (rowScope) {
      _teamMatch ||
      _allianceMatch ||
      _match => count == 1 ? 'match' : 'matches',
      _team => count == 1 ? 'team' : 'teams',
      _ => count == 1 ? 'value' : 'values',
    };
    if (trace) {
      final sample = known
          .take(4)
          .map((value) => _readable(value.data))
          .join(', ');
      _explain(
        recipe,
        scope,
        '$count $unit used${sample.isEmpty ? '' : ' · $sample${known.length > 4 ? '…' : ''}'}',
      );
    }
    if (count == 0) return _absent(values);
    if (operation == GamePackRecipe.rate) {
      return _derived(
        100 * known.where((value) => value.data == true).length / count,
        values,
      );
    }
    if (operation == GamePackRecipe.mostCommon) {
      final counts = <Object?, (int, GamePackValue)>{};
      for (final value in known) {
        final key = value.data;
        counts[key] = ((counts[key]?.$1 ?? 0) + 1, value);
      }
      final ranked = counts.values.toList()
        ..sort((a, b) => b.$1.compareTo(a.$1));
      return ranked.isEmpty
          ? _absent(values)
          : ranked.first.$2.withEvidence(
              values.expand((value) => value.allEvidence),
            );
    }
    final total = _sum(known.map((value) => value.data).whereType<num>());
    return _derived(
      operation == GamePackRecipe.average ? total / count : total,
      values,
    );
  }

  GamePackValue _latestNote(_Step recipe, GamePackScope scope) {
    final reports = [...?_byTeam[scope.team]]..sort((a, b) => _timeOrder(b, a));
    for (final report in reports) {
      for (final ref in recipe.inputs.values) {
        final (form, field, _) =
            analysis._scouted[analysis._sourceRef(ref).output]!;
        if (report.atPath('form').data != form.id) continue;
        final answer = report.atPath('answers.${field.id}');
        if (answer.data case final String text when text.trim().isNotEmpty)
          return answer;
      }
    }
    return GamePackValue.missing;
  }

  GamePackValue _scale(_Step recipe, GamePackScope scope) {
    final keys = (
      scouted: analysis._sourceRef(recipe.inputs['scouted']!),
      official: analysis._sourceRef(recipe.inputs['official']!),
      extra: recipe.inputs['extra'] == null
          ? null
          : analysis._sourceRef(recipe.inputs['extra']!),
      requirePositive: recipe.node.requirePositiveOfficial,
    );
    final raw = _value(keys.scouted, scope);
    final alliance = scope.alliance;
    if (alliance == null) {
      _explain(recipe, scope, 'Alliance unavailable for this team');
      return recipe.node.fallbackToScouted
          ? raw
          : GamePackValue.missing.withEvidence(raw.allEvidence);
    }
    _Factor calculateFactor() {
      final side = GamePackScope(
        event: event,
        match: scope.match,
        alliance: alliance,
      );
      final official = _value(keys.official, side);
      final reports = [
        for (final team in _rows(side, _teamMatch, scheduleRows: false))
          _value(keys.scouted, team),
        if (keys.extra case final extra?) _value(extra, side),
      ];
      final total = _sum(reports.map(_numberOf));
      final counted = official.data as num?;
      final valid =
          counted != null &&
          counted >= 0 &&
          (!keys.requirePositive || counted > 0) &&
          total > 0;
      return (
        value: valid
            ? _derived(counted / total, [official, ...reports])
            : _absent([official, ...reports]),
        official: counted,
        total: total,
      );
    }

    final factor = _trial.isEmpty
        ? _factors.putIfAbsent((keys, scope.match!, alliance), calculateFactor)
        : calculateFactor();
    if (!raw.isKnown) {
      _explain(recipe, scope, 'Scouted team value unavailable');
      return raw;
    }
    if (factor.value.isKnown) {
      final result = _derived(_numberOf(raw) * _numberOf(factor.value), [
        raw,
        factor.value,
      ]);
      _explain(
        recipe,
        scope,
        '${_readable(raw.data)} × (${_readable(factor.official)} official ÷ ${_readable(factor.total)} reported) = ${_readable(result.data)}',
      );
      return result;
    }
    _explain(
      recipe,
      scope,
      recipe.node.fallbackToScouted
          ? 'Scaling unavailable · using ${_readable(raw.data)} scouted'
          : 'Scaling unavailable for this match',
    );
    return (recipe.node.fallbackToScouted ? raw : factor.value).withEvidence([
      ...raw.allEvidence,
      ...factor.value.allEvidence,
    ]);
  }

  GamePackValue _compare(_Step recipe, GamePackScope scope) {
    final results = <GamePackValue>[];
    for (final side in _rows(scope, _allianceMatch, scheduleRows: false)) {
      final level = _metadata('match_level', side);
      if (recipe.node.qualificationsOnly && level.isKnown && level.data != 'qm')
        continue;
      final official = _value(recipe.inputs['official']!, side);
      if (_numberOf(official) <= 0) continue;
      final teams = _rows(side, _teamMatch, scheduleRows: false).toList();
      if (teams.length < recipe.node.minimumReports) continue;
      final values = [
        for (final team in teams) ...[
          _value(recipe.inputs['scouted']!, team),
          if (recipe.inputs['scouted_other'] case final other?)
            _value(other, team),
        ],
      ];
      final total = _sum(values.map(_numberOf));
      final relative =
          (total - _numberOf(official)).abs() / _numberOf(official);
      final flagged = relative > recipe.node.threshold;
      if (recipe.node.flaggedOnly && !flagged) continue;
      results.add(
        GamePackValue.of({
          'match': side.match,
          'alliance': side.alliance,
          'scouted': total,
          'official': official,
          'deviation_percent': relative * 100,
          'flagged': flagged,
        }).withEvidence(values.expand((value) => value.allEvidence)),
      );
    }
    return GamePackValue.list(results);
  }

  GamePackValue _ballot(_Step recipe, GamePackScope scope) {
    final ref = analysis._sourceRef(recipe.inputs['value']!);
    Map<String, GamePackValue> calculateBallots() {
      final scores = <String, List<GamePackValue>>{};
      for (final side in _rows(
        GamePackScope(event: event),
        _allianceMatch,
        scheduleRows: false,
      )) {
        final ballot = _value(ref, side);
        final teams = _list(ballot);
        for (final (index, team) in teams.indexed) {
          if (team.data case final String key) {
            scores
                .putIfAbsent(key, () => [])
                .add(_derived(teams.length - index, [ballot]));
          }
        }
      }
      return scores.map(
        (key, values) =>
            MapEntry(key, _derived(_mean(values.map(_numberOf)), values)),
      );
    }

    final averages = _trial.isEmpty
        ? _ballots.putIfAbsent(ref, calculateBallots)
        : calculateBallots();
    final own = averages[scope.team];
    if (own == null) return GamePackValue.missing;
    final all = averages.values.toList();
    if (recipe.operation == GamePackRecipe.ballotRank) {
      final order = averages.keys.toList()
        ..sort((a, b) {
          final score = _numberOf(averages[b]!)
              .compareTo(_numberOf(averages[a]!));
          return score == 0 ? a.compareTo(b) : score;
        });
      return _derived(order.indexOf(scope.team!) + 1, all);
    }
    final mean = _mean(all.map(_numberOf));
    final deviation = sqrt(
      _mean(
        all.map((entry) {
          final distance = _numberOf(entry) - mean;
          return distance * distance;
        }),
      ),
    );
    return _derived(
      (_numberOf(own) - mean) / (deviation == 0 ? 1 : deviation),
      all,
    );
  }
}

List<GamePackValue> _list(GamePackValue? value) =>
    value?.data is List<GamePackValue>
    ? value!.data as List<GamePackValue>
    : const [];
GamePackValue _optional(Object? value) =>
    value == null ? GamePackValue.missing : GamePackValue.of(value);
num _numberOf(GamePackValue value) => (value.data as num?) ?? 0;
num _sum(Iterable<num> numbers) =>
    numbers.fold(0, (total, value) => total + value);
double _mean(Iterable<num> numbers) => _sum(numbers) / numbers.length;
GamePackValue _derived(Object? value, Iterable<GamePackValue> evidence) =>
    GamePackValue.of(value)
        .withEvidence(evidence.expand((value) => value.allEvidence));
GamePackValue _absent(Iterable<GamePackValue> values) {
  final state =
      values.any(
        (value) => value.state == GamePackValueState.unknown || value.isKnown,
      )
      ? GamePackValue.unknown
      : values.any((value) => value.state == GamePackValueState.notApplicable)
      ? GamePackValue.notApplicable
      : GamePackValue.missing;
  return state.withEvidence(values.expand((value) => value.allEvidence));
}

GamePackValue _nonnegativeScore(GamePackValue score) =>
    score.data is num && (score.data as num) >= 0
    ? score
    : GamePackValue.missing.withEvidence(score.allEvidence);

int _timeOrder(GamePackValue a, GamePackValue b) {
  final chronological = _numberOf(a.atPath('captured_at'))
      .compareTo(_numberOf(b.atPath('captured_at')));
  return chronological == 0
      ? '${a.atPath('id').data}'.compareTo('${b.atPath('id').data}')
      : chronological;
}

String _readable(Object? value) => switch (value) {
  final num number when number == number.roundToDouble() =>
    number.toStringAsFixed(0),
  final num number =>
    number.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), ''),
  true => 'Yes',
  false => 'No',
  null => '—',
  _ => value.toString(),
};
