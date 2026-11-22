import 'package:core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/widgets/bearings_modal.dart';

import 'design.dart';

typedef GamePackPathOption = ({
  String path,
  String label,
  GamePackType? declaredType,
  GamePackValue? sample,
});

/// Use the declared structure even when the test data has no rows or answers.
/// Use sample values to fill in otherwise opaque TBA objects and list indices.
List<GamePackPathOption> gamePackPathOptions({
  GamePackType? type,
  GamePackValue? sample,
  Iterable<GamePackField> fields = const [],
}) {
  final fieldLabels = {for (final field in fields) field.id: field.label};
  final options = <GamePackPathOption>[];

  void visit(
    GamePackType? type,
    GamePackValue? value,
    String path,
    String label,
    int depth,
  ) {
    if (depth > 16 || options.length >= 1200) return;
    if (path.isNotEmpty) {
      options.add((
        path: path,
        label: label,
        declaredType: type,
        sample: value,
      ));
    }
    final object = value?.data;
    final values = object is Map<String, GamePackValue>
        ? object
        : const <String, GamePackValue>{};
    final keys = type?.kind == GamePackTypeKind.record
        ? type!.fields.keys
        : values.keys;
    for (final key in keys) {
      if (key.isEmpty || key.contains('.')) continue;
      final childLabel = path == 'answers' || path.endsWith('.answers')
          ? fieldLabels[key] ?? gamePackKeyLabel(key)
          : gamePackKeyLabel(key);
      visit(
        type?.fields[key],
        values[key],
        path.isEmpty ? key : '$path.$key',
        label.isEmpty ? childLabel : '$label › $childLabel',
        depth + 1,
      );
    }
    if (object is List<GamePackValue> || type?.kind == GamePackTypeKind.list) {
      final rows = object is List<GamePackValue>
          ? object
          : const <GamePackValue>[];
      for (
        var index = 0;
        index < (rows.isEmpty ? 1 : rows.length) && index < 32;
        index++
      ) {
        visit(
          type?.element,
          rows.isEmpty ? null : rows[index],
          path.isEmpty ? '$index' : '$path.$index',
          label.isEmpty ? 'Item ${index + 1}' : '$label › Item ${index + 1}',
          depth + 1,
        );
      }
    }
  }

  visit(type, sample, '', '', 0);
  return options;
}

Future<GamePackPathOption?> pickGamePackPath(
  BuildContext context, {
  required String title,
  required Iterable<GamePackPathOption> options,
}) => BearingsModal.show<GamePackPathOption>(
  context,
  builder: (_) => _PathPicker(title: title, options: options),
);

class _PathPicker extends StatefulWidget {
  const _PathPicker({required this.title, required this.options});
  final String title;
  final Iterable<GamePackPathOption> options;

  @override
  State<_PathPicker> createState() => _PathPickerState();
}

class _PathPickerState extends State<_PathPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final matches = widget.options
        .where(
          (item) =>
              item.label.toLowerCase().contains(_query) ||
              item.path.toLowerCase().contains(_query),
        )
        .toList();
    return BearingsModal(
      title: widget.title,
      actions: const [],
      scrolling: BearingsModalScrolling.content,
      size: BearingsModalSize.tall,
      content: SizedBox(
        width: 510,
        height: 340,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search fields',
                prefixIcon: Icon(LucideIcons.search),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            if (matches.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  widget.options.isEmpty
                      ? 'No fields are available.'
                      : 'No matching fields.',
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final item = matches[index];
                    final sample = item.sample?.data;
                    final detail = switch (sample) {
                      final num value => '$value',
                      final String value => value,
                      final bool value => '$value',
                      final List<GamePackValue> values =>
                        '${values.length} items',
                      final Map<String, GamePackValue> fields =>
                        '${fields.length} fields',
                      _ => item.declaredType?.kind.name,
                    };
                    return ListTile(
                      dense: true,
                      title: Text(item.label),
                      subtitle: detail == null
                          ? null
                          : Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: const Icon(LucideIcons.chevronRight, size: 16),
                      onTap: () => BearingsModal.complete(context, item),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
