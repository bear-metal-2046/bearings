import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

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
    this.reflowGrid = false,
  });

  final Map<String, GamePackField> fields;
  final GamePackForm form;
  final Map<String, Object?> answers;
  final ValueChanged<Map<String, Object?>> onChanged;
  final bool enabled;
  final int initialPage;

  /// Shows the questions in reading order when trying a tablet page on a phone.
  final bool reflowGrid;

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
    Widget field(GamePackControl control, {bool stretch = false}) =>
        _GamePackFieldView(
          key: ValueKey(('control', control.field)),
          field: widget.fields[control.field]!,
          control: control.type,
          value: widget.answers[control.field],
          stretch: stretch,
          change: widget.enabled
              ? (value) => _setValue(control.field, value)
              : null,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pages.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous scouting page',
                  onPressed: index > 0
                      ? () => setState(() => _pageIndex = index - 1)
                      : null,
                  icon: const Icon(LucideIcons.chevronLeft),
                ),
                Expanded(
                  child: Text(
                    page.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Next scouting page',
                  onPressed: index + 1 < pages.length
                      ? () => setState(() => _pageIndex = index + 1)
                      : null,
                  icon: const Icon(LucideIcons.chevronRight),
                ),
              ],
            ),
          ),
        Expanded(
          child: page.usesGrid
              ? widget.reflowGrid
                    ? _ReflowedGrid(page: page, visible: visible, field: field)
                    : _GridPage(
                        key: ValueKey(page.id),
                        page: page,
                        visible: visible,
                        field: (control) => field(control, stretch: true),
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
      ],
    );
  }
}

class _ReflowedGrid extends StatelessWidget {
  const _ReflowedGrid({
    required this.page,
    required this.visible,
    required this.field,
  });

  final GamePackFormPage page;
  final Set<String> visible;
  final Widget Function(GamePackControl) field;

  @override
  Widget build(BuildContext context) {
    final controls =
        page.gridControls
            .where((control) => visible.contains(control.field))
            .toList()
          ..sort((a, b) {
            final row = a.placement!.y.compareTo(b.placement!.y);
            return row == 0 ? a.placement!.x.compareTo(b.placement!.x) : row;
          });
    return ListView.separated(
      key: ValueKey(page.id),
      primary: false,
      itemCount: controls.length,
      itemBuilder: (_, index) => field(controls[index]),
      separatorBuilder: (_, _) => const SizedBox(height: 14),
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
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: LayoutBuilder(
                    builder: (context, bounds) => SingleChildScrollView(
                      primary: false,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: bounds.maxHeight,
                        ),
                        child: field(control),
                      ),
                    ),
                  ),
                ),
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
    required this.stretch,
    required this.change,
  });

  final GamePackField field;
  final GamePackControlType control;
  final Object? value;
  final bool stretch;
  final ValueChanged<Object?>? change;

  @override
  Widget build(BuildContext context) {
    final hasStateOptions = field.allowUnknown || field.allowNotApplicable;
    final Widget input = switch (control) {
      GamePackControlType.number ||
      GamePackControlType.text ||
      GamePackControlType.multiline => _GamePackTextField(
        field: field,
        control: control,
        value: value,
        change: change,
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
    if (!hasStateOptions) return input;

    final status = switch (value) {
      {'state': 'unknown'} => 'Unknown',
      {'state': 'notApplicable'} => 'Not applicable',
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(status ?? field.label)),
            if (change != null)
              PopupMenuButton<GamePackValueState>(
                tooltip: '${field.label} answer status',
                icon: const Icon(LucideIcons.ellipsis, size: 18),
                onSelected: (state) => change!(
                  state == GamePackValueState.missing
                      ? null
                      : {'state': state.name},
                ),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: GamePackValueState.missing,
                    child: Text('Clear answer'),
                  ),
                  if (field.allowUnknown)
                    const PopupMenuItem(
                      value: GamePackValueState.unknown,
                      child: Text('Unknown'),
                    ),
                  if (field.allowNotApplicable)
                    const PopupMenuItem(
                      value: GamePackValueState.notApplicable,
                      child: Text('Not applicable'),
                    ),
                ],
              ),
          ],
        ),
        input,
      ],
    );
  }

  static const _compactChipAvatar = BoxConstraints.tightFor(
    width: 12,
    height: 12,
  );

  Widget _fitChip(Widget Function(bool? showCheckmark) chip) => stretch
      ? LayoutBuilder(
          builder: (_, constraints) => chip(constraints.maxWidth >= 64),
        )
      : chip(null);

  Widget _chip(String label, bool selected, Object option) => _fitChip(
    (showCheckmark) => ChoiceChip(
      label: _buttonLabel(label, selected: selected),
      showCheckmark: showCheckmark,
      avatarBoxConstraints: stretch ? _compactChipAvatar : null,
      labelPadding: stretch ? EdgeInsets.zero : null,
      padding: stretch ? const EdgeInsets.symmetric(horizontal: 4) : null,
      selected: selected,
      onSelected: change == null ? null : (set) => change!(set ? option : null),
    ),
  );

  Widget _filterChip(String option) {
    final selected = value is List && (value as List).contains(option);
    return _fitChip(
      (showCheckmark) => FilterChip(
        label: _buttonLabel(option, selected: selected),
        showCheckmark: showCheckmark,
        avatarBoxConstraints: stretch ? _compactChipAvatar : null,
        labelPadding: stretch ? EdgeInsets.zero : null,
        padding: stretch ? const EdgeInsets.symmetric(horizontal: 4) : null,
        selected: selected,
        onSelected: change == null
            ? null
            : (selected) {
                final choices = switch (value) {
                  final List values => values.cast<String>().toList(),
                  _ => <String>[],
                };
                if (selected) {
                  choices.add(option);
                } else {
                  choices.remove(option);
                }
                change!(choices);
              },
      ),
    );
  }

  Widget _buttonLabel(String label, {bool selected = false}) => stretch
      ? SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: selected
                  ? const TextStyle(fontWeight: FontWeight.w600)
                  : null,
            ),
          ),
        )
      : Text(label);

  Widget _buttonGroup(List<Widget> buttons, {required double spacing}) {
    if (!stretch || buttons.isEmpty) {
      return Wrap(spacing: spacing, runSpacing: 2, children: buttons);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ((constraints.maxWidth + spacing) / (36 + spacing))
            .floor()
            .clamp(1, buttons.length);
        final width = math.max(
          0.0,
          (constraints.maxWidth - spacing * (columns - 1)) / columns,
        );
        return Wrap(
          spacing: spacing,
          runSpacing: 2,
          children: [
            for (final button in buttons) SizedBox(width: width, child: button),
          ],
        );
      },
    );
  }

  Widget _choices(List<Widget> choices) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(field.label),
      _buttonGroup(choices, spacing: stretch ? 4 : 6),
    ],
  );

  Widget _ranking() {
    final order = value is List
        ? (value as List).cast<String>()
        : field.choices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.label),
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
    final current = known ?? field.minimum?.ceil() ?? 0;
    final steps = control == GamePackControlType.counter
        ? [-5, -1, 1, 5]
        : [-1, 1];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.label),
        Text(
          known?.toString() ?? '—',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        _buttonGroup([
          for (final step in steps)
            OutlinedButton(
              style: stretch
                  ? OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    )
                  : null,
              onPressed:
                  change == null ||
                      (field.minimum != null &&
                          current + step < field.minimum!) ||
                      (field.maximum != null && current + step > field.maximum!)
                  ? null
                  : () => change!(current + step),
              child: _buttonLabel(step > 0 ? '+$step' : '$step'),
            ),
        ], spacing: 4),
      ],
    );
  }

  Widget _slider() {
    final minimum = field.minimum!;
    final maximum = field.maximum!;
    final known = value is num ? value as num : null;
    final position = (known ?? minimum).clamp(minimum, maximum).toDouble();
    final isInteger = field.type == GamePackType.integer;
    final low = isInteger ? minimum.ceilToDouble() : minimum.toDouble();
    final high = isInteger ? maximum.floorToDouble() : maximum.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${field.label} · ${known ?? '—'}'),
        Slider(
          min: low,
          max: high,
          value: position.clamp(low, high),
          onChanged: change == null
              ? null
              : (number) => change!(isInteger ? number.round() : number),
        ),
      ],
    );
  }
}

class _GamePackTextField extends StatefulWidget {
  const _GamePackTextField({
    required this.field,
    required this.control,
    required this.value,
    required this.change,
  });

  final GamePackField field;
  final GamePackControlType control;
  final Object? value;
  final ValueChanged<Object?>? change;

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
    validator: (text) {
      if (widget.value is Map) return null;
      final value = _parse(text ?? '');
      if (value == null) {
        return widget.field.isRequired ? 'Enter a value' : null;
      }
      try {
        widget.field.readAnswer(value);
        return null;
      } on FormatException catch (error) {
        return error.message;
      }
    },
    onChanged: widget.change == null
        ? null
        : (text) => widget.change!(_parse(text)),
  );
}
