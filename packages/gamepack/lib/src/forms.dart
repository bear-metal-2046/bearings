import 'value.dart';

final _formIdentifier = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

class GamePackField {
  const GamePackField(
    this.id,
    this.label, {
    this.isRequired = true,
    this.type = GamePackType.number,
    this.defaultValue,
    this.minimum,
    this.maximum,
    this.choices = const [],
    this.allowUnknown = false,
    this.allowNotApplicable = false,
  });

  final String id;
  final String label;
  final bool isRequired;
  final GamePackType type;
  final Object? defaultValue;
  final num? minimum;
  final num? maximum;
  final List<String> choices;
  final bool allowUnknown;
  final bool allowNotApplicable;

  factory GamePackField.fromJson(Map<String, dynamic> json) => GamePackField(
    json['id'] as String,
    json['label'] as String,
    isRequired: json['required'] as bool,
    type: json.containsKey('type')
        ? GamePackType.fromJson(json['type'])
        : GamePackType.number,
    defaultValue: json['defaultValue'],
    minimum: json['minimum'] as num?,
    maximum: json['maximum'] as num?,
    choices: List.unmodifiable(
      (json['choices'] as List<dynamic>? ?? []).cast<String>(),
    ),
    allowUnknown: json['allowUnknown'] as bool? ?? false,
    allowNotApplicable: json['allowNotApplicable'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'required': isRequired,
    if (type != GamePackType.number) 'type': type.toJson(),
    if (defaultValue != null) 'defaultValue': defaultValue,
    if (minimum != null) 'minimum': minimum,
    if (maximum != null) 'maximum': maximum,
    if (choices.isNotEmpty) 'choices': choices,
    if (allowUnknown) 'allowUnknown': true,
    if (allowNotApplicable) 'allowNotApplicable': true,
  };

  void validateDefinition() {
    validateGamePackIdentifier(id);
    validateGamePackLabel(label);
    final scalar = switch (type.kind) {
      GamePackTypeKind.boolean ||
      GamePackTypeKind.integer ||
      GamePackTypeKind.number ||
      GamePackTypeKind.text => true,
      _ => false,
    };
    final isChoiceList = type == const GamePackType.list(GamePackType.text);
    if (!scalar && !isChoiceList) {
      throw FormatException('Form field $id uses an unsupported type: $type.');
    }
    if ((minimum != null || maximum != null) &&
        (!GamePackType.number.accepts(type) ||
            minimum?.isFinite == false ||
            maximum?.isFinite == false ||
            (minimum != null && maximum != null && minimum! > maximum!))) {
      throw FormatException('Invalid bounds for $label.');
    }
    if (choices.isNotEmpty &&
        ((type != GamePackType.text && !isChoiceList) ||
            choices.length > 64 ||
            choices.any(
              (choice) => choice.trim().isEmpty || choice.length > 80,
            ) ||
            choices.toSet().length != choices.length)) {
      throw FormatException('Invalid choices for $label.');
    }
    if (defaultValue != null) readAnswer(defaultValue);
  }

  /// Decode an answer as recorded. Explicit uncertainty is tagged in JSON.
  GamePackValue readAnswer(Object? raw) {
    final value = switch (raw) {
      {'state': 'unknown'} => GamePackValue.unknown,
      {'state': 'notApplicable'} => GamePackValue.notApplicable,
      _ => GamePackValue.of(raw),
    };
    if (value.state == GamePackValueState.unknown) {
      if (!allowUnknown || raw is! Map || raw['state'] != 'unknown')
        throw FormatException('$label needs a value.');
      return value;
    }
    if (value.state == GamePackValueState.notApplicable) {
      if (!allowNotApplicable) {
        throw FormatException('$label cannot be marked not applicable.');
      }
      return value;
    }
    if (!type.acceptsValue(value) ||
        (raw is List &&
            (raw.length > 64 ||
                raw.toSet().length != raw.length ||
                raw.any(
                  (item) =>
                      item is! String ||
                      item.trim().isEmpty ||
                      item.length > 80,
                )))) {
      throw FormatException('$label expects $type.');
    }
    if (raw is num &&
        ((minimum != null && raw < minimum!) ||
            (maximum != null && raw > maximum!))) {
      final limits = [
        if (minimum != null) 'at least $minimum',
        if (maximum != null) 'at most $maximum',
      ];
      throw FormatException('$label must be ${limits.join(' and ')}.');
    }
    if (choices.isNotEmpty) {
      final selected = raw is List ? raw : [raw];
      if (selected.any((choice) => !choices.contains(choice)) ||
          selected.toSet().length != selected.length) {
        throw FormatException('$label has an unavailable choice.');
      }
    }
    return value;
  }
}

enum GamePackFormKind {
  match('Match scouting'),
  strategy('Strategy scouting'),
  pit('Pit scouting'),
  observation('Observations');

  const GamePackFormKind(this.label);
  final String label;
}

enum GamePackControlType {
  number('Number'),
  stepper('Stepper'),
  counter('Counter'),
  slider('Slider'),
  toggle('Toggle'),
  choice('Dropdown'),
  segmented('Segmented choice'),
  multiChoice('Multiple choices'),
  ranking('Ranking'),
  text('Text'),
  multiline('Long text');

  const GamePackControlType(this.label);
  final String label;

  bool accepts(GamePackField field) => switch (this) {
    number => GamePackType.number.accepts(field.type),
    counter || stepper => field.type == GamePackType.integer,
    slider =>
      GamePackType.number.accepts(field.type) &&
          field.minimum != null &&
          field.maximum != null &&
          (field.type == GamePackType.integer
              ? field.minimum!.ceil() < field.maximum!.floor()
              : field.minimum! < field.maximum!),
    toggle => field.type == GamePackType.boolean,
    choice ||
    segmented => field.type == GamePackType.text && field.choices.isNotEmpty,
    multiChoice =>
      field.type == const GamePackType.list(GamePackType.text) &&
          field.choices.isNotEmpty,
    ranking => field.type == const GamePackType.list(GamePackType.text),
    text ||
    multiline => field.type == GamePackType.text && field.choices.isEmpty,
  };
}

/// A rectangle measured in whole cells of the page grid.
class GamePackPlacement {
  const GamePackPlacement(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;

  factory GamePackPlacement.fromJson(Map<String, dynamic> json) =>
      GamePackPlacement(
        json['x'] as int,
        json['y'] as int,
        json['width'] as int,
        json['height'] as int,
      );

  Map<String, int> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  bool fits(int columns, int rows) =>
      x >= 0 &&
      y >= 0 &&
      width > 0 &&
      height > 0 &&
      x + width <= columns &&
      y + height <= rows;
  bool overlaps(GamePackPlacement other) =>
      x < other.x + other.width &&
      x + width > other.x &&
      y < other.y + other.height &&
      y + height > other.y;
}

class GamePackVisibility {
  const GamePackVisibility(this.field, this.equals);

  final String field;
  final Object equals;

  factory GamePackVisibility.fromJson(Map<String, dynamic> json) =>
      GamePackVisibility(json['field'] as String, json['equals'] as Object);

  Map<String, Object> toJson() => {'field': field, 'equals': equals};
}

class GamePackControl {
  const GamePackControl({
    required this.field,
    required this.type,
    this.placement,
    this.visibleWhen,
  });

  final String field;
  final GamePackControlType type;
  final GamePackPlacement? placement;
  final GamePackVisibility? visibleWhen;

  factory GamePackControl.fromJson(Map<String, dynamic> json) {
    final placement = json['placement'] as Map<String, dynamic>?;
    final visibility = json['visibleWhen'] as Map<String, dynamic>?;
    return GamePackControl(
      field: json['field'] as String,
      type: _enumValue(GamePackControlType.values, json['type']),
      placement: placement == null
          ? null
          : GamePackPlacement.fromJson(placement),
      visibleWhen: visibility == null
          ? null
          : GamePackVisibility.fromJson(visibility),
    );
  }

  Map<String, Object> toJson() => {
    'field': field,
    'type': type.name,
    if (placement case final placement?) 'placement': placement.toJson(),
    if (visibleWhen case final visibility?) 'visibleWhen': visibility.toJson(),
  };
}

enum GamePackPageLayout {
  scrolling('Scrolling list'),
  grid('Grid');

  const GamePackPageLayout(this.label);
  final String label;
}

/// An ordered item in a scrolling section. A row has multiple equal-width
/// controls sharing one position in the section's vertical order.
class GamePackListItem {
  GamePackListItem.control(GamePackControl control)
    : controls = List.unmodifiable([control]),
      isRow = false;

  GamePackListItem.row(List<GamePackControl> controls)
    : controls = List.unmodifiable(controls),
      isRow = true;

  static const maxRowControls = 4;
  final List<GamePackControl> controls;
  final bool isRow;

  factory GamePackListItem.fromJson(Map<String, dynamic> json) =>
      switch (json['kind']) {
        'control' => GamePackListItem.control(
          GamePackControl.fromJson(json['control'] as Map<String, dynamic>),
        ),
        'row' => GamePackListItem.row(
          _decodeList(json['controls'], GamePackControl.fromJson),
        ),
        _ => throw const FormatException('Unsupported scrolling item.'),
      };

  Map<String, Object> toJson() => isRow
      ? {
          'kind': 'row',
          'controls': controls.map((control) => control.toJson()).toList(),
        }
      : {'kind': 'control', 'control': controls.single.toJson()};
}

class GamePackSection {
  GamePackSection({
    required this.id,
    required this.label,
    required List<GamePackListItem> items,
  }) : items = List.unmodifiable(items);

  factory GamePackSection.controls({
    required String id,
    required String label,
    required List<GamePackControl> controls,
  }) => GamePackSection(
    id: id,
    label: label,
    items: controls.map(GamePackListItem.control).toList(),
  );

  final String id;
  final String label;
  final List<GamePackListItem> items;
  Iterable<GamePackControl> get controls =>
      items.expand((item) => item.controls);

  factory GamePackSection.fromJson(Map<String, dynamic> json) =>
      GamePackSection(
        id: json['id'] as String,
        label: json['label'] as String,
        items: _decodeList(json['items'], GamePackListItem.fromJson),
      );

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'items': items.map((item) => item.toJson()).toList(),
  };
}

class GamePackFormPage {
  GamePackFormPage.scrolling({
    required this.id,
    required this.label,
    required List<GamePackSection> sections,
  }) : layout = GamePackPageLayout.scrolling,
       sections = List.unmodifiable(sections),
       gridControls = const [],
       columns = null,
       rows = null;

  GamePackFormPage.grid({
    required this.id,
    required this.label,
    required int this.columns,
    required int this.rows,
    required List<GamePackControl> controls,
  }) : layout = GamePackPageLayout.grid,
       gridControls = List.unmodifiable(controls),
       sections = const [];

  static const maxGridSize = 128;
  static bool isGridSize(int size) => size > 0 && size <= maxGridSize;
  final String id;
  final String label;
  final GamePackPageLayout layout;
  final List<GamePackSection> sections;
  final int? columns;
  final int? rows;
  final List<GamePackControl> gridControls;

  Iterable<GamePackControl> get controls =>
      usesGrid ? gridControls : sections.expand((section) => section.controls);
  bool get usesGrid => layout == GamePackPageLayout.grid;

  factory GamePackFormPage.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final label = json['label'] as String;
    return switch (json['layout']) {
      'scrolling'
          when !json.containsKey('columns') &&
              !json.containsKey('rows') &&
              !json.containsKey('controls') =>
        GamePackFormPage.scrolling(
          id: id,
          label: label,
          sections: _decodeList(json['sections'], GamePackSection.fromJson),
        ),
      'grid' when !json.containsKey('sections') => GamePackFormPage.grid(
        id: id,
        label: label,
        columns: json['columns'] as int,
        rows: json['rows'] as int,
        controls: _decodeList(json['controls'], GamePackControl.fromJson),
      ),
      _ => throw const FormatException(
        'Choose a scrolling list or grid layout for each page.',
      ),
    };
  }

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'layout': layout.name,
    if (usesGrid) ...{
      'columns': columns!,
      'rows': rows!,
      'controls': gridControls.map((control) => control.toJson()).toList(),
    } else
      'sections': sections.map((section) => section.toJson()).toList(),
  };
}

class GamePackForm {
  GamePackForm({
    required this.id,
    required this.label,
    required this.kind,
    required List<GamePackFormPage> pages,
  }) : pages = List.unmodifiable(pages);

  final String id;
  final String label;
  final GamePackFormKind kind;
  final List<GamePackFormPage> pages;

  Iterable<GamePackControl> get controls =>
      pages.expand((page) => page.controls);

  factory GamePackForm.fromJson(Map<String, dynamic> json) => GamePackForm(
    id: json['id'] as String,
    label: json['label'] as String,
    kind: _enumValue(GamePackFormKind.values, json['kind']),
    pages: _decodeList(json['pages'], GamePackFormPage.fromJson),
  );

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'kind': kind.name,
    'pages': pages.map((page) => page.toJson()).toList(),
  };

  void validate(Map<String, GamePackField> fields) {
    validateGamePackIdentifier(id);
    validateGamePackLabel(label);
    if (pages.isEmpty || pages.length > 32) {
      throw FormatException('$label needs 1–32 pages.');
    }
    final pageIds = <String>{};
    final controlsByField = <String, GamePackControl>{};
    for (final page in pages) {
      validateGamePackIdentifier(page.id);
      validateGamePackLabel(page.label);
      if (!pageIds.add(page.id)) {
        throw FormatException('Duplicate page ${page.label} in $label.');
      }
      if (page.usesGrid) {
        _validateGrid(page);
      } else {
        _validateSections(page);
      }
      for (final control in page.controls) {
        final field = fields[control.field];
        if (field == null || !control.type.accepts(field)) {
          throw FormatException(
            '${control.type.label} cannot edit ${control.field}.',
          );
        }
        if (control.type == GamePackControlType.ranking &&
            field.choices.isEmpty &&
            kind != GamePackFormKind.match &&
            kind != GamePackFormKind.strategy) {
          throw FormatException(
            '${field.label} needs fixed choices or a form with an alliance roster.',
          );
        }
        if (controlsByField.containsKey(control.field)) {
          throw FormatException('${field.label} is already present in $label.');
        }
        controlsByField[control.field] = control;
      }
    }
    final visiting = <String>{};
    final completed = <String>{};
    void validateVisibility(String field) {
      if (completed.contains(field)) return;
      if (!visiting.add(field))
        throw FormatException('Visibility cycle at $field.');
      final rule = controlsByField[field]!.visibleWhen;
      if (rule != null) {
        if (!controlsByField.containsKey(rule.field)) {
          throw FormatException(
            'Visibility for $field uses a field outside this form.',
          );
        }
        final value = rule.equals;
        if (value is! String && value is! bool && value is! num) {
          throw FormatException(
            'Visibility for $field needs a scalar comparison.',
          );
        }
        fields[rule.field]!.readAnswer(value);
        validateVisibility(rule.field);
      }
      visiting.remove(field);
      completed.add(field);
    }

    for (final field in controlsByField.keys) {
      validateVisibility(field);
    }
  }

  Set<String> visibleFields(Map<String, Object?> answers) {
    final bindings = {for (final control in controls) control.field: control};
    final results = <String, bool>{};
    bool visible(String id) => results.putIfAbsent(id, () {
      final rule = bindings[id]?.visibleWhen;
      return rule == null ||
          (answers[rule.field] == rule.equals && visible(rule.field));
    });
    return bindings.keys.where(visible).toSet();
  }

  Map<String, Object?> defaults(
    Map<String, GamePackField> fields, {
    List<String> roster = const [],
  }) {
    final answers = <String, Object?>{};
    for (final control in controls) {
      final field = fields[control.field];
      if (field == null) continue;
      if (field.defaultValue case final value?) {
        answers[control.field] = value;
      } else if (control.type == GamePackControlType.ranking) {
        final candidates = field.choices.isEmpty ? roster : field.choices;
        if (candidates.isNotEmpty) answers[control.field] = candidates;
      }
    }
    return answers;
  }

  void validateRankings(
    Map<String, Object?> answers,
    Map<String, GamePackField> fields, {
    List<String> roster = const [],
  }) {
    for (final control in controls) {
      if (control.type != GamePackControlType.ranking) continue;
      final value = answers[control.field];
      if (value is! List) continue;
      final field = fields[control.field]!;
      final candidates = field.choices.isEmpty ? roster : field.choices;
      if (candidates.isEmpty && field.choices.isEmpty) continue;
      if (value.length != candidates.length ||
          !value.toSet().containsAll(candidates)) {
        throw FormatException('${field.label} must rank each option once.');
      }
    }
  }

  void _validateGrid(GamePackFormPage page) {
    final columns = page.columns!;
    final rows = page.rows!;
    if (!GamePackFormPage.isGridSize(columns) ||
        !GamePackFormPage.isGridSize(rows)) {
      throw FormatException('Enter a valid grid size for ${page.label}.');
    }
    if (page.gridControls.isEmpty || page.gridControls.length > 128) {
      throw FormatException('${page.label} needs 1–128 controls.');
    }
    final placements = <GamePackPlacement>[];
    for (final control in page.gridControls) {
      final placement = control.placement;
      if (placement == null || !placement.fits(columns, rows)) {
        throw FormatException(
          '${control.field} must fit inside ${page.label}.',
        );
      }
      if (placements.any(placement.overlaps)) {
        throw FormatException(
          '${control.field} overlaps another control in ${page.label}.',
        );
      }
      placements.add(placement);
    }
  }

  void _validateSections(GamePackFormPage page) {
    if (page.sections.isEmpty || page.sections.length > 32) {
      throw FormatException('${page.label} needs 1–32 scrolling sections.');
    }
    final sectionIds = <String>{};
    for (final section in page.sections) {
      validateGamePackIdentifier(section.id);
      validateGamePackLabel(section.label);
      if (!sectionIds.add(section.id) ||
          section.items.isEmpty ||
          section.controls.length > 128) {
        throw FormatException('Invalid or empty section ${section.label}.');
      }
      for (final item in section.items) {
        if (item.controls.isEmpty ||
            item.controls.length > GamePackListItem.maxRowControls) {
          throw FormatException(
            'Each row in ${section.label} needs 1–4 controls.',
          );
        }
        if (item.controls.any((control) => control.placement != null)) {
          throw FormatException(
            'Controls in ${section.label} must use list order.',
          );
        }
      }
    }
  }
}

void validateGamePackIdentifier(String id) {
  if (!_formIdentifier.hasMatch(id)) throw FormatException('Invalid ID: $id.');
}

void validateGamePackLabel(String label) {
  if (label.trim().isEmpty || label.length > 80) {
    throw const FormatException('Use a name of 1–80 characters.');
  }
}

List<T> _decodeList<T>(Object? raw, T Function(Map<String, dynamic>) decode) =>
    (raw as List<dynamic>)
        .map((item) => decode(item as Map<String, dynamic>))
        .toList();

T _enumValue<T extends Enum>(List<T> choices, Object? name) =>
    choices.where((choice) => choice.name == name).firstOrNull ??
    (throw FormatException('Unsupported option: $name.'));
