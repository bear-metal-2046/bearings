import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:ui/ui.dart';
import 'package:ui/widgets/forms/gamepack_form_view.dart';

import 'design.dart';
import 'event_picker.dart';
import 'fixture.dart';

class GamePackFixtureEditor extends ConsumerStatefulWidget {
  const GamePackFixtureEditor({
    super.key,
    required this.design,
    required this.fixture,
  });

  final GamePackDesign design;
  final GamePackBuilderFixture fixture;

  @override
  ConsumerState<GamePackFixtureEditor> createState() =>
      _GamePackFixtureEditorState();
}

class _GamePackFixtureEditorState extends ConsumerState<GamePackFixtureEditor> {
  late var _draft = widget.fixture;
  String? _reportMatch;

  Future<void> _pickEvent(int season) async {
    final event = await BearingsModal.show<CompetitionEvent>(
      context,
      builder: (_) =>
          GamePackEventPicker(current: _draft.event, season: season),
    );
    if (!mounted || event == null || event.id == _draft.event) return;
    setState(() {
      _draft = _draft.selectEvent(event.id);
      _reportMatch = null;
    });
  }

  Future<void> _editReport(
    GamePackBuilderFixture fixture,
    GamePackFixtureObservation? report,
  ) async {
    final result = await BearingsModal.show<GamePackFixtureObservation>(
      context,
      builder: (_) => _FixtureReportEditor(
        design: widget.design,
        fixture: fixture,
        current: report,
        initialMatch: _reportMatch,
      ),
    );
    if (!mounted || result == null) return;
    final reports = [..._draft.reports];
    if (report == null) {
      reports.add(result);
      if (_reportMatch != null && _reportMatch != result.match) {
        _reportMatch = null;
      }
    } else {
      reports[reports.indexOf(report)] = result;
    }
    setState(() => _draft = _draft.copyWith(reports: reports));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gamePackFixtureEventProvider(_draft.event));
    final data = state.value ?? _draft.data;
    final setup = _draft.withData(data);
    final scope = setup.scope;
    final event = _draft.event.isEmpty
        ? null
        : ref.watch(competitionEventProvider(_draft.event)).value;
    final season = widget.design.season;
    final reports = setup.eventReports;
    final reportCounts = <String?, int>{};
    for (final report in reports) {
      reportCounts.update(
        report.match,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final reportGroups = [
      if (_reportMatch case final match?)
        match
      else ...[
        for (final match in data?.matches ?? const <String>[])
          if (reportCounts.containsKey(match)) match,
        for (final match in reportCounts.keys)
          if (!(data?.matches.contains(match) ?? false)) match,
      ],
    ];
    final theme = Theme.of(context);
    final subtle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return BearingsModal(
      title: 'Edit test data',
      actions: const [],
      size: BearingsModalSize.expansive,
      scrolling: BearingsModalScrolling.content,
      primaryAction: BearingsModalPrimaryAction(
        label: 'Apply to previews',
        icon: LucideIcons.check,
        enabled: _draft.event.isNotEmpty && data != null,
        onPressed: () => BearingsModal.complete(
          context,
          setup.copyWith(team: () => scope.team, match: () => scope.match),
        ),
      ),
      content: ListView(
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          Text('Test event', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: season == null ? null : () => _pickEvent(season),
              icon: const Icon(LucideIcons.calendar),
              label: Text(
                event?.name ??
                    (_draft.event.isEmpty ? 'Choose event' : _draft.event),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (season == null)
            Text(
              'Set the GamePack season to choose a test event.',
              style: subtle,
            )
          else if (_draft.event.isEmpty)
            Text(
              'Choose a $season event to use its match schedule and official scores.',
              style: subtle,
            )
          else if (data == null && state.hasError)
            Row(
              children: [
                const Expanded(
                  child: Text('Couldn’t load match data for this event.'),
                ),
                TextButton(
                  onPressed: () {
                    retryCompetitionMatches(
                      ProviderScope.containerOf(context),
                      _draft.event,
                    );
                    ref.invalidate(gamePackFixtureEventProvider(_draft.event));
                  },
                  child: const Text('Retry'),
                ),
              ],
            )
          else if (data == null)
            Text('Loading event matches and official scores…', style: subtle)
          else ...[
            Text(
              '${data.matches.length} ${data.matches.length == 1 ? 'match' : 'matches'} · '
              '${data.scoreCount} with official scores · '
              '${reportCounts.keys.nonNulls.length} with scouting reports',
              style: subtle,
            ),
            if (data.partial)
              Text(
                'Showing available TBA data. Some matches or scores may be missing.',
                style: subtle,
              ),
            const Divider(height: 28),
            Text('Preview focus', style: theme.textTheme.titleMedium),
            const SizedBox(height: 5),
            Text(
              'Choose the team and match shown in previews. Aggregates use the full event.',
              style: subtle,
            ),
            const SizedBox(height: 12),
            _FixtureSelectors(
              children: [
                _FixtureStringSelect(
                  key: ValueKey(('team', _draft.event, scope.team)),
                  label: 'Preview team',
                  value: scope.team,
                  values: data.teamNames,
                  onChanged: (id) => setState(() {
                    _draft = _draft.copyWith(team: () => id, match: () => null);
                  }),
                ),
                _FixtureStringSelect(
                  key: ValueKey((
                    'match',
                    _draft.event,
                    scope.team,
                    scope.match,
                  )),
                  label: 'Preview match',
                  value: scope.match,
                  values: {
                    for (final match in data.matchesFor(scope.team))
                      match: data.matchLabel(match),
                  },
                  onChanged: (id) =>
                      setState(() => _draft = _draft.copyWith(match: () => id)),
                ),
              ],
            ),
            const Divider(height: 28),
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Text(
                    'Scouting reports',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      widget.design.configuredForms.isEmpty ||
                          (data.matches.isEmpty && data.teams.isEmpty)
                      ? null
                      : () => _editReport(setup, null),
                  icon: const Icon(LucideIcons.plus, size: 17),
                  label: const Text('Add report'),
                ),
              ],
            ),
            if (widget.design.configuredForms.isEmpty)
              Text(
                'Add a question in Forms to create a test report.',
                style: subtle,
              )
            else if (data.matches.isEmpty && data.teams.isEmpty)
              Text(
                'Reports need a team or match from the event lineup.',
                style: subtle,
              )
            else ...[
              if (data.matches.isNotEmpty) ...[
                const SizedBox(height: 8),
                _FixtureStringSelect(
                  key: ValueKey(('reports', _draft.event, _reportMatch)),
                  label: 'Show reports for',
                  value: _reportMatch ?? '',
                  values: {
                    '': 'All matches and teams',
                    for (final match in data.matches)
                      match:
                          '${data.matchLabel(match)} · ${reportCounts[match] ?? 0} reports',
                  },
                  onChanged: (id) =>
                      setState(() => _reportMatch = id == '' ? null : id),
                ),
              ],
              if (reports.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Add sample answers to test scouting calculations across matches.',
                    style: subtle,
                  ),
                )
              else
                for (final match in reportGroups) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      match == null ? 'Team reports' : data.matchLabel(match),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (!reportCounts.containsKey(match))
                    Text(
                      'No scouting reports for this match yet.',
                      style: subtle,
                    ),
                  for (final report in reports.where(
                    (report) => report.match == match,
                  ))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(LucideIcons.clipboardList, size: 18),
                      title: Text(
                        widget.design.forms
                                .where((form) => form.id == report.form)
                                .firstOrNull
                                ?.label ??
                            'Unavailable form',
                      ),
                      subtitle: Text(
                        report.team == null
                            ? '${gamePackKeyLabel(report.alliance ?? '')} alliance'
                            : data.teamLabel(report.team!),
                      ),
                      onTap:
                          widget.design.configuredForms.any(
                            (form) => form.id == report.form,
                          )
                          ? () => _editReport(setup, report)
                          : null,
                      trailing: IconButton(
                        tooltip: 'Remove test report',
                        icon: const Icon(LucideIcons.trash2, size: 18),
                        onPressed: () => setState(() {
                          _draft = _draft.copyWith(
                            reports: [..._draft.reports]..remove(report),
                          );
                        }),
                      ),
                    ),
                ],
            ],
            const Divider(height: 28),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Advanced'),
              childrenPadding: const EdgeInsets.only(top: 8, bottom: 12),
              children: [
                TextFormField(
                  initialValue: '${_draft.seed}',
                  decoration: const InputDecoration(
                    labelText: 'Simulation seed',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                  onChanged: (raw) {
                    if (int.tryParse(raw) case final seed?) {
                      _draft = _draft.copyWith(seed: seed);
                    }
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FixtureReportEditor extends StatefulWidget {
  const _FixtureReportEditor({
    required this.design,
    required this.fixture,
    this.current,
    this.initialMatch,
  });

  final GamePackDesign design;
  final GamePackBuilderFixture fixture;
  final GamePackFixtureObservation? current;
  final String? initialMatch;

  @override
  State<_FixtureReportEditor> createState() => _FixtureReportEditorState();
}

class _FixtureReportEditorState extends State<_FixtureReportEditor> {
  final _validation = GlobalKey<FormState>();
  late final _data = widget.fixture.data!;
  late var _form =
      widget.design.configuredForms
          .where((form) => form.id == widget.current?.form)
          .firstOrNull ??
      widget.design.configuredForms.first;
  late String? _match = widget.current != null
      ? widget.current!.match
      : widget.initialMatch ?? widget.fixture.scope.match;
  late String? _team = widget.current?.team ?? widget.fixture.scope.team;
  late String _alliance =
      widget.current?.alliance ?? widget.fixture.scope.alliance ?? 'red';
  late bool _editing = widget.current != null;
  late var _answers = {..._defaultAnswers(), ...?widget.current?.answers};

  bool get _strategy => _form.kind == GamePackFormKind.strategy;
  bool get _matchRequired => _strategy || _form.kind == GamePackFormKind.match;
  bool get _matchSupported => _form.kind != GamePackFormKind.pit;
  bool get _observation => _form.kind == GamePackFormKind.observation;
  String? get _reportMatch => _matchSupported && _match != '' ? _match : null;
  Map<String, ({String alliance, int station})>? get _lineup =>
      _reportMatch == null ? null : _data.lineup(_reportMatch!);
  Iterable<String> get _eligibleTeams => _lineup?.keys ?? _data.teams;
  String? get _reportTeam => _strategy
      ? null
      : widget.current != null
      ? widget.current!.team
      : _eligibleTeams.contains(_team)
      ? _team
      : _eligibleTeams.firstOrNull;
  String? get _reportAlliance =>
      _strategy ? _alliance : _lineup?[_reportTeam]?.alliance;
  bool get _canFill =>
      (!_matchRequired || _reportMatch != null) &&
      (_strategy || _reportTeam != null);
  Map<String, Object?> _defaultAnswers() => _form.defaults(
    widget.design.fieldById,
    roster: _data.allianceTeams(_reportMatch, _reportAlliance),
  );

  void _save() {
    if (!_validation.currentState!.validate()) return;
    final visible = _form.visibleFields(_answers);
    BearingsModal.complete(
      context,
      GamePackFixtureObservation(
        event: widget.fixture.event,
        form: _form.id,
        match: _reportMatch,
        team: _reportTeam,
        alliance: _reportAlliance,
        answers: {
          for (final entry in _answers.entries)
            if (visible.contains(entry.key)) entry.key: entry.value,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BearingsModal(
      title: widget.current == null
          ? 'Add scouting report'
          : 'Edit scouting report',
      actions: [
        if (_editing && widget.current == null)
          BearingsModalAction(
            icon: LucideIcons.arrowLeft,
            label: 'Back to report setup',
            onPressed: () => setState(() => _editing = false),
          ),
      ],
      size: _editing ? BearingsModalSize.expansive : BearingsModalSize.compact,
      scrolling: _editing
          ? BearingsModalScrolling.content
          : BearingsModalScrolling.managed,
      primaryAction: BearingsModalPrimaryAction(
        label: _editing ? 'Save report' : 'Enter answers',
        icon: _editing ? LucideIcons.check : LucideIcons.arrowRight,
        enabled: _editing || _canFill,
        onPressed: _editing
            ? _save
            : () => setState(() {
                _answers = _defaultAnswers();
                _editing = true;
              }),
      ),
      content: _editing
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Text(
                  [
                    _form.label,
                    if (_reportMatch case final match?) _data.matchLabel(match),
                    if (_reportTeam case final team?)
                      _data.teamLabel(team)
                    else
                      '${gamePackKeyLabel(_alliance)} alliance',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Expanded(
                  child: Form(
                    key: _validation,
                    child: GamePackFormView(
                      fields: widget.design.fieldById,
                      form: _form,
                      answers: _answers,
                      onChanged: (answers) =>
                          setState(() => _answers = answers),
                    ),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                _FixtureStringSelect(
                  label: 'Scouting form',
                  value: _form.id,
                  values: {
                    for (final form in widget.design.configuredForms)
                      form.id: form.label,
                  },
                  onChanged: (id) => setState(() {
                    _form = widget.design.configuredForms.firstWhere(
                      (form) => form.id == id,
                    );
                    if (_matchRequired && (_match == null || _match == '')) {
                      _match =
                          widget.fixture.scope.match ??
                          _data.matches.firstOrNull;
                    }
                  }),
                ),
                if (_matchSupported)
                  _FixtureStringSelect(
                    key: ValueKey(('reportMatch', _form.kind, _match)),
                    label: 'Report match',
                    value: _observation ? _match ?? '' : _match,
                    values: {
                      if (_observation) '': 'No match',
                      for (final match in _data.matches)
                        match: _data.matchLabel(match),
                    },
                    onChanged: (match) => setState(() => _match = match),
                  ),
                if (_strategy)
                  _FixtureStringSelect(
                    label: 'Alliance',
                    value: _alliance,
                    values: const {'red': 'Red', 'blue': 'Blue'},
                    onChanged: (alliance) =>
                        setState(() => _alliance = alliance),
                  )
                else
                  _FixtureStringSelect(
                    key: ValueKey((
                      'reportTeam',
                      _form.kind,
                      _match,
                      _reportTeam,
                    )),
                    label: 'Report team',
                    value: _reportTeam,
                    values: {
                      for (final team in _eligibleTeams)
                        team: _data.teamLabel(team),
                    },
                    onChanged: (team) => setState(() => _team = team),
                  ),
              ],
            ),
    );
  }
}

class _FixtureSelectors extends StatelessWidget {
  const _FixtureSelectors({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => bounds.maxWidth < 480
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: children,
          )
        : Row(
            spacing: 12,
            children: [for (final child in children) Expanded(child: child)],
          ),
  );
}

class _FixtureStringSelect extends StatelessWidget {
  const _FixtureStringSelect({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final Map<String, String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => BearingsSelect<String>(
    value: values.containsKey(value) ? value : null,
    decoration: InputDecoration(
      labelText: label,
      hintText: values.isEmpty ? 'Unavailable' : null,
    ),
    items: [
      for (final entry in values.entries)
        BearingsSelectItem(
          value: entry.key,
          child: Text(entry.value, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: values.isEmpty
        ? null
        : (id) {
            if (id != null) onChanged(id);
          },
  );
}
