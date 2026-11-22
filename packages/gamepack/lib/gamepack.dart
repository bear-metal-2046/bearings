import 'src/analysis.dart';
import 'src/forms.dart';
import 'src/team_cards.dart';
import 'src/value.dart';
import 'src/results.dart';

export 'src/analysis.dart';
export 'src/forms.dart';
export 'src/graph.dart';
export 'src/program.dart';
export 'src/sources.dart';
export 'src/results.dart';
export 'src/team_cards.dart';
export 'src/value.dart';
export 'src/views.dart';

/// An immutable, validated release of a scouting season.
class GamePackDefinition {
  GamePackDefinition.typed({
    required this.name,
    required List<GamePackField> fields,
    required List<GamePackForm> forms,
    List<GamePackTbaField> tbaFields = const [],
    List<GamePackCalculation> calculations = const [],
    Map<String, GamePackReportChoice> reportChoices = const {},
    GamePackResults? results,
    this.season,
  }) : fields = List.unmodifiable(fields),
       forms = List.unmodifiable(forms),
       results = results ?? GamePackResults() {
    validateGamePackLabel(name);
    if (season != null && (season! < 1992 || season! > 9999)) {
      throw const FormatException('Enter a valid FRC season.');
    }
    _validateForms();
    analysis = GamePackAnalysis(
      fields: this.fields,
      forms: this.forms,
      tbaFields: tbaFields,
      calculations: calculations,
      reportChoices: reportChoices,
    );
    this.results.validate(analysis, this.forms);
  }

  static const formatVersion = 6;
  static const maxTypedFields = 256;

  final int? season;
  final String name;
  final List<GamePackField> fields;
  final GamePackResults results;
  List<GamePackTeamCardLayout> get teamCards => results.layouts;
  final List<GamePackForm> forms;
  late final GamePackAnalysis analysis;
  late final Map<String, GamePackField> fieldById;

  factory GamePackDefinition.fromJson(Map<String, dynamic> json) {
    final version = json['formatVersion'];
    if (version != formatVersion) {
      throw const FormatException('Unsupported GamePack format');
    }
    final fields = _readList(json['fields'], GamePackField.fromJson);
    return GamePackDefinition.typed(
      name: json['name'] as String,
      season: json['season'] as int?,
      fields: fields,
      forms: _readList(json['forms'], GamePackForm.fromJson),
      results: GamePackResults.fromJson(
        json['results'] as Map<String, dynamic>? ?? const {},
      ),
      tbaFields: _readList(
        json['tbaFields'] ?? const [],
        GamePackTbaField.fromJson,
      ),
      calculations: _readList(
        json['calculations'] ?? const [],
        GamePackCalculation.fromJson,
      ),
      reportChoices:
          (json['reportChoices'] as Map<String, dynamic>? ?? const {}).map(
            (key, value) => MapEntry(
              key,
              GamePackReportChoice.values.byName(value as String),
            ),
          ),
    );
  }

  Map<String, dynamic> toJson() => {
    'formatVersion': formatVersion,
    'name': name,
    if (season case final value?) 'season': value,
    'fields': fields.map((field) => field.toJson()).toList(),
    'forms': forms.map((form) => form.toJson()).toList(),
    'results': results.toJson(),
    'tbaFields': analysis.tbaFields.map((field) => field.toJson()).toList(),
    'calculations': analysis.calculations
        .map((recipe) => recipe.toJson())
        .toList(),
    if (analysis.reportChoices.isNotEmpty)
      'reportChoices': analysis.reportChoices.map(
        (key, choice) => MapEntry(key, choice.name),
      ),
  };

  GamePackForm formById(String id) =>
      forms.where((form) => form.id == id).firstOrNull ??
      (throw FormatException('Unknown form: $id.'));

  GamePackForm? formFor(GamePackFormKind kind) =>
      forms.where((form) => form.kind == kind).firstOrNull;

  void _validateForms() {
    if (fields.isEmpty ||
        fields.length > maxTypedFields ||
        forms.isEmpty ||
        forms.length > GamePackFormKind.values.length) {
      throw const FormatException('Add at least one form and 1–256 fields.');
    }
    final indexed = <String, GamePackField>{};
    for (final field in fields) {
      field.validateDefinition();
      if (indexed.containsKey(field.id)) {
        throw FormatException('Duplicate field ID: ${field.id}.');
      }
      indexed[field.id] = field;
    }
    fieldById = Map.unmodifiable(indexed);

    final ids = <String>{};
    final kinds = <GamePackFormKind>{};
    for (final form in forms) {
      if (!ids.add(form.id) || !kinds.add(form.kind)) {
        throw FormatException(
          'Publish one form per workflow. Duplicate form: ${form.label}.',
        );
      }
      form.validate(fieldById);
    }
  }

  void validateAnswers(Map<String, Object?> answers, {String? formId}) {
    decodeAnswers(answers, formId: formId);
  }

  Map<String, GamePackValue> decodeAnswers(
    Map<String, Object?> answers, {
    String? formId,
  }) {
    final form = formId == null
        ? forms.singleOrNull ??
              (throw const FormatException(
                'Choose a form for this submission.',
              ))
        : formById(formId);
    final visible = form.visibleFields(answers);
    for (final id in visible) {
      final field = fieldById[id]!;
      if (field.isRequired && !answers.containsKey(id)) {
        throw FormatException('${field.label} is required.');
      }
    }
    return {
      for (final entry in answers.entries)
        entry.key: visible.contains(entry.key)
            ? fieldById[entry.key]!.readAnswer(entry.value)
            : (throw FormatException(
                'Field ${entry.key} is unavailable on this form.',
              )),
    };
  }
}

List<T> _readList<T>(Object? value, T Function(Map<String, dynamic>) read) =>
    (value as List<dynamic>)
        .map((item) => read(item as Map<String, dynamic>))
        .toList();
