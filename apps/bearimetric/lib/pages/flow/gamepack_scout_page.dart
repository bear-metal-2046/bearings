import 'dart:async';
import 'dart:convert';

import 'package:bearimetric/custom_widgets/upload_status_indicator.dart';
import 'package:bearimetric/data/scouting_store.dart';
import 'package:bearimetric/models/scouting_session.dart' show trainingEventKey;
import 'package:bearimetric/providers/app_provider.dart';
import 'package:bearimetric/providers/scouting_providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grove/grove.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:services/providers/gamepack_provider.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:ui/widgets/bearings_popup_menu.dart';
import 'package:ui/widgets/forms/gamepack_form_view.dart';

class GamePackScoutPage extends ConsumerStatefulWidget {
  const GamePackScoutPage({
    super.key,
    required this.event,
    required this.position,
    this.scoutId,
    required this.initialMatchId,
    this.onMatchSelected,
    this.onChooseMatch,
    this.onBack,
  });

  final String event;
  final ScoutPosition position;
  final String? scoutId;
  final String initialMatchId;
  final ValueChanged<CompetitionMatch>? onMatchSelected;
  final VoidCallback? onBack;
  final VoidCallback? onChooseMatch;

  @override
  ConsumerState<GamePackScoutPage> createState() => _GamePackScoutPageState();
}

class _GamePackScoutPageState extends ConsumerState<GamePackScoutPage> {
  var _observation = GlobalKey<_GamePackObservationFormState>();
  Object? _observationIdentity;
  String? _selectedMatch;
  bool _navigating = false;

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _changeMatch(CompetitionMatch match) async {
    if (_navigating) return;
    setState(() => _navigating = true);
    try {
      if (!mounted) return;
      final observation = _observation.currentState;
      if (observation != null && await observation._submit() && mounted) {
        _select(match);
      }
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  AppBar _appBar(Widget title) {
    final isDark = ref.watch(brightnessNotifierProvider) == Brightness.dark;
    return AppBar(
      leading: widget.onBack == null
          ? null
          : IconButton(
              icon: const Icon(LucideIcons.x),
              tooltip: 'Exit to Scout Selection',
              onPressed: _navigating
                  ? null
                  : () async {
                      if (await _confirm(
                            'Exit Scouting',
                            'Are you sure you want to exit this match?',
                            'Exit',
                          ) &&
                          mounted) {
                        final observation = _observation.currentState;
                        if (observation == null ||
                            await observation._flushDraft()) {
                          if (mounted) widget.onBack!();
                        }
                      }
                    },
            ),
      title: title,
      actionsPadding: const EdgeInsets.only(right: 4),
      actions: [
        const Padding(
          padding: EdgeInsets.only(left: 8, right: 4),
          child: UploadStatusIndicator(),
        ),
        if (!widget.position.isStrategy)
          IconButton(
            isSelected: isDark,
            tooltip: isDark ? 'Use light theme' : 'Use dark theme',
            iconSize: 18,
            icon: const Icon(LucideIcons.sun),
            selectedIcon: const Icon(LucideIcons.moon),
            onPressed: () => ref
                .read(brightnessNotifierProvider.notifier)
                .changeBrightness(!isDark),
          ),
      ],
    );
  }

  String _teamLabel(EntityRef<CompetitionTeam> team) =>
      'Team ${team.id.replaceFirst('frc', '')}';

  void _select(CompetitionMatch match) {
    setState(() => _selectedMatch = match.id);
    widget.onMatchSelected?.call(match);
  }

  @override
  Widget build(BuildContext context) {
    final training = widget.event == trainingEventKey;
    final source = training
        ? ref.watch(practiceScheduleProvider)
        : AsyncData<String?>(widget.event);
    return source.when(
      loading: _loadingScreen,
      error: (error, _) => _status('Training schedule unavailable: $error'),
      data: (event) => event == null
          ? _status('No event schedule is available for training.')
          : ref
                .watch(
                  training
                      ? practiceGamePackProvider(event)
                      : eventGamePackProvider(event),
                )
                .when(
                  loading: _loadingScreen,
                  error: (error, _) => _status('GamePack unavailable: $error'),
                  data: (release) => release == null
                      ? _status(
                          training
                              ? 'Assign a practice GamePack in Beariscope.'
                              : 'No GamePack is assigned to $event.',
                        )
                      : _buildSchedule(release, event, training),
                ),
    );
  }

  Widget _buildSchedule(GamePack release, String event, bool training) {
    final form = release.definition.formFor(
      widget.position.isStrategy
          ? GamePackFormKind.strategy
          : GamePackFormKind.match,
    );
    if (form == null) {
      return _status(
        'This GamePack has no form for ${widget.position.displayName}.',
      );
    }
    final grove = ref.watch(bearingsGroveProvider);
    final schedule = ref.watch(competitionMatchesProvider(event));
    return schedule.when(
      loading: _loadingScreen,
      error: (error, _) => _status('Schedule unavailable: $error'),
      data: (snapshot) {
        if (!snapshot.hasSnapshot || snapshot.updateRequired) {
          return _status(
            'Open this event online to download its match schedule.',
          );
        }
        final options =
            <String, (CompetitionMatch, EntityRef<CompetitionTeam>?)>{};
        final index = widget.position.allianceIndex;
        for (final match in snapshot.items) {
          final teams = (widget.position.isRed ? match.red : match.blue)?.teams;
          if (teams == null || teams.isEmpty) continue;
          if (widget.position.isStrategy) {
            options[match.id] = (match, null);
          } else if (index >= 0 && index < teams.length) {
            options[match.id] = (match, teams[index]);
          }
        }
        if (options.isEmpty) {
          return _status(
            'No scheduled matches for ${widget.position.displayName}.',
          );
        }
        final sorted = options.values.toList()
          ..sort((a, b) => compareScoutingMatches(a.$1, b.$1));
        final requested = _selectedMatch ?? widget.initialMatchId;
        final selected = options[requested];
        if (selected == null) {
          return _shell(
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 12,
                children: [
                  const Text(
                    'This match is unavailable in the downloaded schedule.',
                    textAlign: TextAlign.center,
                  ),
                  if (widget.onChooseMatch != null)
                    FilledButton(
                      onPressed: widget.onChooseMatch,
                      child: const Text('Choose another match'),
                    ),
                ],
              ),
            ),
          );
        }
        final records = ref.watch(scoutingRecordsProvider).value ?? [];
        final drafts = {
          for (final record in records)
            if (isScoutingDraft(record)) record['key'],
        };
        final (match, team) = selected;
        final identity = (
          grove,
          release.id,
          match.id,
          team?.id,
          widget.position,
          widget.scoutId,
          training,
        );
        if (_observationIdentity != identity) {
          _observationIdentity = identity;
          _observation = GlobalKey<_GamePackObservationFormState>();
        }
        final indexInSchedule = sorted.indexOf(selected);
        final previous = indexInSchedule > 0
            ? sorted[indexInSchedule - 1].$1
            : null;
        final next = indexInSchedule + 1 < sorted.length
            ? sorted[indexInSchedule + 1].$1
            : null;
        final matchTitle =
            '${scoutingMatchLabel(match)} · ${widget.position.displayName}'
            '${team == null ? '' : ' · ${_teamLabel(team)}'}';
        final title = Text(
          matchTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge,
        );
        return Scaffold(
          appBar: _appBar(
            sorted.length == 1
                ? title
                : BearingsPopupMenu(
                    triggerBuilder: (context, controller, focusNode) => Tooltip(
                      message: 'Select match',
                      child: TextButton(
                        focusNode: focusNode,
                        onPressed: _navigating
                            ? null
                            : () => controller.isOpen
                                  ? controller.close()
                                  : controller.open(),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .onSurface,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(48, 48),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: title),
                            const SizedBox(width: 6),
                            const Icon(Icons.expand_more, size: 20),
                          ],
                        ),
                      ),
                    ),
                    menuChildren: [
                      for (final (option, team) in sorted)
                        BearingsMenuItem(
                          selected: option.id == match.id,
                          onPressed: () {
                            if (option.id != match.id) _changeMatch(option);
                          },
                          child: Text(
                            '${scoutingMatchLabel(option)}'
                            '${team == null ? '' : ' · ${_teamLabel(team)}'}'
                            '${drafts.contains(scoutingRecordKey(training: training, pack: release.id, form: form.id, match: option.id, station: widget.position.posIndex, team: team?.id, scout: widget.scoutId)) ? ' · Draft' : ''}',
                          ),
                        ),
                    ],
                  ),
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: form.pages.any((page) => page.usesGrid)
                      ? double.infinity
                      : 840,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (training)
                        const Text('Practice submissions stay on this device.'),
                      if (snapshot.offline)
                        const Text('Using the downloaded schedule'),
                      Expanded(
                        child: _GamePackObservationForm(
                          key: _observation,
                          form: form,
                          scoutId: widget.scoutId,
                          match: match,
                          team: team,
                          position: widget.position,
                          release: release,
                          isLastMatch: next == null,
                          onPreviousMatch: _navigating || previous == null
                              ? null
                              : () => _changeMatch(previous),
                          onNextMatch: _navigating || next == null
                              ? null
                              : () => _changeMatch(next),
                          training: training,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _loadingScreen() =>
      _shell(const Center(child: CircularProgressIndicator()));

  Widget _status(String message) => _shell(
    Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(message, textAlign: TextAlign.center),
      ),
    ),
  );

  Widget _shell(Widget body) => Scaffold(
    appBar: _appBar(
      Text(widget.event == trainingEventKey ? 'Training' : 'Scouting'),
    ),
    body: body,
  );
}

class _GamePackObservationForm extends ConsumerStatefulWidget {
  const _GamePackObservationForm({
    required super.key,
    required this.form,
    required this.scoutId,
    required this.isLastMatch,
    required this.onPreviousMatch,
    required this.onNextMatch,
    required this.training,
    required this.match,
    required this.team,
    required this.position,
    required this.release,
  });

  final GamePackForm form;
  final String? scoutId;
  final bool isLastMatch;
  final VoidCallback? onPreviousMatch;
  final VoidCallback? onNextMatch;
  final bool training;
  final CompetitionMatch match;
  final EntityRef<CompetitionTeam>? team;
  final ScoutPosition position;
  final GamePack release;

  @override
  ConsumerState<_GamePackObservationForm> createState() =>
      _GamePackObservationFormState();
}

class _GamePackObservationFormState
    extends ConsumerState<_GamePackObservationForm> {
  final _form = GlobalKey<FormState>();
  late final _grove = ref.read(bearingsGroveProvider);
  late final _store = ref.read(scoutingStoreProvider);
  late final _draftKey = scoutingRecordKey(
    training: widget.training,
    pack: widget.release.id,
    form: widget.form.id,
    match: widget.match.id,
    station: widget.position.posIndex,
    team: widget.team?.id,
    scout: widget.scoutId,
  );
  late final Json _subject = {
    'event': widget.match.event.id,
    'match': widget.match.id,
    'team': widget.team?.id,
    'gamePack': widget.release.id,
    'station': widget.position.posIndex,
    'form': widget.form.id,
    'scout': widget.scoutId,
  };
  late final _defaults = widget.form.defaults(
    widget.release.definition.fieldById,
    roster:
        ((widget.position.isRed ? widget.match.red : widget.match.blue)
                    ?.teams ??
                [])
            .map((team) => team.id)
            .toList(),
  );
  Future<void> _writes = Future.value();
  bool _loading = true;
  bool _saving = false;
  bool _draftWriteFailed = false;
  late Map<String, Object?> _answers = Map.of(_defaults);
  late String _baseline = canonicalJson(_visibleAnswers(_defaults));

  Json _visibleAnswers(Map<String, Object?> answers) {
    final visible = widget.form.visibleFields(answers);
    return {
      for (final entry in answers.entries)
        if (visible.contains(entry.key)) entry.key: entry.value,
    };
  }

  bool get _changed => canonicalJson(_visibleAnswers(_answers)) != _baseline;

  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final local = await _store.read(_draftKey);
      final previous = local == null
          ? await _grove.cache.read(_draftKey)
          : null;
      if (!mounted) return;
      final answers = (local ?? previous)?['answers'] as Json?;
      if (answers != null) {
        _answers = local == null ? {..._defaults, ...answers} : Map.of(answers);
      }
      Json? previousBaseline;
      if (previous != null) {
        final baseline = previous['baseline'] as String?;
        final legacy =
            previous['saved'] == true || previous['legacySave'] == true;
        final confirmed = baseline == null
            ? (legacy ? _visibleAnswers(_answers) : null)
            : jsonDecode(baseline) as Json;
        previousBaseline = confirmed;
        final parent = previous['savedId'] as String?;
        final pendingId = previous['submissionId'] as String?;
        final migration = {
          'head': parent,
          'confirmedAnswers': confirmed,
          'legacySave': legacy,
          if (pendingId != null)
            'flight': {
              ..._subject,
              'id': pendingId,
              'capturedAt': previous['capturedAt'],
              'answers': _visibleAnswers(_answers),
              'supersedes': parent,
              'reason': parent == null ? null : 'Updated by the scout',
            },
        };
        await _store.save(
          _draftKey,
          subject: _subject,
          answers: _answers,
          working: _visibleAnswers(_answers),
          defaults: _visibleAnswers(_defaults),
          training: widget.training,
          ready: pendingId == null ? null : _visibleAnswers(_answers),
          initial: migration,
        );
      }
      _baseline = canonicalJson(
        local?['ready'] ??
            local?['confirmedAnswers'] ??
            previousBaseline ??
            _visibleAnswers(_defaults),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not reopen draft: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _saveDraft(Map<String, Object?> answers) {
    setState(() {
      _answers = answers;
      _error = null;
    });
    _writes = _store
        .save(
          _draftKey,
          subject: _subject,
          answers: answers,
          working: _visibleAnswers(answers),
          defaults: _visibleAnswers(_defaults),
          training: widget.training,
        )
        .then(
          (_) {
            _draftWriteFailed = false;
          },
          onError: (Object error) {
            _draftWriteFailed = true;
            if (mounted) {
              setState(() => _error = 'Could not save draft: $error');
            }
          },
        );
  }

  Future<bool> _flushDraft() async {
    await _writes;
    return !_draftWriteFailed;
  }

  Future<bool> _submit({bool explicit = false}) async {
    if (_loading || _saving) return false;
    final answers = _visibleAnswers(_answers);
    if (!_changed) return _flushDraft();
    Json? ready;
    try {
      widget.release.definition.validateAnswers(
        answers,
        formId: widget.form.id,
      );
      widget.form.validateRankings(
        answers,
        widget.release.definition.fieldById,
        roster:
            ((widget.position.isRed ? widget.match.red : widget.match.blue)
                        ?.teams ??
                    [])
                .map((team) => team.id)
                .toList(),
      );
      if (_form.currentState?.validate() == true) ready = answers;
    } on FormatException catch (error) {
      if (explicit && mounted) setState(() => _error = error.message);
    }
    if (!mounted) return false;
    if (explicit && ready == null) return false;
    setState(() => _saving = true);
    try {
      await _writes;
      await _store.save(
        _draftKey,
        subject: _subject,
        answers: _answers,
        working: answers,
        defaults: _visibleAnswers(_defaults),
        training: widget.training,
        ready: ready,
      );
      _draftWriteFailed = false;
      if (mounted && ready != null) {
        setState(() => _baseline = canonicalJson(ready));
      }
      return true;
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not save match: $error');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _loading
      ? const Center(
          child: SizedBox(width: 96, child: LinearProgressIndicator()),
        )
      : Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: GamePackFormView(
                  fields: widget.release.definition.fieldById,
                  form: widget.form,
                  answers: _answers,
                  onChanged: _saveDraft,
                  enabled: !_saving,
                  pageNavigationTrailing: _MatchNavigation(
                    onPrevious: _saving ? null : widget.onPreviousMatch,
                    onNext: _saving ? null : widget.onNextMatch,
                  ),
                ),
              ),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (widget.isLastMatch && _changed)
                FilledButton.icon(
                  onPressed: _saving ? null : () => _submit(explicit: true),
                  icon: const Icon(LucideIcons.check),
                  label: Text(_saving ? 'Saving…' : 'Save observation'),
                ),
            ],
          ),
        );
}

class _MatchNavigation extends StatelessWidget {
  const _MatchNavigation({required this.onPrevious, required this.onNext});

  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final style = OutlinedButton.styleFrom(
      minimumSize: Size(48, 48 + (scale - 1).clamp(0.0, 2.0) * 14),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      backgroundColor: colors.surfaceContainerHigh,
      disabledBackgroundColor: colors.surfaceContainerHigh,
      foregroundColor: colors.onSurface,
      side: BorderSide(color: colors.outlineVariant),
      shape: const StadiumBorder(),
      visualDensity: VisualDensity.standard,
      textStyle: Theme.of(context).textTheme.labelLarge,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Tooltip(
          message: 'Previous Match',
          child: OutlinedButton(
            style: style,
            onPressed: onPrevious,
            child: const Icon(LucideIcons.chevronLeft, size: 18),
          ),
        ),
        Tooltip(
          message: 'Next Match',
          child: OutlinedButton(
            style: style,
            onPressed: onNext,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                Text(
                  'Next',
                  style:
                      (Theme.of(context).textTheme.labelMedium ??
                              const TextStyle())
                          .copyWith(fontWeight: FontWeight.w500),
                ),
                const Icon(LucideIcons.chevronRight, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
