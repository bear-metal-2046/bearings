import 'package:core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import 'design.dart';

Future<GamePackType?> pickGamePackType(
  BuildContext context, {
  GamePackType? initial,
  Iterable<GamePackType> types = const [],
}) => BearingsModal.show<GamePackType>(
  context,
  builder: (_) => _TypePicker(initial: initial, types: types),
);

class _TypePicker extends StatefulWidget {
  const _TypePicker({required this.initial, required this.types});
  final GamePackType? initial;
  final Iterable<GamePackType> types;

  @override
  State<_TypePicker> createState() => _TypePickerState();
}

class _TypePickerState extends State<_TypePicker> {
  late GamePackType _type = widget.initial ?? GamePackType.number;

  Future<void> _collection(bool distribution) async {
    final chosen = await pickGamePackType(
      context,
      initial: _type.element,
      types: widget.types,
    );
    if (!mounted || chosen == null) return;
    setState(
      () => _type = distribution
          ? GamePackType.distribution(chosen)
          : GamePackType.list(chosen),
    );
  }

  Future<void> _record() async {
    final result = await BearingsModal.show<GamePackType>(
      context,
      builder: (_) =>
          _RecordTypeDialog(fields: _type.fields, types: widget.types),
    );
    if (mounted && result != null) setState(() => _type = result);
  }

  @override
  Widget build(BuildContext context) {
    final choices = {
      GamePackType.number,
      GamePackType.integer,
      GamePackType.boolean,
      GamePackType.text,
      GamePackType.json,
      GamePackType.any,
      ...widget.types,
      _type,
    };
    return BearingsModal(
      title: 'Choose a port type',
      actions: const [],
      primaryAction: BearingsModalPrimaryAction(
        label: 'Use type',
        icon: LucideIcons.check,
        onPressed: () => BearingsModal.complete(context, _type),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BearingsSelect<GamePackType>(
            value: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final type in choices)
                BearingsSelectItem(
                  value: type,
                  child: Text('$type', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (type) => setState(() => _type = type ?? _type),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton(
                onPressed: () => _collection(false),
                child: const Text('List type'),
              ),
              OutlinedButton(
                onPressed: () => _collection(true),
                child: const Text('Distribution type'),
              ),
              OutlinedButton(
                onPressed: _record,
                child: const Text('Record type'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordTypeDialog extends StatefulWidget {
  const _RecordTypeDialog({required this.fields, required this.types});
  final Map<String, GamePackType> fields;
  final Iterable<GamePackType> types;

  @override
  State<_RecordTypeDialog> createState() => _RecordTypeDialogState();
}

class _RecordTypeDialogState extends State<_RecordTypeDialog> {
  late final _fields = Map<String, GamePackType>.of(widget.fields);

  Future<void> _add() async {
    final name = await askGamePackName(
      context,
      label: 'Record field name',
      used: _fields.keys,
      fallback: 'field',
    );
    if (!mounted || name == null) return;
    final type = await pickGamePackType(context, types: widget.types);
    if (mounted && type != null) setState(() => _fields[name] = type);
  }

  @override
  Widget build(BuildContext context) => BearingsModal(
    title: 'Record fields',
    actions: const [],
    primaryAction: BearingsModalPrimaryAction(
      label: 'Save record type',
      icon: LucideIcons.check,
      onPressed: () =>
          BearingsModal.complete(context, GamePackType.record(_fields)),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in _fields.entries)
          ListTile(
            title: Text(entry.key),
            subtitle: Text('${entry.value}'),
            trailing: IconButton(
              tooltip: 'Remove ${entry.key}',
              icon: const Icon(LucideIcons.trash2),
              onPressed: () => setState(() => _fields.remove(entry.key)),
            ),
          ),
        OutlinedButton(onPressed: _add, child: const Text('Add record field')),
      ],
    ),
  );
}

Future<String?> askGamePackName(
  BuildContext context, {
  required String label,
  required Iterable<String> used,
  required String fallback,
}) => BearingsModal.show<String>(
  context,
  builder: (_) =>
      _NameDialog(label: label, used: used.toSet(), fallback: fallback),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.label,
    required this.used,
    required this.fallback,
  });
  final String label;
  final Set<String> used;
  final String fallback;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  String _value = '';
  String? _error;

  void _accept() {
    try {
      validateGamePackLabel(_value);
      Navigator.pop(
        context,
        gamePackIdForName(_value, widget.used, widget.fallback),
      );
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => BearingsModal(
    title: widget.label,
    actions: const [],
    primaryAction: BearingsModalPrimaryAction(
      label: 'Add',
      icon: LucideIcons.plus,
      onPressed: _accept,
    ),
    content: TextField(
      autofocus: true,
      onChanged: (value) => _value = value.trim(),
      onSubmitted: (_) => _accept(),
      decoration: InputDecoration(labelText: widget.label, errorText: _error),
    ),
  );
}
