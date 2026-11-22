import 'package:core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/widgets/bearings_modal.dart';

import 'design.dart';

typedef GamePackOptions = Map<GameGraphOutputRef, GamePackResultInfo>;

Future<GameGraphOutputRef?> pickGamePackResult(
  BuildContext context, {
  required String title,
  required GamePackOptions options,
  GamePackGrain? preferredScope,
  Map<String, String> questionPaths = const {},
}) => BearingsModal.show<GameGraphOutputRef>(
  context,
  builder: (_) => _ResultPicker(
    title: title,
    options: options,
    preferredScope: preferredScope,
    questionPaths: questionPaths,
  ),
);

class _ResultPicker extends StatefulWidget {
  const _ResultPicker({
    required this.title,
    required this.options,
    this.preferredScope,
    required this.questionPaths,
  });

  final String title;
  final GamePackOptions options;
  final GamePackGrain? preferredScope;
  final Map<String, String> questionPaths;

  @override
  State<_ResultPicker> createState() => _ResultPickerState();
}

class _ResultPickerState extends State<_ResultPicker> {
  String _query = '';
  String? _field;

  @override
  Widget build(BuildContext context) {
    final groups =
        <String, List<MapEntry<GameGraphOutputRef, GamePackResultInfo>>>{};
    for (final item in widget.options.entries) {
      final group = gamePackRollupOf(item.key.output)?.field ?? item.key.output;
      groups.putIfAbsent(group, () => []).add(item);
    }
    final choices = groups.entries
        .where(
          (entry) => entry.value.any((item) {
            final path = widget.questionPaths[entry.key] ?? '';
            final words =
                '${gamePackResultLabel(item.key, item.value)} '
                '${gamePackResultDetail(item.value)} $path ${entry.key}';
            return matchesGamePackSearch(words, _query);
          }),
        )
        .toList();
    final selected = groups[_field];
    return BearingsModal(
      title: widget.title,
      actions: const [],
      size: BearingsModalSize.tall,
      scrolling: BearingsModalScrolling.content,
      content: SizedBox(
        width: 500,
        height: 340,
        child: Column(
          children: [
            if (selected == null)
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(LucideIcons.search),
                  labelText: 'Search questions and metrics',
                ),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: IconButton(
                  tooltip: 'Back to results',
                  icon: const Icon(LucideIcons.arrowLeft),
                  onPressed: () => setState(() => _field = null),
                ),
                title: Text(
                  widget.questionPaths[_field] ?? selected.first.value.label,
                ),
              ),
            Expanded(
              child: selected != null
                  ? ListView(
                      children: [
                        for (final entry in selected)
                          ListTile(
                            title: Text(
                              gamePackRollupOf(entry.key.output)
                                      ?.rollup
                                      .label ??
                                  'This match',
                            ),
                            subtitle: Text(entry.value.grain?.label ?? ''),
                            trailing:
                                entry.value.grain == widget.preferredScope &&
                                    widget.preferredScope != null
                                ? const Icon(LucideIcons.star, size: 16)
                                : const Icon(
                                    LucideIcons.chevronRight,
                                    size: 16,
                                  ),
                            onTap: () =>
                                BearingsModal.complete(context, entry.key),
                          ),
                      ],
                    )
                  : choices.isEmpty
                  ? const Center(child: Text('No results match your search.'))
                  : ListView.builder(
                      itemCount: choices.length,
                      itemBuilder: (context, index) {
                        final entry = choices[index];
                        final first = entry.value.first;
                        return ListTile(
                          title: Text(
                            gamePackResultLabel(first.key, first.value),
                          ),
                          subtitle: Text(
                            widget.questionPaths[entry.key] ??
                                (entry.value.length > 1
                                    ? 'Match value or event summary'
                                    : gamePackResultDetail(first.value)),
                          ),
                          trailing: const Icon(
                            LucideIcons.chevronRight,
                            size: 16,
                          ),
                          onTap: () {
                            if (entry.value.length == 1) {
                              BearingsModal.complete(context, first.key);
                            } else {
                              setState(() => _field = entry.key);
                            }
                          },
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
