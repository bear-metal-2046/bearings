import 'package:core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import 'calculation_canvas.dart';

Future<GamePackStepNode?> editCalculationStep(
  BuildContext context, {
  required GamePackStepNode node,
  required GamePackResultInfo? input,
}) => BearingsModal.show<GamePackStepNode>(
  context,
  builder: (_) => _StepSettings(node: node, input: input),
);

enum _LiteralType { number, text, yesNo }

enum _Counting { reported, positive, missingZero }

class _StepSettings extends StatefulWidget {
  const _StepSettings({required this.node, required this.input});
  final GamePackStepNode node;
  final GamePackResultInfo? input;
  @override
  State<_StepSettings> createState() => _StepSettingsState();
}

class _StepSettingsState extends State<_StepSettings> {
  GamePackRecipe get _op => widget.node.operation;
  late GamePackGrain _grain = widget.node.grain;
  late GamePackGrain? _row = widget.node.rowGrain;
  late bool _schedule = widget.node.scheduleRows;
  late _Counting _counting = widget.node.positiveOnly
      ? _Counting.positive
      : widget.node.missingAsZero
      ? _Counting.missingZero
      : _Counting.reported;
  late bool _fallback = widget.node.fallbackToScouted;
  late bool _positiveOfficial = widget.node.requirePositiveOfficial;
  late bool _qualifications = widget.node.qualificationsOnly;
  late bool _flagged = widget.node.flaggedOnly;
  late GamePackCondition _condition = widget.node.condition;
  late String _value = widget.node.comparisonValue?.toString() ?? '';
  late String _threshold = (widget.node.threshold * 100).toStringAsFixed(0);
  late String _minimum = widget.node.minimumReports.toString();
  late String _singular = widget.node.singular;
  late String _plural = widget.node.plural;
  late String _trials = widget.node.trials.toString();
  late _LiteralType _literal = switch (widget.node.comparisonValue) {
    bool() => _LiteralType.yesNo,
    String() => _LiteralType.text,
    _ => _LiteralType.number,
  };

  bool get _collection => _op.reducesRows || _op == GamePackRecipe.rows;
  bool get _comparison =>
      _op == GamePackRecipe.excludeValue ||
      _op == GamePackRecipe.condition &&
          [
            GamePackCondition.equals,
            GamePackCondition.different,
          ].contains(_condition);

  Object? get _comparisonValue {
    final kind = widget.input?.type.kind;
    if (_op == GamePackRecipe.constant)
      return switch (_literal) {
        _LiteralType.number => num.tryParse(_value),
        _LiteralType.text => _value,
        _LiteralType.yesNo => switch (_value.toLowerCase()) {
          'yes' || 'true' => true,
          'no' || 'false' => false,
          _ => null,
        },
      };
    if (_op == GamePackRecipe.quantile || kind == GamePackTypeKind.number)
      return num.tryParse(_value);
    if (kind == GamePackTypeKind.integer) return int.tryParse(_value);
    if (kind == GamePackTypeKind.boolean)
      return switch (_value.toLowerCase()) {
        'yes' || 'true' => true,
        'no' || 'false' => false,
        _ => null,
      };
    return _comparison ? _value : null;
  }

  List<GamePackGrain> get _scopes => switch (_op) {
    GamePackRecipe.scale => [GamePackGrain.teamMatch],
    GamePackRecipe.compare || GamePackRecipe.constant => [GamePackGrain.event],
    GamePackRecipe.latestNote ||
    GamePackRecipe.ballotRank ||
    GamePackRecipe.ballotScore => [GamePackGrain.team],
    _ => GamePackGrain.values,
  };

  Widget _check(String label, bool value, ValueChanged<bool> change) =>
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        onChanged: (checked) => setState(() => change(checked ?? false)),
      );
  Widget _text(
    String label,
    String value,
    ValueChanged<String> change, {
    bool number = false,
  }) => TextFormField(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    keyboardType: number ? TextInputType.number : TextInputType.text,
    onChanged: (text) => setState(() => change(text)),
  );

  @override
  Widget build(BuildContext context) {
    final target = _comparisonValue;
    final pct = double.tryParse(_threshold);
    final count = int.tryParse(_minimum);
    final trials = int.tryParse(_trials);
    final valid = switch (_op) {
      GamePackRecipe.compare =>
        pct != null && pct.isFinite && pct >= 0 && count != null && count > 0,
      GamePackRecipe.quantile =>
        target is num && target.isFinite && target >= 0 && target <= 1,
      GamePackRecipe.simulate =>
        trials != null && trials >= 1 && trials <= 1000,
      GamePackRecipe.constant =>
        target != null && (target is! num || target.isFinite),
      _ => !_comparison || target != null,
    };
    return BearingsModal(
      title: calculationStepTitle(widget.node),
      actions: const [],
      primaryAction: BearingsModalPrimaryAction(
        label: 'Save step',
        icon: LucideIcons.check,
        enabled: valid,
        onPressed: () => BearingsModal.complete(
          context,
          GamePackStepNode(
            id: widget.node.id,
            operation: _op,
            grain: _grain,
            inputs: widget.node.inputs,
            rowGrain: _row,
            scheduleRows: _schedule,
            missingAsZero: _counting == _Counting.missingZero,
            positiveOnly: _counting == _Counting.positive,
            condition: _condition,
            comparisonValue: target,
            threshold: (pct ?? 40) / 100,
            minimumReports: count ?? 3,
            qualificationsOnly: _qualifications,
            flaggedOnly: _flagged,
            fallbackToScouted: _fallback,
            requirePositiveOfficial: _positiveOfficial,
            singular: _singular,
            plural: _plural,
            trials: trials ?? 100,
          ),
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          if (_op == GamePackRecipe.constant)
            BearingsSelect<_LiteralType>(
              value: _literal,
              decoration: const InputDecoration(labelText: 'Type of value'),
              items: const [
                BearingsSelectItem(
                  value: _LiteralType.number,
                  child: Text('Number'),
                ),
                BearingsSelectItem(
                  value: _LiteralType.text,
                  child: Text('Text'),
                ),
                BearingsSelectItem(
                  value: _LiteralType.yesNo,
                  child: Text('Yes or no'),
                ),
              ],
              onChanged: (type) => setState(() => _literal = type!),
            ),
          if (_op == GamePackRecipe.constant ||
              _op == GamePackRecipe.quantile ||
              _comparison)
            _text(
              _op == GamePackRecipe.quantile
                  ? 'Percentile fraction (0–1)'
                  : _op == GamePackRecipe.constant
                  ? 'Value'
                  : 'Compare with',
              _value,
              (value) => _value = value,
              number:
                  _op == GamePackRecipe.quantile ||
                  _op == GamePackRecipe.constant &&
                      _literal == _LiteralType.number,
            ),
          if (_op == GamePackRecipe.condition)
            BearingsSelect<GamePackCondition>(
              value: _condition,
              decoration: const InputDecoration(labelText: 'Condition'),
              items: [
                for (final test in GamePackCondition.values)
                  BearingsSelectItem(value: test, child: Text(test.label)),
              ],
              onChanged: (test) => setState(() => _condition = test!),
            ),
          if ([
            GamePackRecipe.average,
            GamePackRecipe.sum,
            GamePackRecipe.rate,
            GamePackRecipe.add,
            GamePackRecipe.multiply,
            GamePackRecipe.any,
            GamePackRecipe.condition,
          ].contains(_op))
            BearingsSelect<_Counting>(
              value: _counting,
              decoration: const InputDecoration(
                labelText: 'Which values count?',
              ),
              items: [
                const BearingsSelectItem(
                  value: _Counting.reported,
                  child: Text('Reported values'),
                ),
                if (_op == GamePackRecipe.average)
                  const BearingsSelectItem(
                    value: _Counting.positive,
                    child: Text('Positive values only'),
                  ),
                BearingsSelectItem(
                  value: _Counting.missingZero,
                  child: Text(
                    [
                          GamePackRecipe.rate,
                          GamePackRecipe.any,
                          GamePackRecipe.condition,
                        ].contains(_op)
                        ? 'Treat missing as No'
                        : 'Treat missing as zero',
                  ),
                ),
              ],
              onChanged: (choice) => setState(() => _counting = choice!),
            ),
          if (_op == GamePackRecipe.scale) ...[
            _check(
              'Use scouted value when scaling is unavailable',
              _fallback,
              (value) => _fallback = value,
            ),
            _check(
              'Require a positive official value',
              _positiveOfficial,
              (value) => _positiveOfficial = value,
            ),
          ],
          if (_op == GamePackRecipe.compare) ...[
            _text(
              'Flag above difference (%)',
              _threshold,
              (value) => _threshold = value,
              number: true,
            ),
            _text(
              'Minimum team reports per alliance',
              _minimum,
              (value) => _minimum = value,
              number: true,
            ),
            _check(
              'Qualification matches only',
              _qualifications,
              (value) => _qualifications = value,
            ),
            _check(
              'Only include flagged matches',
              _flagged,
              (value) => _flagged = value,
            ),
          ],
          if (_op == GamePackRecipe.simulate)
            _text(
              'Number of trials',
              _trials,
              (value) => _trials = value,
              number: true,
            ),
          if (_op == GamePackRecipe.countLabel) ...[
            _text('Label for one', _singular, (value) => _singular = value),
            _text('Label for several', _plural, (value) => _plural = value),
          ],
          if (_scopes.length > 1 || _collection)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Data scope'),
              subtitle: Text(_grain.label),
              children: [
                if (_scopes.length > 1)
                  BearingsSelect<GamePackGrain>(
                    value: _grain,
                    decoration: const InputDecoration(
                      labelText: 'This step produces one value per',
                    ),
                    items: [
                      for (final scope in _scopes)
                        BearingsSelectItem(
                          value: scope,
                          child: Text(scope.label),
                        ),
                    ],
                    onChanged: (scope) => setState(() {
                      _grain = scope!;
                      if (_row?.canRead(_grain) == false) _row = null;
                    }),
                  ),
                if (_collection) ...[
                  BearingsSelect<GamePackGrain>(
                    key: ValueKey(_grain),
                    value: _row?.canRead(_grain) == true ? _row : null,

                    hint: const Text('Infer from inputs'),
                    decoration: const InputDecoration(
                      labelText: 'Combine values at',
                    ),
                    items: [
                      const BearingsSelectItem(
                        value: null,
                        child: Text('Infer from inputs'),
                      ),
                      for (final scope in GamePackGrain.values)
                        if (scope.canRead(_grain))
                          BearingsSelectItem(
                            value: scope,
                            child: Text(scope.label),
                          ),
                    ],
                    onChanged: (scope) => setState(() => _row = scope),
                  ),
                  _check(
                    'Include matches without scout reports',
                    _schedule,
                    (value) => _schedule = value,
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
