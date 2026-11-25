part of 'gamepack_form_view.dart';

class _GamePackControlTile extends StatelessWidget {
  const _GamePackControlTile({
    super.key,
    required this.field,
    required this.control,
    required this.value,
    required this.change,
  });

  final GamePackField field;
  final GamePackControlType control;
  final Object? value;
  final ValueChanged<Object?>? change;

  Future<void> _edit(BuildContext context) async {
    var draft = value;
    final answer = await showDialog<(Object?,)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(field.label),
          scrollable: true,
          content: SizedBox(
            width: 360,
            child: _GamePackFieldView(
              field: field,
              control: control,
              value: draft,
              change: (value) => setState(() => draft = value),
              inDialog: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: field.isRequired && draft == null
                  ? null
                  : () => Navigator.pop(context, (draft,)),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    if (context.mounted && answer != null) change?.call(answer.$1);
  }

  @override
  Widget build(BuildContext context) => switch (control) {
    GamePackControlType.number ||
    GamePackControlType.text ||
    GamePackControlType.multiline => FormField<Object?>(
      validator: (_) => _textAnswerError(field, value),
      builder: (state) => _tile(state.errorText),
    ),
    _ => _tile(),
  };

  Widget _tile([String? error]) => LayoutBuilder(
    builder: (context, bounds) {
      final size = bounds.biggest;
      final colors = Theme.of(context).colorScheme;
      final menuSize = (size.shortestSide * .35).clamp(0.0, 36.0);
      final Widget input = switch (control) {
        GamePackControlType.toggle => _TileFace(
          label: field.label,
          detail: error ?? _answerSummary(value) ?? 'Unanswered',
          emphasized: value == true,
          onTap: change == null ? null : () => change!(value != true),
        ),
        GamePackControlType.choice => _choiceMenu(),
        GamePackControlType.counter ||
        GamePackControlType.stepper => _counter(size),
        GamePackControlType.segmented ||
        GamePackControlType.multiChoice => _choices(context, size),
        GamePackControlType.slider when size.width >= 56 && size.height >= 40 =>
          _slider(),
        _ => _editFace(context, error: error),
      };

      return Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: error == null ? colors.outlineVariant : colors.error,
          ),
        ),
        borderOnForeground: true,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            input,
            if (_canClear(field, value, change))
              PositionedDirectional(
                top: 0,
                end: 0,
                width: menuSize,
                height: menuSize,
                child: _clearAnswerMenu(
                  field,
                  () => change!(null),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Icon(LucideIcons.ellipsis, size: 18),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _editFace(BuildContext context, {String? error}) => _TileFace(
    label: field.label,
    detail:
        error ??
        _answerSummary(value) ??
        switch (control) {
          GamePackControlType.choice ||
          GamePackControlType.segmented ||
          GamePackControlType.multiChoice => 'Select',
          GamePackControlType.ranking => 'Rank',
          _ => 'Enter value',
        },
    onTap: change == null ? null : () => _edit(context),
  );

  Widget _choiceMenu() => PopupMenuButton<String>(
    tooltip: field.label,
    enabled: change != null,
    initialValue: value is String ? value as String : null,
    onSelected: change,
    itemBuilder: (_) => [
      for (final option in field.choices)
        PopupMenuItem(value: option, child: Text(option)),
    ],
    child: _TileFace(
      label: field.label,
      detail: _answerSummary(value) ?? 'Select',
      onTap: null,
    ),
  );

  Widget _counter(Size size) {
    final sideRail = size.width > size.height * 1.35;
    return Flex(
      direction: sideRail ? Axis.horizontal : Axis.vertical,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 2,
          child: _TileFace(
            label: field.label,
            detail: _answerSummary(value) ?? '—',
            semanticLabel: 'Increment ${field.label}',
            onTap: _counterAction(field, value, 1, change),
          ),
        ),
        Expanded(
          child: Flex(
            direction: sideRail ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final step in _counterSteps(
                control,
              ).where((step) => step != 1))
                Expanded(
                  child: _TileFace(
                    label: _stepLabel(step),
                    semanticLabel: '${field.label}, ${_stepLabel(step)}',
                    secondary: true,
                    onTap: _counterAction(field, value, step, change),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _choices(BuildContext context, Size size) {
    final options = field.choices;
    final columns = (size.width / 48).floor().clamp(1, options.length);
    final rows = (options.length / columns).ceil();
    if (size.height * .75 / rows < 36 || size.width < 48) {
      return control == GamePackControlType.segmented
          ? _choiceMenu()
          : _editFace(context);
    }
    final multiple = control == GamePackControlType.multiChoice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _TileFace(
            label: field.label,
            onTap: change == null ? null : () => _edit(context),
          ),
        ),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var row = 0; row < rows; row++)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final option
                          in options.skip(row * columns).take(columns))
                        Expanded(child: _choice(option, multiple)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _choice(String option, bool multiple) {
    final selected = multiple
        ? value is List && (value as List).contains(option)
        : value == option;
    return _TileFace(
      label: option,
      semanticLabel: '${field.label}, $option',
      selected: selected,
      emphasized: selected,
      secondary: true,
      onTap: change == null
          ? null
          : () {
              if (multiple) {
                change!(_toggleOption(value, option));
              } else {
                _selectAnswer(field, option, selected, change!);
              }
            },
    );
  }

  Widget _slider() => Stack(
    fit: StackFit.expand,
    children: [
      Semantics(label: field.label, child: _answerSlider(field, value, change)),
      IgnorePointer(
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _TileText(field.label, bold: true)),
              const Spacer(),
              Expanded(child: _TileText(_answerSummary(value) ?? '—')),
            ],
          ),
        ),
      ),
    ],
  );
}

String? _answerSummary(Object? value) => switch (value) {
  final bool value => value ? 'Yes' : 'No',
  final List values when values.isNotEmpty => values.join(' · '),
  final String value when value.trim().isNotEmpty => value,
  final num value => value.toString(),
  _ => null,
};

class _TileFace extends StatelessWidget {
  const _TileFace({
    required this.label,
    this.detail,
    this.semanticLabel,
    this.secondary = false,
    this.emphasized = false,
    this.selected,
    required this.onTap,
  });

  final String label;
  final String? detail;
  final String? semanticLabel;
  final bool secondary;
  final bool emphasized;
  final bool? selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel ?? label,
      value: detail,
      selected: selected,
      button: onTap != null,
      child: Ink(
        decoration: BoxDecoration(
          color: emphasized
              ? colors.primaryContainer
              : secondary
              ? colors.surfaceContainerHigh
              : null,
          border: secondary ? Border.all(color: colors.outlineVariant) : null,
        ),
        child: InkWell(
          onTap: onTap,
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: emphasized ? colors.onPrimaryContainer : colors.onSurface,
            ),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _TileText(label, bold: true)),
                  if (detail case final detail?)
                    Expanded(child: _TileText(detail, prominent: true)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TileText extends StatelessWidget {
  const _TileText(this.label, {this.bold = false, this.prominent = false});

  final String label;
  final bool bold;
  final bool prominent;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final inset = (bounds.biggest.shortestSide * .1).clamp(0.0, 8.0);
      final typography = Theme.of(context).textTheme;
      final style = prominent
          ? typography.headlineSmall
          : typography.titleSmall;
      return Padding(
        padding: EdgeInsets.all(inset),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: style?.copyWith(
              color: DefaultTextStyle.of(context).style.color,
              fontWeight: bold ? FontWeight.w700 : null,
            ),
          ),
        ),
      );
    },
  );
}
