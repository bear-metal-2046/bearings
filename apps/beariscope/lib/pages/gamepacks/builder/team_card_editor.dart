import 'package:core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../team_card_content.dart';
import 'analysis_editor.dart';
import 'design.dart';
import 'fixture.dart';
import 'output_view.dart';
import 'team_card_block_editor.dart';

typedef GamePackCardEdit = ({
  GamePackTeamCardLayout layout,
  List<GamePackCalculation> calculations,
});

class GamePackTeamCardEditor extends StatefulWidget {
  const GamePackTeamCardEditor({
    super.key,
    required this.kind,
    required this.design,
    required this.fixture,
    required this.compact,
    required this.onChanged,
  });

  final GamePackTeamCardKind kind;
  final GamePackDesign design;
  final GamePackBuilderFixture fixture;
  final bool compact;
  final ValueChanged<GamePackCardEdit> onChanged;

  @override
  State<GamePackTeamCardEditor> createState() => _GamePackTeamCardEditorState();
}

class _GamePackTeamCardEditorState extends State<GamePackTeamCardEditor>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(GamePackTeamCardEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _design = widget.design;
  }

  void _changed() =>
      widget.onChanged((layout: _layout, calculations: _design.calculations));

  late List<GamePackCardSection> _sections =
      widget.design.teamCards
          .where((card) => card.kind == widget.kind)
          .firstOrNull
          ?.sections
          .toList() ??
      [GamePackCardSection(id: 'overview', blocks: const [])];
  bool _showPreview = false;

  late GamePackDesign _design = widget.design;

  GamePackOptions get _options => {
    for (final entry in _design.catalog.catalog.entries)
      if (entry.value.grain == null ||
          GamePackGrain.team.canRead(entry.value.grain!))
        entry.key: entry.value,
  };

  Map<GameGraphOutputRef, GamePackType> get _outputs => {
    for (final entry in _options.entries) entry.key: entry.value.type,
  };

  Future<void> _newMetric(int index) async {
    final recipe = await editGamePackCalculation(
      context,
      design: _design,
      fixture: widget.fixture,
      scope: GamePackGrain.team,
    );
    if (!mounted || recipe == null) return;
    final draft = withGamePackCalculation(_design, recipe);
    final ref = gamePackFieldRef(recipe.id);
    final output = draft.catalog.resultInfo(ref);
    setState(() => _design = draft);
    if (!GamePackCardMetric.supports(output.type)) return;
    final section = _sections[index];
    _setBlocks(index, [
      ...section.blocks,
      GamePackCardBlock(
        id: availableId('metric', section.blocks.map((block) => block.id)),
        kind: GamePackCardBlockKind.metrics,
        metrics: [GamePackCardMetric(label: recipe.label, output: ref)],
      ),
    ]);
  }

  Future<void> _newTrend(int index) async {
    final section = _sections[index];
    final created =
        await BearingsModal.show<
          ({GamePackCalculation recipe, GamePackCardBlock block})
        >(
          context,
          builder: (_) => _MatchTrendEditor(
            design: _design,
            id: availableId('trend', section.blocks.map((block) => block.id)),
          ),
        );
    if (!mounted || created == null) return;
    setState(() => _design = withGamePackCalculation(_design, created.recipe));
    _setBlocks(index, [..._sections[index].blocks, created.block]);
  }

  GamePackTeamCardLayout get _layout => GamePackTeamCardLayout(
    kind: widget.kind,
    sections: _sections.where((section) => section.blocks.isNotEmpty).toList(),
  );

  Future<void> _section([int? index]) async {
    final current = index == null ? null : _sections[index];
    final title = await BearingsModal.show<String>(
      context,
      builder: (_) => _SectionName(initial: current?.title ?? ''),
    );
    if (!mounted || title == null) return;
    final section = GamePackCardSection(
      id:
          current?.id ??
          gamePackIdForName(title, _sections.map((item) => item.id), 'section'),
      title: title,
      blocks: current?.blocks ?? const [],
    );
    setState(
      () => _sections = index == null
          ? [..._sections, section]
          : replaceAt(_sections, index, section),
    );
    _changed();
  }

  void _setBlocks(int index, List<GamePackCardBlock> blocks) {
    final section = _sections[index];
    setState(
      () => _sections = replaceAt(
        _sections,
        index,
        GamePackCardSection(
          id: section.id,
          title: section.title,
          blocks: blocks,
        ),
      ),
    );
    _changed();
  }

  Future<void> _addBlock(int index) async {
    final outputs = _outputs;
    final action = await BearingsModal.show<Future<void> Function()>(
      context,
      builder: (context) => BearingsModal(
        title: 'Add block',
        actions: const [],
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final kind in GamePackCardBlockKind.values)
              if (kind != GamePackCardBlockKind.table ||
                  widget.kind == GamePackTeamCardKind.details)
                ListTile(
                  leading: Icon(cardBlockIcon(kind)),
                  title: Text(kind.label),
                  enabled: switch (kind) {
                    GamePackCardBlockKind.eventRank => true,
                    GamePackCardBlockKind.table => outputs.values.any(
                      GamePackCardTable.supports,
                    ),
                    GamePackCardBlockKind.trend => outputs.values.any(
                      GamePackCardChart.supports,
                    ),
                    _ => outputs.values.any(GamePackCardMetric.supports),
                  },
                  onTap: () => BearingsModal.complete(
                    context,
                    () => _block(index, kind),
                  ),
                ),
            const Divider(),
            ListTile(
              leading: const Icon(LucideIcons.calculator),
              title: const Text('Create metric'),
              onTap: () =>
                  BearingsModal.complete(context, () => _newMetric(index)),
            ),
            ListTile(
              leading: const Icon(LucideIcons.trendingUp),
              title: const Text('Build match trend'),
              onTap: () =>
                  BearingsModal.complete(context, () => _newTrend(index)),
            ),
          ],
        ),
      ),
    );
    if (mounted && action != null) await action();
  }

  Future<void> _block(
    int sectionIndex,
    GamePackCardBlockKind kind, [
    GamePackCardBlock? current,
  ]) async {
    final section = _sections[sectionIndex];
    final result = await BearingsModal.show<GamePackCardBlock>(
      context,
      builder: (_) => GamePackCardBlockEditor(
        kind: kind,
        current: current,
        id:
            current?.id ??
            availableId('block', section.blocks.map((block) => block.id)),
        outputs: _outputs,
        options: _options,
        questionPaths: _design.questionPaths,
      ),
    );
    if (!mounted || result == null) return;
    _setBlocks(
      sectionIndex,
      current == null
          ? [...section.blocks, result]
          : replaceAt(section.blocks, section.blocks.indexOf(current), result),
    );
  }

  void _moveSection(int from, int to) {
    setState(() => _sections = _move(_sections, from, to));
    _changed();
  }

  bool get _details => widget.kind == GamePackTeamCardKind.details;

  Widget _edit() {
    if (!_details && _sections.first.blocks.isEmpty) {
      return const GamePackOutputEmpty(
        icon: LucideIcons.contact,
        title: 'No blocks yet',
        description: 'Add the most useful scouting values to the card teammates see in team lists.',
      );
    }
    if (_sections.isEmpty) {
      return const GamePackOutputEmpty(
        icon: LucideIcons.layoutDashboard,
        title: 'No sections yet',
        description: 'Add a section to group metrics, trends, and other scouting details.',
      );
    }
    return ListView(
      primary: false,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final (i, section) in _sections.indexed) ...[
          if (i > 0) const Divider(height: 28),
          if (_details)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                section.title ?? 'Overview',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: () => _section(i),
              trailing: BearingsPopupMenu.overflow(
                tooltip: 'Section options',
                menuChildren: [
                  for (final (offset, label) in [
                    (-1, 'Move section up'),
                    (1, 'Move section down'),
                  ])
                    if (i + offset >= 0 && i + offset < _sections.length)
                      BearingsMenuItem(
                        onPressed: () => _moveSection(i, i + offset),
                        child: Text(label),
                      ),
                  BearingsMenuItem(
                    onPressed: () => _section(i),
                    child: const Text('Rename section'),
                  ),
                  BearingsMenuItem(
                    onPressed: () {
                      setState(() => _sections = [..._sections]..removeAt(i));
                      _changed();
                    },
                    destructive: true,
                    child: const Text('Remove section'),
                  ),
                ],
              ),
            ),
          ReorderableListView.builder(
            primary: false,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: section.blocks.length,
            onReorderItem: (from, to) =>
                _setBlocks(i, _move(section.blocks, from, to)),
            itemBuilder: (context, index) {
              final block = section.blocks[index];
              return ListTile(
                key: ValueKey(block.id),
                contentPadding: EdgeInsets.zero,
                leading: ReorderableDragStartListener(
                  index: index,
                  child: const Tooltip(
                    message: 'Drag to reorder block',
                    child: Icon(LucideIcons.gripVertical),
                  ),
                ),
                title: Text(block.title ?? block.kind.label),
                subtitle: block.metrics.isEmpty
                    ? null
                    : Text(
                        block.metrics.map((metric) => metric.label).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                onTap: () => _block(i, block.kind, block),
                trailing: IconButton(
                  tooltip: 'Remove ${block.title ?? block.kind.label}',
                  icon: const Icon(LucideIcons.trash2, size: 17),
                  onPressed: () =>
                      _setBlocks(i, [...section.blocks]..removeAt(index)),
                ),
              );
            },
          ),
          if (_details && section.blocks.length < 24)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _addBlockButton(i, sectionId: section.id),
            ),
        ],
      ],
    );
  }

  Widget _addBlockButton(int index, {String? sectionId}) => OutlinedButton.icon(
    key: sectionId == null ? null : ValueKey(('add-card-block', sectionId)),
    onPressed: _sections[index].blocks.length < 24
        ? () => _addBlock(index)
        : null,
    icon: const Icon(LucideIcons.plus, size: 17),
    label: const Text('Add block'),
  );

  Widget _preview() {
    final layout = _layout;
    final team = widget.fixture.scope.team;
    return ListView(
      primary: false,
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      children: [
        Text(
          'Test data',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        if (layout.sections.isEmpty)
          const ListTile(title: Text('Add a block to preview this card.'))
        else if (team == null)
          const ListTile(
            title: Text('Choose a preview team in Edit test data.'),
          )
        else
          _renderPreview(layout, team),
      ],
    );
  }

  Widget _renderPreview(GamePackTeamCardLayout layout, String team) {
    try {
      final catalog = _design.catalog;
      layout.validate(catalog);
      final fixture = widget.fixture;
      final session = fixture.analysisFor(_design);
      final scope = GamePackScope(event: fixture.event, team: team);
      GamePackValue value(GameGraphOutputRef output) =>
          session.evaluate(output, scope: scope).result;
      final blocks = layout.sections.expand((section) => section.blocks);
      for (final block in blocks) {
        for (final metric in block.metrics) {
          value(metric.output);
        }
        if (block.chart case final chart?) value(chart.output);
        if (block.table case final table?) value(table.output);
      }
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.kind == GamePackTeamCardKind.compact ? 420 : 620,
          ),
          child: Card.filled(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  Text(
                    fixture.data?.teamLabel(team) ??
                        'Team ${team.replaceFirst('frc', '')}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  GamePackTeamCardContent(
                    layout: layout,
                    output: value,
                    rank: gamePackEventRank(fixture.data?.rankings, team),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } on FormatException catch (error) {
      return ListTile(
        title: const Text('Preview unavailable'),
        subtitle: Text(error.message),
      );
    } on ArgumentError catch (error) {
      return ListTile(
        title: const Text('Preview unavailable'),
        subtitle: Text(
          error.message?.toString() ?? 'The preview data has a different type.',
        ),
      );
    } on GameGraphLimitExceeded catch (error) {
      return ListTile(
        title: const Text('Preview unavailable'),
        subtitle: Text(error.message),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= 740;
        final previewing = !split && _showPreview;
        return GamePackOutputView(
          title: _details ? 'Team details' : 'Team card',
          compact: widget.compact,
          stackActions: !split,
          modeSwitcher: split
              ? null
              : GamePackEditPreviewSwitcher(
                  previewing: previewing,
                  onChanged: (value) => setState(() => _showPreview = value),
                ),
          actions: [
            if (!previewing)
              if (_details)
                OutlinedButton.icon(
                  onPressed: _sections.length < 12 ? _section : null,
                  icon: const Icon(LucideIcons.plus, size: 17),
                  label: const Text('Add section'),
                )
              else
                _addBlockButton(0),
          ],
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: SizedBox.expand(
                child: split
                    ? Row(
                        children: [
                          Expanded(child: _edit()),
                          const VerticalDivider(width: 32),
                          Expanded(child: _preview()),
                        ],
                      )
                    : previewing
                    ? _preview()
                    : _edit(),
              ),
            ),
          ),
        );
      },
    );
  }
}

List<T> _move<T>(List<T> items, int from, int to) {
  final result = items.toList();
  result.insert(to, result.removeAt(from));
  return result;
}

class _SectionName extends StatefulWidget {
  const _SectionName({required this.initial});
  final String initial;

  @override
  State<_SectionName> createState() => _SectionNameState();
}

class _SectionNameState extends State<_SectionName> {
  late String _title = widget.initial.trim();

  @override
  Widget build(BuildContext context) => BearingsModal(
    title: 'Card section',
    actions: const [],
    primaryAction: BearingsModalPrimaryAction(
      label: 'Save section',
      icon: LucideIcons.check,
      enabled: _title.isNotEmpty && _title.length <= 80,
      onPressed: () => BearingsModal.complete(context, _title),
    ),
    content: TextFormField(
      initialValue: widget.initial,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Section title'),
      onChanged: (value) => setState(() => _title = value.trim()),
    ),
  );
}

class _MatchTrendEditor extends StatefulWidget {
  const _MatchTrendEditor({required this.design, required this.id});
  final GamePackDesign design;
  final String id;

  @override
  State<_MatchTrendEditor> createState() => _MatchTrendEditorState();
}

class _MatchTrendEditorState extends State<_MatchTrendEditor> {
  String _title = 'By match';
  final _series = <GameGraphOutputRef>[];
  final _markers = <GameGraphOutputRef>[];
  bool _schedule = false;
  late final _catalog = widget.design.catalog.catalog;

  Future<void> _add(bool marker) async {
    final values = marker ? _markers : _series;
    final field = await pickGamePackResult(
      context,
      title: marker ? 'Choose a match marker' : 'Choose a match value',
      questionPaths: widget.design.questionPaths,
      options: {
        for (final entry in _catalog.entries)
          if (entry.value.grain != null &&
              [
                GamePackGrain.teamMatch,
                GamePackGrain.allianceMatch,
                GamePackGrain.match,
              ].contains(entry.value.grain) &&
              (marker
                  ? entry.value.type == GamePackType.boolean
                  : GamePackType.number.accepts(entry.value.type)) &&
              !values.contains(entry.key))
            entry.key: entry.value,
      },
    );
    if (mounted && field != null) setState(() => values.add(field));
  }

  String _label(GameGraphOutputRef ref) =>
      gamePackResultLabel(ref, _catalog[ref]).split(' · ').first;

  void _save() {
    final key = gamePackIdForName(
      _title,
      widget.design.resultIds,
      'match_trend',
    );
    final inputs = {'match': gamePackFieldRef('match_label')};
    String add(GameGraphOutputRef ref) {
      final id = gamePackIdForName(_label(ref), inputs.keys, 'value');
      inputs[id] = ref;
      return id;
    }

    final series = [
      for (final (index, ref) in _series.indexed)
        GamePackCardSeries(
          field: add(ref),
          label: _label(ref),
          tone: const [
            GamePackCardTone.accent,
            GamePackCardTone.info,
            GamePackCardTone.positive,
            GamePackCardTone.danger,
          ][index % 4],
        ),
    ];
    final markers = [
      for (final ref in _markers)
        GamePackCardMarker(field: add(ref), label: _label(ref)),
    ];
    final recipe = GamePackCalculation.recipe(
      id: key,
      label: _title.trim(),
      operation: GamePackRecipe.rows,
      grain: GamePackGrain.team,
      rowGrain: GamePackGrain.teamMatch,
      inputs: inputs,
      scheduleRows: _schedule,
    );
    final block = GamePackCardBlock(
      id: widget.id,
      title: _title.trim(),
      kind: GamePackCardBlockKind.trend,
      chart: GamePackCardChart(
        output: gamePackFieldRef(key),
        x: 'match',
        series: series,
        markers: markers,
      ),
    );
    BearingsModal.complete(context, (recipe: recipe, block: block));
  }

  @override
  Widget build(BuildContext context) => BearingsModal(
    title: 'Build match trend',
    actions: const [],
    primaryAction: BearingsModalPrimaryAction(
      label: 'Add trend',
      icon: LucideIcons.check,
      onPressed: _series.isEmpty || _title.trim().isEmpty ? null : _save,
    ),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 7,
      children: [
        TextFormField(
          initialValue: _title,
          decoration: const InputDecoration(labelText: 'Chart title'),
          onChanged: (title) => setState(() => _title = title),
        ),
        for (final values in [_series, _markers])
          for (final ref in values)
            ListTile(
              title: Text(_label(ref)),
              leading: Icon(
                values == _series ? LucideIcons.trendingUp : LucideIcons.flag,
              ),
              trailing: IconButton(
                tooltip: 'Remove ${_label(ref)}',
                onPressed: () => setState(() => values.remove(ref)),
                icon: const Icon(LucideIcons.x),
              ),
            ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              onPressed: _series.length >= 8 ? null : () => _add(false),
              icon: const Icon(LucideIcons.plus),
              label: const Text('Add match value'),
            ),
            OutlinedButton.icon(
              onPressed: _markers.length >= 8 ? null : () => _add(true),
              icon: const Icon(LucideIcons.plus),
              label: const Text('Add match marker'),
            ),
          ],
        ),
        CheckboxListTile(
          value: _schedule,
          title: const Text('Include matches without scout reports'),
          onChanged: (value) => setState(() => _schedule = value ?? false),
        ),
      ],
    ),
  );
}
