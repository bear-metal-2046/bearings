import 'package:core/core.dart';
import 'package:grove/grove.dart';

/// The same document shape used at publication, with references permitted to
/// be incomplete until the author runs validation.
class GamePackDesign {
  GamePackDesign({
    this.name = 'Untitled GamePack',
    this.season,
    this.fields = const [],
    List<GamePackForm> forms = const [],
    this.tbaFields = const [],
    this.calculations = const [],
    this.reportChoices = const {},
    GamePackResults? results,
  }) : forms = _withScoutForms(forms),
       results = results ?? GamePackResults();

  final String name;
  final int? season;
  final List<GamePackField> fields;
  final List<GamePackForm> forms;
  final List<GamePackTbaField> tbaFields;
  final List<GamePackCalculation> calculations;
  final Map<String, GamePackReportChoice> reportChoices;
  late final GamePackAnalysis catalog = GamePackAnalysis(
    fields: fields,
    forms: forms,
    tbaFields: tbaFields,
    calculations: calculations,
    reportChoices: reportChoices,
    validate: false,
  );
  Iterable<String> get resultIds => catalog.fieldRefs.map((ref) => ref.output);
  final GamePackResults results;
  List<GamePackTeamCardLayout> get teamCards => results.layouts;

  factory GamePackDesign.fromJson(Json json) {
    if (json['formatVersion'] != GamePackDefinition.formatVersion) {
      throw const FormatException(
        'This draft uses a different GamePack format.',
      );
    }
    return GamePackDesign(
      name: json['name'] as String? ?? 'Untitled GamePack',
      season: json['season'] as int?,
      fields: _read(json['fields'], GamePackField.fromJson),
      forms: _read(json['forms'], GamePackForm.fromJson),
      tbaFields: _read(json['tbaFields'], GamePackTbaField.fromJson),
      calculations: _read(json['calculations'], GamePackCalculation.fromJson),
      reportChoices:
          (json['reportChoices'] as Json? ?? const <String, dynamic>{}).map(
            (key, value) => MapEntry(
              key,
              GamePackReportChoice.values.byName(value as String),
            ),
          ),
      results: GamePackResults.fromJson(json['results'] as Json? ?? const {}),
    );
  }

  Json toJson() => {
    'formatVersion': GamePackDefinition.formatVersion,
    'name': name,
    if (season != null) 'season': season,
    'fields': fields.map((item) => item.toJson()).toList(),
    'forms': forms.map((item) => item.toJson()).toList(),
    'tbaFields': tbaFields.map((item) => item.toJson()).toList(),
    'calculations': calculations.map((item) => item.toJson()).toList(),
    if (reportChoices.isNotEmpty)
      'reportChoices': reportChoices.map(
        (key, value) => MapEntry(key, value.name),
      ),
    'results': results.toJson(),
  };

  late final configuredForms = List<GamePackForm>.unmodifiable(
    forms.where((form) => form.controls.isNotEmpty),
  );

  GamePackDefinition compile() => GamePackDefinition.typed(
    name: name,
    season: season,
    fields: fields,
    forms: configuredForms,
    tbaFields: tbaFields,
    calculations: calculations,
    reportChoices: {
      for (final form in configuredForms) form.id: ?reportChoices[form.id],
    },
    results: results,
  );

  late final fieldById = {for (final field in fields) field.id: field};

  late final questions = [
    for (final form in forms)
      for (final page in form.pages)
        for (final control in page.controls)
          if (fieldById[control.field] case final field?)
            (form: form, page: page, field: field, control: control),
  ];

  late final questionPaths = {
    for (final question in questions)
      gamePackScoutFieldId(
        question.form.id,
        question.field.id,
      ): '${question.form.label} › ${question.page.label} › ${question.field.label}',
  };

  Set<String> formRemovalDependencies(List<GamePackForm> remaining) {
    final kept = {
      for (final form in remaining)
        for (final control in form.controls)
          gamePackScoutFieldId(form.id, control.field),
    };
    final removed = {
      for (final question in questions)
        gamePackScoutFieldId(question.form.id, question.field.id),
    }.difference(kept);
    bool uses(String? id) =>
        id != null && removed.contains(gamePackRollupOf(id)?.field ?? id);
    final removedForms = configuredForms
        .map((form) => form.id)
        .toSet()
        .difference({
          for (final form in remaining)
            if (form.controls.isNotEmpty) form.id,
        });
    return {
      for (final question in questions)
        if (kept.contains(
              gamePackScoutFieldId(question.form.id, question.field.id),
            ) &&
            question.control.visibleWhen != null &&
            uses(
              gamePackScoutFieldId(
                question.form.id,
                question.control.visibleWhen!.field,
              ),
            ))
          '${question.form.label} › ${question.page.label} › ${question.field.label} (visibility)',
      for (final calculation in calculations)
        if (calculation.nodes.whereType<GamePackInputNode>().any(
          (node) => uses(node.field),
        ))
          'Metrics › ${calculation.label}',
      for (final layout in teamCards)
        for (final section in layout.sections)
          for (final block in section.blocks)
            if (block.metrics.any((metric) => uses(metric.output.output)) ||
                uses(block.chart?.output.output) ||
                uses(block.table?.output.output))
              '${layout.kind.label} › ${block.title ?? block.kind.label}',
      for (final sort in results.sorts)
        if (uses(sort.output.output)) 'Sorting & filters › ${sort.label}',
      for (final filter in results.filters)
        if (uses(filter.output.output)) 'Sorting & filters › ${filter.label}',
      for (final sheet in results.sheets)
        if (removedForms.contains(sheet.form) ||
            uses(sheet.table?.output) ||
            sheet.columns.any(
              (column) =>
                  uses(column.output?.output) ||
                  (sheet.form != null &&
                      column.path != null &&
                      uses(gamePackScoutFieldId(sheet.form!, column.path!))),
            ))
          'Export sheets › ${sheet.name}',
    };
  }

  GamePackDesign copyWith({
    String? name,
    int? Function()? season,
    List<GamePackField>? fields,
    List<GamePackForm>? forms,
    List<GamePackTbaField>? tbaFields,
    List<GamePackCalculation>? calculations,
    Map<String, GamePackReportChoice>? reportChoices,
    List<GamePackTeamSort>? sorts,
    List<GamePackTeamFilter>? filters,
    List<GamePackWorksheet>? sheets,
    List<GamePackTeamCardLayout>? teamCards,
  }) => GamePackDesign(
    name: name ?? this.name,
    season: season == null ? this.season : season(),
    fields: fields ?? this.fields,
    forms: forms ?? this.forms,
    tbaFields: tbaFields ?? this.tbaFields,
    calculations: calculations ?? this.calculations,
    reportChoices: reportChoices ?? this.reportChoices,
    results: GamePackResults(
      layouts: teamCards ?? this.teamCards,
      sorts: sorts ?? results.sorts,
      filters: filters ?? results.filters,
      sheets: sheets ?? results.sheets,
    ),
  );
}

List<GamePackForm> _withScoutForms(List<GamePackForm> existing) {
  final byKind = {for (final form in existing) form.kind: form};
  if (byKind.length != existing.length) {
    throw const FormatException(
      'A GamePack can have one form per scouting type.',
    );
  }
  final ids = existing.map((form) => form.id).toSet();
  if (ids.length != existing.length) {
    throw const FormatException('Each scouting form needs a unique ID.');
  }
  return List.unmodifiable([
    for (final kind in GamePackFormKind.values)
      if (byKind[kind] case final form? when form.pages.isNotEmpty)
        form
      else
        _starterForm(kind, ids, byKind[kind]),
  ]);
}

GamePackForm _starterForm(
  GamePackFormKind kind,
  Set<String> ids,
  GamePackForm? existing,
) {
  final id = existing?.id ?? availableId(kind.name, ids);
  ids.add(id);
  return GamePackForm(
    id: id,
    label: existing?.label ?? kind.label,
    kind: kind,
    pages: [
      if (kind == GamePackFormKind.match)
        GamePackFormPage.grid(
          id: 'page_1',
          label: 'Page 1',
          columns: 6,
          rows: 6,
          controls: const [],
        )
      else
        GamePackFormPage.scrolling(
          id: 'page_1',
          label: 'Page 1',
          sections: [
            GamePackSection.controls(
              id: 'questions',
              label: 'Questions',
              controls: const [],
            ),
          ],
        ),
    ],
  );
}

List<T> _read<T>(Object? value, T Function(Json) fromJson) =>
    (value as List<dynamic>? ?? const [])
        .map((item) => fromJson(item as Json))
        .toList();

String availableId(String stem, Iterable<String> used) {
  final ids = used.toSet();
  if (!ids.contains(stem)) return stem;
  var suffix = 2;
  while (ids.contains('${stem}_$suffix')) {
    suffix++;
  }
  return '${stem}_$suffix';
}

String gamePackIdForName(String name, Iterable<String> used, String fallback) {
  final stem = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^[^a-z]+|_+$'), '');
  return availableId(
    stem.isEmpty ? fallback : stem.substring(0, stem.length.clamp(0, 48)),
    used,
  );
}

String gamePackKeyLabel(String key) {
  final words = key
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match[1]} ${match[2]}',
      )
      .replaceAll('_', ' ');
  return words.isEmpty ? key : '${words[0].toUpperCase()}${words.substring(1)}';
}

List<T> replaceAt<T>(List<T> original, int index, T replacement) =>
    [...original]..[index] = replacement;

String gamePackResultLabel(
  GameGraphOutputRef ref, [
  GamePackResultInfo? info,
]) => ref.graph == gamePackFieldNamespace
    ? info?.label ?? gamePackKeyLabel(ref.output)
    : '${gamePackKeyLabel(ref.graph)} › ${gamePackKeyLabel(ref.output)}';

String gamePackResultDetail(GamePackResultInfo info) => [
  info.origin.label,
  info.grain?.label,
  info.type.toString(),
].nonNulls.join(' · ');

GamePackDesign withGamePackCalculation(
  GamePackDesign design,
  GamePackCalculation calculation,
) => design.copyWith(
  calculations: [
    for (final prior in design.calculations)
      if (prior.id == calculation.id) calculation else prior,
    if (!design.calculations.any((prior) => prior.id == calculation.id))
      calculation,
  ],
);

({String? operation, List<String> inputs}) calculationDetails(
  GamePackAnalysis catalog,
  GamePackCalculation calculation,
) {
  final root = calculation.nodesById[calculation.result];
  final inputs = [
    for (final node in calculation.nodes.whereType<GamePackInputNode>())
      if (catalog.tryInfo(gamePackFieldRef(node.field ?? '')) case final field?)
        field.label.split(' · ').first,
  ];
  return (
    operation: root is GamePackStepNode ? root.operation.label : null,
    inputs: inputs,
  );
}

bool matchesGamePackSearch(String text, String query) {
  final searchable = text.toLowerCase();
  return query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .every(searchable.contains);
}
