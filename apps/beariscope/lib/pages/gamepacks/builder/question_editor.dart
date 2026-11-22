import 'package:core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import 'design.dart';
import 'form_grid.dart';

typedef GamePackQuestionEdit = ({GamePackField field, GamePackControl control});

Future<GamePackQuestionEdit?> editGamePackQuestion(
  BuildContext context, {
  required Set<String> ids,
  required GamePackField? field,
  required GamePackControl? control,
  required GamePackFormPage page,
  required GamePackPlacement? placement,
  required List<GamePackField> conditionFields,
}) => BearingsModal.show<GamePackQuestionEdit>(
  context,
  builder: (_) => _QuestionEditor(
    ids: ids,
    field: field,
    control: control,
    page: page,
    placement: placement,
    conditionFields: conditionFields,
  ),
);

enum GamePackAnswerKind {
  integer('Whole number', GamePackType.integer),
  decimal('Number', GamePackType.number),
  boolean('Yes / No', GamePackType.boolean),
  text('Text', GamePackType.text),
  choice('Single choice', GamePackType.text),
  multiple('Multiple choices', GamePackType.list(GamePackType.text)),
  roster('Alliance roster', GamePackType.list(GamePackType.text));

  const GamePackAnswerKind(this.label, this.type);
  final String label;
  final GamePackType type;

  IconData get icon => switch (this) {
    integer || decimal => LucideIcons.hash,
    boolean => LucideIcons.toggleLeft,
    text => LucideIcons.text,
    choice || multiple => LucideIcons.listChecks,
    roster => LucideIcons.users,
  };

  static GamePackAnswerKind forQuestion(GamePackField? field) {
    if (field == null) return integer;
    if (field.choices.isNotEmpty && field.type == GamePackType.text) {
      return choice;
    }
    if (field.type == const GamePackType.list(GamePackType.text) &&
        field.choices.isEmpty) {
      return roster;
    }
    return values.firstWhere((kind) => kind.type == field.type);
  }
}

class _QuestionEditor extends StatefulWidget {
  const _QuestionEditor({
    required this.ids,
    required this.field,
    required this.control,
    required this.page,
    required this.placement,
    required this.conditionFields,
  });

  final Set<String> ids;
  final GamePackField? field;
  final GamePackControl? control;
  final GamePackFormPage page;
  final GamePackPlacement? placement;
  final List<GamePackField> conditionFields;

  @override
  State<_QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<_QuestionEditor> {
  late final _label = TextEditingController(text: widget.field?.label ?? '');
  late final _choices = TextEditingController(
    text: widget.field?.choices.join('\n') ?? '',
  );
  late final _minimum = TextEditingController(
    text: widget.field?.minimum?.toString() ?? '',
  );
  late final _maximum = TextEditingController(
    text: widget.field?.maximum?.toString() ?? '',
  );
  late final _originalDefault = switch (widget.field?.defaultValue) {
    final List values => values.join(', '),
    {'state': 'unknown'} => 'Unknown',
    {'state': 'notApplicable'} => 'Not applicable',
    null => '',
    final value => value.toString(),
  };
  late final _default = TextEditingController(text: _originalDefault);
  late GamePackAnswerKind _kind = GamePackAnswerKind.forQuestion(widget.field);
  late bool _required = widget.field?.isRequired ?? true;
  late bool _unknown = widget.field?.allowUnknown ?? false;
  late bool _notApplicable = widget.field?.allowNotApplicable ?? false;
  late GamePackControlType? _display = widget.control?.type;
  late GamePackField? _dependency = widget.conditionFields
      .where((field) => field.id == widget.control?.visibleWhen?.field)
      .firstOrNull;
  late String _equals = widget.control?.visibleWhen?.equals.toString() ?? '';
  late final _position = <int?>[
    if (widget.placement case final place?) ...[
      place.x + 1,
      place.y + 1,
      place.width,
      place.height,
    ],
  ];
  String? _error;

  @override
  void dispose() {
    for (final controller in [_label, _choices, _minimum, _maximum, _default]) {
      controller.dispose();
    }
    super.dispose();
  }

  num? _finiteNumber(String value) {
    final parsed = num.tryParse(value);
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  num? _bound(TextEditingController controller) {
    final content = controller.text.trim();
    if (content.isEmpty) return null;
    final value = _finiteNumber(content);
    if (value == null) {
      throw const FormatException('Enter a finite bound.');
    }
    return value;
  }

  Object? _defaultValue() {
    if (widget.field != null &&
        _kind == GamePackAnswerKind.forQuestion(widget.field) &&
        _default.text == _originalDefault) {
      return widget.field!.defaultValue;
    }
    final value = _default.text.trim();
    if (value.isEmpty) return null;
    return switch (_kind) {
      GamePackAnswerKind.integer => int.tryParse(value) ?? value,
      GamePackAnswerKind.decimal => num.tryParse(value) ?? value,
      GamePackAnswerKind.boolean =>
        value == 'true'
            ? true
            : value == 'false'
            ? false
            : value,
      GamePackAnswerKind.multiple =>
        value.split(',').map((item) => item.trim()).toList(),
      GamePackAnswerKind.roster => null,
      _ => value,
    };
  }

  bool get _isNumeric => GamePackType.number.accepts(_kind.type);
  bool get _hasChoices =>
      _kind == GamePackAnswerKind.choice ||
      _kind == GamePackAnswerKind.multiple;

  void _save() {
    try {
      final label = _label.text.trim();
      final id =
          widget.field?.id ?? gamePackIdForName(label, widget.ids, 'question');
      final originalChoices = widget.field?.choices ?? const <String>[];
      final choices = !_hasChoices
          ? const <String>[]
          : _choices.text == originalChoices.join('\n')
          ? originalChoices
          : _choices.text
                .split('\n')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList();
      if (_hasChoices && choices.isEmpty) {
        throw const FormatException('Enter at least one choice.');
      }
      final field = GamePackField(
        id,
        label,
        type: _kind.type,
        isRequired: _required,
        choices: choices,
        minimum: _isNumeric ? _bound(_minimum) : null,
        maximum: _isNumeric ? _bound(_maximum) : null,
        defaultValue: _defaultValue(),
        allowUnknown: _unknown,
        allowNotApplicable: _notApplicable,
      );
      field.validateDefinition();
      GamePackVisibility? visibility;
      if (_dependency case final dependency?) {
        final value = switch (dependency.type.kind) {
          GamePackTypeKind.boolean => switch (_equals.toLowerCase()) {
            'true' || 'yes' => true,
            'false' || 'no' => false,
            _ => _equals,
          },
          GamePackTypeKind.integer => int.tryParse(_equals) ?? _equals,
          GamePackTypeKind.number => num.tryParse(_equals) ?? _equals,
          _ => _equals,
        };
        dependency.readAnswer(value);
        visibility = GamePackVisibility(dependency.id, value);
      }
      GamePackPlacement? placement;
      if (widget.page.usesGrid) {
        if (_position.any((value) => value == null)) {
          throw const FormatException('Enter a row, column, width and height.');
        }
        placement = GamePackPlacement(
          _position[0]! - 1,
          _position[1]! - 1,
          _position[2]!,
          _position[3]!,
        );
        if (!canPlaceGridControl(
          widget.page,
          placement,
          excluding: widget.control,
        )) {
          throw const FormatException(
            'Choose an open area inside the page grid.',
          );
        }
      }
      BearingsModal.complete(context, (
        field: field,
        control: GamePackControl(
          field: id,
          type: _displayType(field),
          visibleWhen: visibility,
          placement: placement,
        ),
      ));
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  GamePackControlType _displayType(GamePackField field) {
    if (_display case final type? when type.accepts(field)) return type;
    return GamePackControlType.values.firstWhere((type) => type.accepts(field));
  }

  @override
  Widget build(BuildContext context) {
    final answer = GamePackField(
      'question',
      '',
      type: _kind.type,
      choices: _hasChoices ? const ['Choice'] : const [],
      minimum: _finiteNumber(_minimum.text),
      maximum: _finiteNumber(_maximum.text),
    );
    final displayTypes = GamePackControlType.values.where(
      (type) => type.accepts(answer),
    );
    return BearingsModal(
      title: widget.field == null ? 'Add question' : 'Edit question',
      actions: const [],
      primaryAction: BearingsModalPrimaryAction(
        label: 'Save question',
        icon: LucideIcons.check,
        onPressed: _save,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          TextField(
            controller: _label,
            decoration: const InputDecoration(
              labelText: 'Question label',
              hintText: 'Robots docked',
            ),
          ),
          BearingsSelect<GamePackAnswerKind>(
            value: _kind,
            decoration: const InputDecoration(labelText: 'Answer type'),
            items: [
              for (final kind in GamePackAnswerKind.values)
                BearingsSelectItem(
                  value: kind,
                  child: Row(
                    children: [
                      Icon(kind.icon, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          kind.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (kind) => setState(() {
              _kind = kind ?? _kind;
              _display = null;
            }),
          ),
          BearingsSelect<GamePackControlType>(
            value: _displayType(answer),
            decoration: const InputDecoration(labelText: 'Display as'),
            items: [
              for (final type in displayTypes)
                BearingsSelectItem(value: type, child: Text(type.label)),
            ],
            onChanged: (type) => setState(() => _display = type),
          ),
          if (_isNumeric)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minimum,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Minimum'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _maximum,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Maximum'),
                  ),
                ),
              ],
            ),
          if (_hasChoices)
            TextField(
              controller: _choices,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Choices',
                helperText: 'One choice per line',
              ),
            ),
          if (_kind != GamePackAnswerKind.roster)
            TextField(
              controller: _default,
              decoration: InputDecoration(
                labelText: 'Default answer',
                helperText: _kind == GamePackAnswerKind.boolean
                    ? 'Enter true or false'
                    : null,
              ),
            ),
          const SizedBox(height: 4),
          Text('Answer rules', style: Theme.of(context).textTheme.titleSmall),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Require an answer'),
            value: _required,
            onChanged: (value) => setState(() => _required = value),
          ),
          if (widget.conditionFields.isNotEmpty)
            BearingsSelect<GamePackField?>(
              value: _dependency,
              decoration: const InputDecoration(labelText: 'Show question'),
              items: [
                const BearingsSelectItem(
                  value: null,
                  child: Text('Always visible'),
                ),
                for (final field in widget.conditionFields)
                  BearingsSelectItem(value: field, child: Text(field.label)),
              ],
              onChanged: (field) => setState(() => _dependency = field),
            ),
          if (_dependency != null)
            TextFormField(
              initialValue: _equals,
              onChanged: (value) => _equals = value,
              decoration: const InputDecoration(
                labelText: 'When the answer is',
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow Unknown'),
            value: _unknown,
            onChanged: (value) => setState(() => _unknown = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow Not applicable'),
            value: _notApplicable,
            onChanged: (value) => setState(() => _notApplicable = value),
          ),
          if (_position.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Grid position'),
              children: [
                for (final (index, label) in [
                  'Column',
                  'Row',
                  'Width',
                  'Height',
                ].indexed)
                  TextFormField(
                    initialValue: _position[index]?.toString(),
                    keyboardType: TextInputType.number,
                    onChanged: (value) =>
                        _position[index] = int.tryParse(value),
                    decoration: InputDecoration(labelText: label),
                  ),
              ],
            ),
          if (_error case final error?)
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
