import 'analysis.dart';
import 'forms.dart';
import 'graph.dart';
import 'program.dart';
import 'sources.dart';
import 'team_cards.dart';
import 'value.dart';
import 'views.dart';

class GamePackResults {
  GamePackResults({
    List<GamePackTeamCardLayout> layouts = const [],
    List<GamePackTeamSort> sorts = const [],
    List<GamePackTeamFilter> filters = const [],
    List<GamePackWorksheet> sheets = const [],
  }) : layouts = List.unmodifiable(layouts),
       sorts = List.unmodifiable(sorts),
       filters = List.unmodifiable(filters),
       sheets = List.unmodifiable(sheets);

  final List<GamePackTeamCardLayout> layouts;
  final List<GamePackTeamSort> sorts;
  final List<GamePackTeamFilter> filters;
  final List<GamePackWorksheet> sheets;

  factory GamePackResults.fromJson(Map<String, dynamic> json) =>
      GamePackResults(
        layouts: _read(json['layouts'], GamePackTeamCardLayout.fromJson),
        sorts: _read(json['sorts'], GamePackTeamSort.fromJson),
        filters: _read(json['filters'], GamePackTeamFilter.fromJson),
        sheets: _read(json['sheets'], GamePackWorksheet.fromJson),
      );

  Map<String, Object> toJson() => {
    'layouts': layouts.map((item) => item.toJson()).toList(),
    'sorts': sorts.map((item) => item.toJson()).toList(),
    'filters': filters.map((item) => item.toJson()).toList(),
    'sheets': sheets.map((item) => item.toJson()).toList(),
  };

  void validate(GamePackAnalysis analysis, List<GamePackForm> forms) {
    final kinds = <GamePackTeamCardKind>{};
    for (final layout in layouts) {
      if (!kinds.add(layout.kind))
        throw FormatException('Duplicate ${layout.kind.label} layout.');
      layout.validate(analysis);
    }
    final ids = <String>{};
    void check(String id, String label) {
      validateGamePackIdentifier(id);
      validateGamePackLabel(label);
      if (!ids.add(id))
        throw FormatException('Duplicate Results identifier $id.');
    }

    for (final sort in sorts) {
      check(sort.id, sort.label);
      sort.validate(analysis);
    }
    for (final filter in filters) {
      check(filter.id, filter.label);
      filter.validate(analysis);
    }
    final names = <String>{};
    if (sheets.length > 32)
      throw const FormatException('A workbook supports up to 32 sheets.');
    for (final sheet in sheets) {
      check(sheet.id, sheet.name);
      if (!names.add(sheet.name.toLowerCase()))
        throw FormatException('Duplicate sheet name ${sheet.name}.');
      sheet.validate(analysis, forms);
    }
  }
}

class GamePackTeamSort {
  const GamePackTeamSort({
    required this.id,
    required this.label,
    required this.output,
    this.ascending = false,
  });

  final String id;
  final String label;
  final GameGraphOutputRef output;
  final bool ascending;

  factory GamePackTeamSort.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('list')) {
      throw const FormatException(
        'Team sorts are shared. Remove the list setting.',
      );
    }
    return GamePackTeamSort(
      id: json['id'] as String,
      label: json['label'] as String,
      output: readGamePackResult(json),
      ascending: json['ascending'] == true,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    ...writeGamePackResult(output),
    if (ascending) 'ascending': true,
  };

  void validate(GamePackAnalysis analysis) {
    final type = validateGamePackViewOutput(
      analysis,
      output,
      label,
      scope: GamePackGrain.team,
    );
    if (!GamePackCardMetric.supports(type))
      throw FormatException('$label needs a number, text, or yes/no field.');
  }
}

enum GamePackFilterTest {
  equals('Is'),
  notEquals('Isn’t'),
  atLeast('At least'),
  atMost('At most'),
  contains('Contains'),
  reported('Has a value'),
  missing('Has no value');

  const GamePackFilterTest(this.label);
  final String label;

  bool get needsValue => this != reported && this != missing;

  bool supports(GamePackType type) => switch (this) {
    atLeast || atMost => GamePackType.number.accepts(type),
    contains => type == GamePackType.text,
    equals || notEquals => GamePackCardMetric.supports(type),
    _ => true,
  };
}

class GamePackTeamFilter {
  const GamePackTeamFilter({
    required this.id,
    required this.label,
    required this.output,
    required this.test,
    this.value,
  });

  final String id;
  final String label;
  final GameGraphOutputRef output;
  final GamePackFilterTest test;
  final Object? value;

  factory GamePackTeamFilter.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('list')) {
      throw const FormatException(
        'Team filters are shared. Remove the list setting.',
      );
    }
    return GamePackTeamFilter(
      id: json['id'] as String,
      label: json['label'] as String,
      output: readGamePackResult(json),
      test: GamePackFilterTest.values.byName(json['test'] as String),
      value: json['value'],
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    ...writeGamePackResult(output),
    'test': test.name,
    if (value case final operand?) 'value': operand,
  };

  void validate(GamePackAnalysis analysis) {
    final type = validateGamePackViewOutput(
      analysis,
      output,
      label,
      scope: GamePackGrain.team,
    );
    if (!test.supports(type) ||
        test.needsValue &&
            (value == null || !type.acceptsValue(GamePackValue.of(value)))) {
      throw FormatException(
        'Choose a compatible condition and value for $label.',
      );
    }
  }

  bool matches(GamePackValue actual) {
    if (test == GamePackFilterTest.reported) return actual.isKnown;
    if (test == GamePackFilterTest.missing) return !actual.isKnown;
    if (!actual.isKnown) return false;
    final raw = actual.data;
    return switch (test) {
      GamePackFilterTest.equals => raw == value,
      GamePackFilterTest.notEquals => raw != value,
      GamePackFilterTest.atLeast => raw is num && raw >= (value as num),
      GamePackFilterTest.atMost => raw is num && raw <= (value as num),
      GamePackFilterTest.contains =>
        raw is String &&
            raw.toLowerCase().contains((value as String).toLowerCase()),
      _ => false,
    };
  }
}

int compareGamePackTeamValues(
  GamePackValue left,
  GamePackValue right, {
  required bool ascending,
}) {
  if (left.isKnown != right.isKnown) return left.isKnown ? -1 : 1;
  final order = switch ((left.data, right.data)) {
    (final num a, final num b) => a.compareTo(b),
    (final String a, final String b) => a.toLowerCase().compareTo(
      b.toLowerCase(),
    ),
    (final bool a, final bool b) => (a ? 1 : 0).compareTo(b ? 1 : 0),
    _ => 0,
  };
  return ascending ? order : -order;
}

enum GamePackSheetRows {
  teams('Team Summary', 'One row per team'),
  matches('Match Results', 'One row per team in a match'),
  reports('Scouting Reports', 'One row per submission'),
  calculation('From a Calculation', 'Rows from a calculated table');

  const GamePackSheetRows(this.label, this.description);
  final String label;
  final String description;

  GamePackGrain? get scope => switch (this) {
    teams => GamePackGrain.team,
    matches => GamePackGrain.teamMatch,
    _ => null,
  };
}

enum GamePackColumnInfo {
  teamNumber('Team number'),
  teamName('Team name'),
  teamKey('Team key'),
  match('Match'),
  alliance('Alliance'),
  station('Station'),
  reportId('Report ID'),
  capturedAt('Captured at (UTC)'),
  scout('Scout ID');

  const GamePackColumnInfo(this.label);
  final String label;

  bool canUse(GamePackSheetRows rows, {GamePackFormKind? form}) =>
      switch (this) {
        teamNumber || teamName || teamKey =>
          rows != GamePackSheetRows.calculation &&
              (rows != GamePackSheetRows.reports ||
                  form != GamePackFormKind.strategy),
        match =>
          rows == GamePackSheetRows.matches ||
              rows == GamePackSheetRows.reports &&
                  [
                    GamePackFormKind.match,
                    GamePackFormKind.strategy,
                    GamePackFormKind.observation,
                  ].contains(form),
        alliance || station =>
          rows == GamePackSheetRows.matches ||
              rows == GamePackSheetRows.reports &&
                  [
                    GamePackFormKind.match,
                    GamePackFormKind.strategy,
                  ].contains(form),
        _ => rows == GamePackSheetRows.reports,
      };
}

class GamePackWorksheetColumn {
  const GamePackWorksheetColumn({
    required this.id,
    required this.heading,
    this.info,
    this.output,
    this.path,
  });

  final String id;
  final String heading;
  final GamePackColumnInfo? info;
  final GameGraphOutputRef? output;
  final String? path;

  factory GamePackWorksheetColumn.fromJson(Map<String, dynamic> json) =>
      GamePackWorksheetColumn(
        id: json['id'] as String,
        heading: json['heading'] as String,
        info: json['info'] == null
            ? null
            : GamePackColumnInfo.values.byName(json['info'] as String),
        output: json['result'] == null ? null : readGamePackResult(json),
        path: json['path'] as String?,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'heading': heading,
    if (info case final field?) 'info': field.name,
    if (output case final ref?) ...writeGamePackResult(ref),
    if (path case final field?) 'path': field,
  };
}

class GamePackWorksheet {
  GamePackWorksheet({
    required this.id,
    required this.name,
    required this.rows,
    required List<GamePackWorksheetColumn> columns,
    this.form,
    this.table,
    this.includeUnscouted = false,
  }) : columns = List.unmodifiable(columns);

  final String id;
  final String name;
  final GamePackSheetRows rows;
  final List<GamePackWorksheetColumn> columns;
  final String? form;
  final GameGraphOutputRef? table;
  final bool includeUnscouted;

  static bool validName(String name) =>
      name.isNotEmpty &&
      name.trim() == name &&
      name.length <= 31 &&
      !RegExp(r"[\[\]:*?/\\\x00-\x1f]").hasMatch(name) &&
      !name.startsWith("'") &&
      !name.endsWith("'") &&
      name.toLowerCase() != 'history';

  factory GamePackWorksheet.fromJson(Map<String, dynamic> json) =>
      GamePackWorksheet(
        id: json['id'] as String,
        name: json['name'] as String,
        rows: GamePackSheetRows.values.byName(json['rows'] as String),
        columns: _read(json['columns'], GamePackWorksheetColumn.fromJson),
        form: json['form'] as String?,
        table: json['table'] == null
            ? null
            : readGamePackResult(json, key: 'table'),
        includeUnscouted: json['includeUnscouted'] == true,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'rows': rows.name,
    'columns': columns.map((column) => column.toJson()).toList(),
    if (form case final form?) 'form': form,
    if (table case final ref?) ...writeGamePackResult(ref, key: 'table'),
    if (includeUnscouted) 'includeUnscouted': true,
  };

  static bool supportsTable(GamePackResultInfo info) =>
      info.grain == GamePackGrain.event &&
      info.type.kind == GamePackTypeKind.list &&
      info.type.element!.kind == GamePackTypeKind.record;

  void validate(GamePackAnalysis analysis, List<GamePackForm> forms) {
    if (!validName(name))
      throw FormatException(
        'Choose an Excel sheet name of 1–31 characters for $name.',
      );
    if (columns.isEmpty || columns.length > 256)
      throw FormatException('Add 1–256 columns to $name.');
    final selected = forms.where((item) => item.id == form).firstOrNull;
    if (rows == GamePackSheetRows.reports && selected == null)
      throw FormatException('$name needs a scouting form.');
    final tableInfo = table == null ? null : analysis.resultInfo(table!);
    if (rows == GamePackSheetRows.calculation &&
        (tableInfo == null || !supportsTable(tableInfo))) {
      throw FormatException(
        '$name needs an event calculation that returns a table.',
      );
    }
    final headings = <String>{};
    final ids = <String>{};
    for (final column in columns) {
      validateGamePackIdentifier(column.id);
      validateGamePackLabel(column.heading);
      if (!ids.add(column.id) || !headings.add(column.heading.toLowerCase())) {
        throw FormatException('Duplicate column ${column.heading} in $name.');
      }
      if ([column.info, column.output, column.path].nonNulls.length != 1) {
        throw FormatException('Choose a source for ${column.heading}.');
      }
      if (column.output case final ref?) {
        final scope = rows.scope;
        if (scope == null)
          throw FormatException('${column.heading} needs team or match rows.');
        validateGamePackViewOutput(analysis, ref, column.heading, scope: scope);
      } else if (column.path case final key?) {
        final allowed = switch (rows) {
          GamePackSheetRows.reports => selected!.controls.any(
            (control) => control.field == key,
          ),
          GamePackSheetRows.calculation => GamePackCardChart.columns(
            tableInfo!.type,
          ).containsKey(key),
          _ => false,
        };
        if (!allowed)
          throw FormatException(
            'Unknown column source for ${column.heading} in $name.',
          );
      } else if (!column.info!.canUse(rows, form: selected?.kind)) {
        throw FormatException(
          '${column.heading} is unavailable for this type of sheet.',
        );
      }
    }
  }

  Iterable<List<GamePackValue>> values(
    GamePackAnalysisSession session, {
    Map<String, String> teamNames = const {},
    Set<String> teams = const {},
    bool includeScout = false,
  }) sync* {
    bool includes(Object? team) =>
        teams.isEmpty || team == null || teams.contains(team);
    if (rows == GamePackSheetRows.reports) {
      for (final report in session.reportsFor(form!)) {
        if (!includes(report.atPath('team').data)) continue;
        yield [
          for (final column in columns)
            if (column.path case final field?)
              report.atPath('answers.$field')
            else
              _reportInfo(column.info!, report, teamNames, includeScout),
        ];
      }
      return;
    }
    if (rows == GamePackSheetRows.calculation) {
      final value = session.evaluate(table!).result;
      if (value.data case final List<GamePackValue> items) {
        for (final item in items) {
          final team = item.atPath('team').data ?? item.atPath('team_key').data;
          if (!includes(team)) continue;
          yield [for (final column in columns) item.atPath(column.path!)];
        }
      }
      return;
    }

    final scopes = rows == GamePackSheetRows.teams
        ? ({
            ...teamNames.keys,
            ...session.contexts(GamePackGrain.team).map((row) => row.team!),
          }.toList()..sort((a, b) => _number(a).compareTo(_number(b)))).map(
            (team) => GamePackScope(event: session.event, team: team),
          )
        : session.contexts(
            GamePackGrain.teamMatch,
            includeUnscouted: includeUnscouted,
          );
    for (final scope in scopes) {
      if (!includes(scope.team)) continue;
      yield [
        for (final column in columns)
          if (column.output case final ref?)
            _safeEvaluate(session, ref, scope)
          else
            _contextInfo(column.info!, session, scope, teamNames),
      ];
    }
  }
}

GamePackValue _safeEvaluate(
  GamePackAnalysisSession session,
  GameGraphOutputRef ref,
  GamePackScope scope,
) {
  try {
    return session.evaluate(ref, scope: scope).result;
  } on GameGraphLimitExceeded {
    return GamePackValue.unknown;
  }
}

int _number(String team) => int.tryParse(team.replaceFirst('frc', '')) ?? 0;
GamePackValue _teamNumber(Object? team) => team is String && _number(team) > 0
    ? GamePackValue.of(_number(team))
    : GamePackValue.missing;

GamePackValue _contextInfo(
  GamePackColumnInfo info,
  GamePackAnalysisSession session,
  GamePackScope scope,
  Map<String, String> names,
) => switch (info) {
  GamePackColumnInfo.teamNumber => _teamNumber(scope.team),
  GamePackColumnInfo.teamName => _optional(names[scope.team]),
  GamePackColumnInfo.teamKey => _optional(scope.team),
  GamePackColumnInfo.match =>
    session.evaluate(gamePackFieldRef('match_label'), scope: scope).result,
  GamePackColumnInfo.alliance => _optional(scope.alliance),
  GamePackColumnInfo.station => _station(scope.station),
  _ => GamePackValue.missing,
};

GamePackValue _reportInfo(
  GamePackColumnInfo info,
  GamePackValue report,
  Map<String, String> names,
  bool includeScout,
) => switch (info) {
  GamePackColumnInfo.teamNumber => _teamNumber(report.atPath('team').data),
  GamePackColumnInfo.teamName => _optional(names[report.atPath('team').data]),
  GamePackColumnInfo.teamKey => report.atPath('team'),
  GamePackColumnInfo.match => report.atPath('match'),
  GamePackColumnInfo.alliance => report.atPath('alliance'),
  GamePackColumnInfo.station => _station(report.atPath('station').data),
  GamePackColumnInfo.reportId => report.atPath('id'),
  GamePackColumnInfo.scout =>
    includeScout ? report.atPath('scout') : GamePackValue.missing,
  GamePackColumnInfo.capturedAt => switch (report.atPath('captured_at').data) {
    final int timestamp => GamePackValue.of(
      DateTime.fromMillisecondsSinceEpoch(
        timestamp,
        isUtc: true,
      ).toIso8601String(),
    ),
    _ => GamePackValue.missing,
  },
};

GamePackValue _station(Object? index) => index is int && index >= 0 && index < 6
    ? GamePackValue.of(index % 3 + 1)
    : GamePackValue.missing;

GamePackValue _optional(Object? value) =>
    value == null ? GamePackValue.missing : GamePackValue.of(value);

List<T> _read<T>(Object? data, T Function(Map<String, dynamic>) read) =>
    ((data as List?) ?? const [])
        .map((row) => read(row as Map<String, dynamic>))
        .toList();
