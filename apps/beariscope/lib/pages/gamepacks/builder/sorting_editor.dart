import 'package:core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../team_lookup/team_sorting.dart';
import '../gamepack_displays.dart';
import 'design.dart';
import 'fixture.dart';
import 'output_view.dart';
import 'result_picker.dart';

class GamePackSortingEditor extends StatefulWidget {
  const GamePackSortingEditor({
    super.key,
    required this.design,
    required this.fixture,
    required this.compact,
    required this.onChanged,
  });
  final GamePackDesign design;
  final GamePackBuilderFixture fixture;
  final bool compact;
  final ValueChanged<GamePackDesign> onChanged;
  @override
  State<GamePackSortingEditor> createState() => _GamePackSortingEditorState();
}

class _GamePackSortingEditorState extends State<GamePackSortingEditor> {
  String? _sortId;
  String _query = '';
  Set<String> _enabled = {};
  bool _searching = false;
  bool _showPreview = false;

  Future<void> _rule({
    required bool filter,
    GamePackTeamSort? sort,
    GamePackTeamFilter? existing,
  }) async {
    final design = widget.design;
    final output = sort?.output ?? existing?.output;
    final result = await BearingsModal.show<_TeamRuleDraft>(
      context,
      builder: (_) => _RuleEditor(
        filter: filter,
        design: design,
        output: output,
        label: sort?.label ?? existing?.label,
        ascending: sort?.ascending ?? false,
        rule: existing,
      ),
    );
    if (!mounted || result == null) return;
    final ids = [
      ...widget.design.results.sorts.map((value) => value.id),
      ...widget.design.results.filters.map((value) => value.id),
      ...widget.design.results.sheets.map((value) => value.id),
    ];
    final id =
        sort?.id ??
        existing?.id ??
        gamePackIdForName(result.label, ids, filter ? 'filter' : 'sort');
    if (filter) {
      final rule = GamePackTeamFilter(
        id: id,
        label: result.label,
        output: result.output,
        test: result.test,
        value: result.value,
      );
      widget.onChanged(
        widget.design.copyWith(
          filters: [
            for (final prior in widget.design.results.filters)
              if (prior.id == id) rule else prior,
            if (existing == null) rule,
          ],
        ),
      );
      setState(() => _enabled = {..._enabled, id});
    } else {
      final item = GamePackTeamSort(
        id: id,
        label: result.label,
        output: result.output,
        ascending: result.ascending,
      );
      widget.onChanged(
        widget.design.copyWith(
          sorts: [
            for (final prior in widget.design.results.sorts)
              if (prior.id == id) item else prior,
            if (sort == null) item,
          ],
        ),
      );
      setState(() => _sortId = id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final design = widget.design;
    final sorts = design.results.sorts;
    final filters = design.results.filters;
    final hasRules = sorts.isNotEmpty || filters.isNotEmpty;
    final session = widget.fixture.analysisFor(design);
    final selected = sorts.where((sort) => sort.id == _sortId).firstOrNull;
    final enabled = filters
        .where((rule) => _enabled.contains(rule.id))
        .toList();
    final original = {
      ...?widget.fixture.data?.teams,
      ...session.contexts(GamePackGrain.team).map((scope) => scope.team!),
    };
    final preview = original
        .where((team) => teamPassesFilters(session, team, enabled))
        .toList();
    final values = <String, GamePackValue>{
      if (selected != null)
        for (final team in preview)
          team: teamListValue(session, team, selected.output),
    };
    int number(String team) => int.tryParse(team.replaceFirst('frc', '')) ?? 0;
    preview.sort((a, b) {
      final bySort = selected == null
          ? 0
          : compareGamePackTeamValues(
              values[a]!,
              values[b]!,
              ascending: selected.ascending,
            );
      return bySort == 0 ? number(a).compareTo(number(b)) : bySort;
    });

    bool matches(String label, GameGraphOutputRef output) {
      final source = design.catalog.tryInfo(output);
      return matchesGamePackSearch(
        '$label ${source?.label ?? output.output}',
        _query,
      );
    }

    final visibleSorts = sorts
        .where((sort) => matches(sort.label, sort.output))
        .toList();
    final visibleFilters = filters
        .where((rule) => matches(rule.label, rule.output))
        .toList();

    final settings = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        Text(
          'Available in Team Lookup and Picklists.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text('Sort options', style: theme.textTheme.titleMedium),
        if (sorts.isEmpty) const Text('Add a field to the team sort menu.'),
        if (sorts.isNotEmpty && visibleSorts.isEmpty)
          const Text('No matching sorts.'),
        for (final sort in visibleSorts)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              sort.ascending
                  ? LucideIcons.arrowUpNarrowWide
                  : LucideIcons.arrowDownWideNarrow,
              size: 18,
            ),
            title: Text(sort.label),
            subtitle: switch (gamePackResultLabel(
              sort.output,
              design.catalog.tryInfo(sort.output),
            )) {
              final source when source != sort.label => Text(
                source,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              _ => null,
            },
            selected: selected == sort,
            onTap: () => _rule(filter: false, sort: sort),
            trailing: IconButton(
              tooltip: 'Remove ${sort.label}',
              icon: const Icon(LucideIcons.trash2, size: 17),
              onPressed: () => widget.onChanged(
                design.copyWith(
                  sorts: design.results.sorts
                      .where((item) => item.id != sort.id)
                      .toList(),
                ),
              ),
            ),
          ),
        const Divider(),
        Text('Filter options', style: theme.textTheme.titleMedium),
        if (filters.isEmpty)
          const Text('Add a condition people can turn on when browsing teams.'),
        if (filters.isNotEmpty && visibleFilters.isEmpty)
          const Text('No matching filters.'),
        for (final rule in visibleFilters)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.listFilter, size: 18),
            title: Text(rule.label),
            subtitle: Text(
              [
                gamePackResultLabel(
                  rule.output,
                  design.catalog.tryInfo(rule.output),
                ),
                rule.test.label.toLowerCase(),
                if (rule.test.needsValue)
                  formatGamePackValue(GamePackValue.of(rule.value)),
              ].join(' '),
            ),
            onTap: () => _rule(filter: true, existing: rule),
            trailing: IconButton(
              tooltip: 'Remove ${rule.label}',
              icon: const Icon(LucideIcons.trash2, size: 17),
              onPressed: () => widget.onChanged(
                design.copyWith(
                  filters: design.results.filters
                      .where((item) => item.id != rule.id)
                      .toList(),
                ),
              ),
            ),
          ),
      ],
    );

    final sample = Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Text('Team list preview', style: theme.textTheme.titleMedium),
            Text('Test data', style: theme.textTheme.bodySmall),
            if (sorts.isNotEmpty)
              BearingsSelect<String>(
                key: ValueKey(selected?.id),
                value: selected?.id ?? '',
                decoration: const InputDecoration(labelText: 'Preview sort'),
                items: [
                  const BearingsSelectItem(
                    value: '',
                    child: Text('Team number'),
                  ),
                  for (final sort in sorts)
                    BearingsSelectItem(value: sort.id, child: Text(sort.label)),
                ],
                onChanged: (value) => setState(() => _sortId = value),
              ),
            if (filters.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 5,
                children: [
                  for (final rule in filters)
                    FilterChip(
                      label: Text(rule.label),
                      selected: _enabled.contains(rule.id),
                      onSelected: (yes) => setState(() {
                        _enabled = {..._enabled};
                        if (yes) {
                          _enabled.add(rule.id);
                        } else {
                          _enabled.remove(rule.id);
                        }
                      }),
                    ),
                ],
              ),
            Text(
              '${preview.length} of ${original.length} teams',
              style: theme.textTheme.labelMedium,
            ),
            for (final team in preview.take(12))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.fixture.data?.teamLabel(team) ??
                      'Team ${team.replaceFirst('frc', '')}',
                ),
                trailing: values[team] == null
                    ? null
                    : Text(formatGamePackValue(values[team]!)),
              ),
            if (preview.isEmpty) const Text('No teams match this preview.'),
          ],
        ),
      ),
    );

    Widget panel(Widget content) => ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [content],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= 740;
        final previewing = hasRules && !split && _showPreview;
        void toggleSearch() => setState(() {
          _searching = !_searching;
          _query = '';
        });
        final searchButton = IconButton(
          tooltip: _searching ? 'Close search' : 'Find a sort or filter',
          icon: Icon(_searching ? LucideIcons.x : LucideIcons.search),
          onPressed: toggleSearch,
        );
        return GamePackOutputView(
          title: 'Sorting & filters',
          compact: widget.compact,
          stackActions: !split,
          modeSwitcher: hasRules && !split
              ? GamePackEditPreviewSwitcher(
                  previewing: previewing,
                  onChanged: (value) => setState(() {
                    _showPreview = value;
                    _searching = false;
                    _query = '';
                  }),
                )
              : null,
          tools: [if (hasRules && split) searchButton],
          actionTools: [if (hasRules && !split && !previewing) searchButton],
          actions: [
            if (!previewing)
              for (final (filter, label) in [
                (false, 'Add sort'),
                (true, 'Add filter'),
              ])
                OutlinedButton.icon(
                  onPressed: () => _rule(filter: filter),
                  style: split
                      ? null
                      : OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                  icon: const Icon(LucideIcons.plus, size: 17),
                  label: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          ],
          search: hasRules && _searching && !previewing
              ? TextField(
                  autofocus: true,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(LucideIcons.search, size: 18),
                    labelText: 'Find a sort or filter',
                    suffixIcon: split ? null : searchButton,
                  ),
                )
              : null,
          child: !hasRules
              ? const GamePackOutputEmpty(
                  icon: LucideIcons.listFilter,
                  title: 'No sorts or filters yet',
                  description: 'Add sorting and filtering options for Team Lookup and Picklists.',
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: SizedBox.expand(
                      child: split
                          ? Row(
                              spacing: 24,
                              children: [
                                Expanded(child: panel(settings)),
                                Expanded(child: panel(sample)),
                              ],
                            )
                          : panel(previewing ? sample : settings),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

typedef _TeamRuleDraft = ({
  String label,
  GameGraphOutputRef output,
  GamePackFilterTest test,
  Object? value,
  bool ascending,
});

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({
    required this.filter,
    required this.design,
    required this.output,
    required this.label,
    required this.ascending,
    required this.rule,
  });
  final bool filter;
  final GamePackDesign design;
  final GameGraphOutputRef? output;
  final String? label;
  final bool ascending;
  final GamePackTeamFilter? rule;
  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late final _name = TextEditingController(text: widget.label ?? '');
  late GameGraphOutputRef? _output = widget.output;
  late GamePackFilterTest _test =
      widget.rule?.test ?? GamePackFilterTest.reported;
  late String _operand = widget.rule?.value?.toString() ?? '';
  late bool _ascending = widget.ascending;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _field() async {
    final ref = await pickGamePackResult(
      context,
      title: 'Choose a team field',
      preferredScope: GamePackGrain.team,
      questionPaths: widget.design.questionPaths,
      options: {
        for (final entry in widget.design.catalog.catalog.entries)
          if (GamePackGrain.team.canRead(
                entry.value.grain ?? GamePackGrain.event,
              ) &&
              (widget.filter || GamePackCardMetric.supports(entry.value.type)))
            entry.key: entry.value,
      },
    );
    if (!mounted || ref == null) return;
    setState(() {
      _output = ref;
      final info = widget.design.catalog.resultInfo(ref);
      if (_name.text.isEmpty) _name.text = info.label;
      if (!_test.supports(info.type)) _test = GamePackFilterTest.reported;
      _operand = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final ref = _output;
    final info = ref == null ? null : widget.design.catalog.tryInfo(ref);
    final type = info?.type;
    final label = _name.text.trim();
    final value = switch (type?.kind) {
      GamePackTypeKind.number => num.tryParse(_operand.trim()),
      GamePackTypeKind.integer => int.tryParse(_operand.trim()),
      GamePackTypeKind.boolean =>
        _operand == 'true'
            ? true
            : _operand == 'false'
            ? false
            : null,
      _ => _operand.trim().isEmpty ? null : _operand.trim(),
    };
    final ready =
        label.isNotEmpty &&
        label.length <= 80 &&
        info != null &&
        (!widget.filter ||
            !_test.needsValue ||
            value != null && type!.acceptsValue(GamePackValue.of(value)));
    return BearingsModal(
      title: widget.filter ? 'Team filter' : 'Team sort',
      actions: const [],
      primaryAction: BearingsModalPrimaryAction(
        label: widget.filter ? 'Save filter' : 'Save sort',
        icon: LucideIcons.check,
        enabled: ready,
        onPressed: () => BearingsModal.complete(context, (
          label: label,
          output: ref!,
          test: _test,
          value: value,
          ascending: _ascending,
        )),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 9,
        children: [
          OutlinedButton.icon(
            onPressed: _field,
            icon: const Icon(LucideIcons.listChecks, size: 17),
            label: Text(info?.label ?? 'Choose field'),
          ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Menu label'),
            onChanged: (_) => setState(() {}),
          ),
          if (!widget.filter)
            BearingsSelect<bool>(
              value: _ascending,
              decoration: const InputDecoration(labelText: 'Default order'),
              items: const [
                BearingsSelectItem(
                  value: false,
                  child: Text('Highest first / Z–A'),
                ),
                BearingsSelectItem(
                  value: true,
                  child: Text('Lowest first / A–Z'),
                ),
              ],
              onChanged: (value) => setState(() => _ascending = value ?? false),
            ),
          if (widget.filter && type != null)
            BearingsSelect<GamePackFilterTest>(
              key: ValueKey((ref, _test)),
              value: _test,
              decoration: const InputDecoration(labelText: 'Condition'),
              items: [
                for (final choice in GamePackFilterTest.values)
                  if (choice.supports(type))
                    BearingsSelectItem(
                      value: choice,
                      child: Text(choice.label),
                    ),
              ],
              onChanged: (test) {
                if (test != null) setState(() => _test = test);
              },
            ),
          if (widget.filter && type != null && _test.needsValue)
            if (type == GamePackType.boolean)
              BearingsSelect<String>(
                key: ValueKey(ref),
                value: _operand.isEmpty ? null : _operand,
                decoration: const InputDecoration(labelText: 'Compare with'),
                items: const [
                  BearingsSelectItem(value: 'true', child: Text('Yes')),
                  BearingsSelectItem(value: 'false', child: Text('No')),
                ],
                onChanged: (value) => setState(() => _operand = value ?? ''),
              )
            else
              TextFormField(
                key: ValueKey(ref),
                initialValue: _operand,
                decoration: const InputDecoration(labelText: 'Compare with'),
                keyboardType: GamePackType.number.accepts(type)
                    ? TextInputType.number
                    : null,
                onChanged: (value) => setState(() => _operand = value),
              ),
        ],
      ),
    );
  }
}
