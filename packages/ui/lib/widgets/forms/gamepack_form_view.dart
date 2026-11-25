import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../bearings_capsule_bar.dart';

part 'gamepack_control_tile.dart';

/// Used for collection and the authoring preview. The caller owns the answers,
/// which are stored exactly as they will be validated by Honeycomb.
class GamePackFormView extends StatefulWidget {
  const GamePackFormView({
    super.key,
    required this.fields,
    required this.form,
    required this.answers,
    required this.onChanged,
    this.enabled = true,
    this.initialPage = 0,
    this.pageNavigationTrailing,
  });

  final Map<String, GamePackField> fields;
  final GamePackForm form;
  final Map<String, Object?> answers;
  final ValueChanged<Map<String, Object?>> onChanged;
  final bool enabled;
  final int initialPage;
  final Widget? pageNavigationTrailing;

  @override
  State<GamePackFormView> createState() => _GamePackFormViewState();
}

class _GamePackFormViewState extends State<GamePackFormView> {
  late int _pageIndex = widget.initialPage;
  final _scrollPositions = PageStorageBucket();

  void _setValue(String id, Object? value) {
    final answers = {...widget.answers};
    if (value == null) {
      answers.remove(id);
    } else {
      answers[id] = value;
    }
    widget.onChanged(answers);
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.form.pages;
    final index = _pageIndex.clamp(0, pages.length - 1);
    final page = pages[index];
    final visible = widget.form.visibleFields(widget.answers);
    Widget field(GamePackControl control) {
      final definition = widget.fields[control.field]!;
      final value = widget.answers[control.field];
      final change = widget.enabled
          ? (Object? value) => _setValue(control.field, value)
          : null;
      final tiled = switch (control.appearance) {
        GamePackControlAppearance.automatic => page.usesGrid,
        GamePackControlAppearance.tile => true,
        GamePackControlAppearance.inline => false,
      };
      if (tiled) {
        final tile = _GamePackControlTile(
          key: ValueKey(('tile', control.field)),
          field: definition,
          control: control.type,
          value: value,
          change: change,
        );
        return page.usesGrid
            ? tile
            : LayoutBuilder(
                builder: (_, bounds) => SizedBox(
                  height: (bounds.maxWidth * .65).clamp(120.0, 200.0),
                  child: tile,
                ),
              );
      }

      final inline = _GamePackFieldView(
        key: ValueKey(('control', control.field)),
        field: definition,
        control: control.type,
        value: value,
        change: change,
      );
      if (!page.usesGrid) return inline;
      // A grid still assigns an exact rectangle to an inline override.
      return LayoutBuilder(
        builder: (_, bounds) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.topStart,
          child: SizedBox(width: math.max(180, bounds.maxWidth), child: inline),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: page.usesGrid
              ? _GridPage(
                  key: ValueKey(page.id),
                  page: page,
                  visible: visible,
                  field: field,
                )
              : PageStorage(
                  bucket: _scrollPositions,
                  child: ListView(
                    key: PageStorageKey(page.id),
                    primary: false,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final section in page.sections)
                        if (section.controls.any(
                          (control) => visible.contains(control.field),
                        )) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              section.label,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          for (final item in section.items)
                            if (item.controls
                                    .where(
                                      (control) =>
                                          visible.contains(control.field),
                                    )
                                    .toList()
                                case final controls when controls.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: controls.length == 1
                                    ? field(controls.single)
                                    : Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          for (final (index, control)
                                              in controls.indexed) ...[
                                            if (index > 0)
                                              const SizedBox(width: 8),
                                            Expanded(child: field(control)),
                                          ],
                                        ],
                                      ),
                              ),
                        ],
                    ],
                  ),
                ),
        ),
        if (pages.length > 1 || widget.pageNavigationTrailing != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (pages.length > 1)
                  Expanded(
                    child: BearingsCapsuleBar<int>(
                      selected: index,
                      onActivated: (page) => setState(() => _pageIndex = page),
                      destinations: [
                        for (final (index, page) in pages.indexed)
                          BearingsCapsuleDestination(
                            value: index,
                            label: page.label,
                          ),
                      ],
                    ),
                  ),
                if (pages.length > 1 && widget.pageNavigationTrailing != null)
                  const SizedBox(width: 8),
                ?widget.pageNavigationTrailing,
              ],
            ),
          ),
      ],
    );
  }
}

class _GridPage extends StatelessWidget {
  const _GridPage({
    super.key,
    required this.page,
    required this.visible,
    required this.field,
  });

  final GamePackFormPage page;
  final Set<String> visible;
  final Widget Function(GamePackControl) field;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.biggest.isEmpty) return const SizedBox.expand();
      final cellWidth = constraints.maxWidth / page.columns!;
      final cellHeight = constraints.maxHeight / page.rows!;
      return Stack(
        fit: StackFit.expand,
        children: [
          for (final control in page.gridControls)
            if (visible.contains(control.field))
              Positioned(
                left: control.placement!.x * cellWidth,
                top: control.placement!.y * cellHeight,
                width: control.placement!.width * cellWidth,
                height: control.placement!.height * cellHeight,
                key: ValueKey(control.field),
                child: field(control),
              ),
        ],
      );
    },
  );
}

class _GamePackFieldView extends StatelessWidget {
  const _GamePackFieldView({
    super.key,
    required this.field,
    required this.control,
    required this.value,
    required this.change,
    this.inDialog = false,
  });

  final GamePackField field;
  final GamePackControlType control;
  final Object? value;
  final ValueChanged<Object?>? change;
  final bool inDialog;

  @override
  Widget build(BuildContext context) {
    final Widget input = switch (control) {
      GamePackControlType.number ||
      GamePackControlType.text ||
      GamePackControlType.multiline => _GamePackTextField(
        field: field,
        control: control,
        value: value,
        change: change,
        autofocus: inDialog,
      ),
      GamePackControlType.toggle => _choices([
        _chip('Yes', value == true, true),
        _chip('No', value == false, false),
      ]),
      GamePackControlType.choice => DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: field.choices.contains(value) ? value as String : null,
        decoration: InputDecoration(
          labelText: field.label,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final option in field.choices)
            DropdownMenuItem(
              value: option,
              child: Text(option, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: change,
      ),
      GamePackControlType.segmented => _choices([
        for (final option in field.choices)
          _chip(option, value == option, option),
      ]),
      GamePackControlType.multiChoice => _choices([
        for (final option in field.choices) _filterChip(option),
      ]),
      GamePackControlType.ranking => _ranking(),
      GamePackControlType.counter ||
      GamePackControlType.stepper => _counter(context),
      GamePackControlType.slider => _slider(),
    };
    if (inDialog || field.isRequired) return input;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: input),
        if (_canClear(field, value, change))
          _clearAnswerMenu(field, () => change!(null)),
      ],
    );
  }

  Widget _chip(String label, bool selected, Object option) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: change == null
        ? null
        : (_) => _selectAnswer(field, option, selected, change!),
  );

  Widget _filterChip(String option) => FilterChip(
    label: Text(option),
    selected: value is List && (value as List).contains(option),
    onSelected: change == null
        ? null
        : (_) => change!(_toggleOption(value, option)),
  );

  Widget _choices(List<Widget> choices) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (!inDialog) Text(field.label),
      Wrap(spacing: 6, runSpacing: 2, children: choices),
    ],
  );

  Widget _ranking() {
    final order = value is List
        ? (value as List).cast<String>()
        : field.choices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!inDialog) Text(field.label),
        if (order.isEmpty) const Text('No options available'),
        if (order.isNotEmpty)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) {
              final next = [...order];
              final item = next.removeAt(from);
              next.insert(to, item);
              change?.call(next);
            },
            children: [
              for (final (index, item) in order.indexed)
                ListTile(
                  key: ValueKey(item),
                  leading: Text('${index + 1}'),
                  title: Text(
                    field.choices.isEmpty ? item.replaceFirst('frc', '') : item,
                  ),
                  trailing: change == null
                      ? null
                      : ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(LucideIcons.gripVertical),
                          ),
                        ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _counter(BuildContext context) {
    final known = value is int ? value as int : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!inDialog) Text(field.label),
        Text(
          known?.toString() ?? '—',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Wrap(
          spacing: 4,
          runSpacing: 2,
          children: [
            for (final step in _counterSteps(control))
              OutlinedButton(
                onPressed: _counterAction(field, value, step, change),
                child: Text(_stepLabel(step)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _slider() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        inDialog
            ? '${value is num ? value : '—'}'
            : '${field.label} · ${value is num ? value : '—'}',
      ),
      _answerSlider(field, value, change),
    ],
  );
}

bool _canClear(
  GamePackField field,
  Object? value,
  ValueChanged<Object?>? change,
) => !field.isRequired && value != null && change != null;

Widget _clearAnswerMenu(
  GamePackField field,
  VoidCallback clear, {
  Widget? child,
}) => PopupMenuButton<void>(
  tooltip: '${field.label} answer options',
  icon: child == null ? const Icon(LucideIcons.ellipsis, size: 18) : null,
  itemBuilder: (_) => [
    PopupMenuItem<void>(onTap: clear, child: const Text('Clear answer')),
  ],
  child: child,
);

void _selectAnswer(
  GamePackField field,
  Object option,
  bool selected,
  ValueChanged<Object?> change,
) {
  if (!selected) {
    change(option);
  } else if (!field.isRequired) {
    change(null);
  }
}

List<String> _toggleOption(Object? value, String option) {
  final choices = value is List
      ? List<String>.of(value.cast<String>())
      : <String>[];
  if (!choices.remove(option)) choices.add(option);
  return choices;
}

List<int> _counterSteps(GamePackControlType control) =>
    control == GamePackControlType.counter
    ? const [-5, -1, 1, 5]
    : const [-1, 1];

String _stepLabel(int step) => step > 0 ? '+$step' : '$step';

VoidCallback? _counterAction(
  GamePackField field,
  Object? value,
  int step,
  ValueChanged<Object?>? change,
) {
  final current = value is int ? value : field.minimum?.ceil() ?? 0;
  final next = current + step;
  if (change == null ||
      (field.minimum != null && next < field.minimum!) ||
      (field.maximum != null && next > field.maximum!)) {
    return null;
  }
  return () => change(next);
}

Widget _answerSlider(
  GamePackField field,
  Object? value,
  ValueChanged<Object?>? change,
) {
  final minimum = field.minimum!;
  final maximum = field.maximum!;
  final isInteger = field.type == GamePackType.integer;
  final low = isInteger ? minimum.ceilToDouble() : minimum.toDouble();
  final high = isInteger ? maximum.floorToDouble() : maximum.toDouble();
  return Slider(
    min: low,
    max: high,
    value: (value is num ? value : minimum).toDouble().clamp(low, high),
    onChanged: change == null
        ? null
        : (number) => change(isInteger ? number.round() : number),
  );
}

String? _textAnswerError(GamePackField field, Object? value) {
  if (value == null) return field.isRequired ? 'Enter a value' : null;
  try {
    field.readAnswer(value);
    return null;
  } on FormatException catch (error) {
    return error.message;
  }
}

class _GamePackTextField extends StatefulWidget {
  const _GamePackTextField({
    required this.field,
    required this.control,
    required this.value,
    required this.change,
    this.autofocus = false,
  });

  final GamePackField field;
  final GamePackControlType control;
  final Object? value;
  final ValueChanged<Object?>? change;
  final bool autofocus;

  @override
  State<_GamePackTextField> createState() => _GamePackTextFieldState();
}

class _GamePackTextFieldState extends State<_GamePackTextField> {
  late final _controller = TextEditingController(
    text: _visibleText(widget.value),
  );

  bool get _numeric => widget.control == GamePackControlType.number;

  static String _visibleText(Object? value) =>
      value is num || value is String ? value.toString() : '';

  @override
  void didUpdateWidget(covariant _GamePackTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _parse(_controller.text) != widget.value) {
      _controller.text = _visibleText(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Object? _parse(String text) {
    if (text.trim().isEmpty) return null;
    if (!_numeric) return text;
    if (widget.field.type == GamePackType.integer) {
      return int.tryParse(text.trim()) ?? text;
    }
    final number = num.tryParse(text.trim());
    return number?.isFinite == true ? number : text;
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey(widget.field.id),
    controller: _controller,
    autofocus: widget.autofocus,
    enabled: widget.change != null,
    minLines: widget.control == GamePackControlType.multiline ? 3 : 1,
    maxLines: widget.control == GamePackControlType.multiline ? 5 : 1,
    keyboardType: _numeric
        ? TextInputType.numberWithOptions(
            decimal: widget.field.type != GamePackType.integer,
            signed: true,
          )
        : null,
    decoration: InputDecoration(
      labelText: widget.field.label,
      helperText: widget.field.isRequired ? null : 'Optional',
      border: const OutlineInputBorder(),
    ),
    validator: (text) => _textAnswerError(widget.field, _parse(text ?? '')),
    onChanged: widget.change == null
        ? null
        : (text) => widget.change!(_parse(text)),
  );
}
