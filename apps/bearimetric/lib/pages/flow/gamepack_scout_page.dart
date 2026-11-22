import 'dart:async';

import 'package:bearimetric/custom_widgets/upload_status_indicator.dart';
import 'package:bearimetric/models/scouting_session.dart' show trainingEventKey;
import 'package:bearimetric/providers/scouting_providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grove/grove.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:services/providers/gamepack_provider.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:ui/widgets/forms/gamepack_form_view.dart';
import 'package:uuid/uuid.dart';

class GamePackScoutPage extends ConsumerStatefulWidget {
  const GamePackScoutPage({
    super.key,
    required this.event,
    required this.position,
    this.scoutId,
    this.initialMatchNumber,
    this.onBack,
    this.onMatchChanged,
  });

  final String event;
  final ScoutPosition position;
  final String? scoutId;
  final int? initialMatchNumber;
  final VoidCallback? onBack;
  final ValueChanged<int>? onMatchChanged;

  @override
  ConsumerState<GamePackScoutPage> createState() => _GamePackScoutPageState();
}

class _GamePackScoutPageState extends ConsumerState<GamePackScoutPage> {
  String? _selectedMatch;

  void _select(CompetitionMatch match) {
    setState(() => _selectedMatch = match.id);
    if (match.level == 'qm') widget.onMatchChanged?.call(match.matchNumber);
  }

  @override
  Widget build(BuildContext context) {
    final training = widget.event == trainingEventKey;
    final source = training
        ? ref.watch(eventsProvider).whenData((events) => events.firstOrNull?.id)
        : AsyncData<String?>(widget.event);
    return Scaffold(
      appBar: AppBar(
        title: Text(training ? 'Training' : 'Scouting'),
        leading: widget.onBack == null
            ? null
            : BackButton(onPressed: widget.onBack),
        actionsPadding: const EdgeInsets.only(right: 16),
        actions: const [UploadStatusIndicator()],
      ),
      body: source.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _status('Training schedule unavailable: $error'),
        data: (event) => event == null
            ? _status('No event schedule is available for training.')
            : ref
                  .watch(eventGamePackProvider(event))
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) =>
                        _status('GamePack unavailable: $error'),
                    data: (release) => release == null
                        ? _status('No GamePack is assigned to $event.')
                        : _buildSchedule(release, event, training),
                  ),
      ),
    );
  }

  Widget _buildSchedule(GamePackRelease release, String event, bool training) {
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
      loading: () => const Center(child: CircularProgressIndicator()),
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
          ..sort((a, b) {
            final left = a.$1;
            final right = b.$1;
            final dateOrder = (left.scheduledAt?.millisecondsSinceEpoch ?? 0)
                .compareTo(right.scheduledAt?.millisecondsSinceEpoch ?? 0);
            if (dateOrder != 0) return dateOrder;
            final setOrder = left.setNumber.compareTo(right.setNumber);
            if (setOrder != 0) return setOrder;
            final matchOrder = left.matchNumber.compareTo(right.matchNumber);
            return matchOrder != 0 ? matchOrder : left.id.compareTo(right.id);
          });
        final initial = widget.initialMatchNumber;
        final selected =
            options[_selectedMatch] ??
            sorted
                .where(
                  (entry) =>
                      entry.$1.level == 'qm' && entry.$1.matchNumber == initial,
                )
                .firstOrNull ??
            sorted.first;
        _selectedMatch = selected.$1.id;
        final (match, team) = selected;
        final nextIndex = sorted.indexOf(selected) + 1;
        final next = nextIndex < sorted.length ? sorted[nextIndex].$1 : null;
        return Align(
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
                  Text(
                    release.definition.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text('$event · ${widget.position.displayName}'),
                  if (training)
                    const Text('Practice submissions stay on this device.'),
                  if (snapshot.offline)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Using the downloaded schedule'),
                    ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    key: ValueKey(match.id),
                    initialValue: match.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Match and team',
                    ),
                    items: [
                      for (final (match, team) in sorted)
                        DropdownMenuItem(
                          value: match.id,
                          child: Text(
                            '${match.id.split('_').last.toUpperCase()} · '
                            '${team == null ? widget.position.displayName : 'Team ${team.id.replaceFirst('frc', '')}'}',
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      if (options[id] case (final match, _)) _select(match);
                    },
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: _GamePackObservationForm(
                      key: ValueKey((
                        grove,
                        release.id,
                        match.id,
                        team?.id,
                        widget.position,
                        widget.scoutId,
                        training,
                      )),
                      form: form,
                      scoutId: widget.scoutId,
                      match: match,
                      team: team,
                      position: widget.position,
                      release: release,
                      onNext: next == null ? null : () => _select(next),
                      training: training,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _status(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

class _GamePackObservationForm extends ConsumerStatefulWidget {
  const _GamePackObservationForm({
    required super.key,
    required this.form,
    required this.scoutId,
    required this.onNext,
    required this.training,
    required this.match,
    required this.team,
    required this.position,
    required this.release,
  });

  final GamePackForm form;
  final String? scoutId;
  final VoidCallback? onNext;
  final bool training;
  final CompetitionMatch match;
  final EntityRef<CompetitionTeam>? team;
  final ScoutPosition position;
  final GamePackRelease release;

  @override
  ConsumerState<_GamePackObservationForm> createState() =>
      _GamePackObservationFormState();
}

class _GamePackObservationFormState
    extends ConsumerState<_GamePackObservationForm> {
  final _form = GlobalKey<FormState>();
  late final _grove = ref.read(bearingsGroveProvider);
  late final _draftKey =
      'gamepack:draft:${canonicalJson([if (widget.training) 'training', widget.release.id, widget.form.id, widget.match.id, widget.position.posIndex, widget.team?.id, if (widget.scoutId != null) widget.scoutId])}';
  late Map<String, Object?> _answers = widget.form.defaults(
    widget.release.definition.fieldById,
    roster:
        ((widget.position.isRed ? widget.match.red : widget.match.blue)
                    ?.teams ??
                [])
            .map((team) => team.id)
            .toList(),
  );
  Future<void> _writes = Future.value();
  ({String id, DateTime capturedAt})? _submission;
  bool _loading = true;
  bool _saving = false;
  bool _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final draft = await _grove.cache.read(_draftKey);
      if (!mounted) return;
      setState(() {
        if (draft?['answers'] case final Map<String, dynamic> answers) {
          _answers = answers;
        }
        if (draft?['submissionId'] case final String id) {
          _submission = (
            id: id,
            capturedAt: DateTime.parse(draft!['capturedAt'] as String),
          );
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not reopen draft: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _saveDraft(Map<String, Object?> answers) {
    setState(() => _answers = answers);
    _writes = _writes.then((_) async {
      try {
        await _grove.cache.write(_draftKey, {'answers': answers});
      } catch (error) {
        if (mounted) setState(() => _error = 'Could not save draft: $error');
      }
    });
  }

  Future<void> _submit() async {
    if (_saving || _saved || !_form.currentState!.validate()) return;
    final visible = widget.form.visibleFields(_answers);
    final answers = <String, dynamic>{
      for (final entry in _answers.entries)
        if (visible.contains(entry.key)) entry.key: entry.value,
    };
    try {
      widget.release.definition.validateAnswers(
        answers,
        formId: widget.form.id,
      );
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    final submission =
        _submission ??
        (id: const Uuid().v4(), capturedAt: DateTime.now().toUtc());
    final observation = GamePackObservation(
      id: submission.id,
      event: widget.match.event,
      match: EntityRef(widget.match.id),
      team: widget.team,
      release: EntityRef(widget.release.id),
      station: widget.position.posIndex,
      capturedAt: submission.capturedAt,
      form: widget.form.id,
      scout: widget.scoutId == null ? null : EntityRef(widget.scoutId!),
      answers: answers,
    );
    setState(() {
      _saving = true;
      _error = null;
      _submission = submission;
    });
    try {
      await _writes;
      // A restart between the durable queue write and draft cleanup can
      // safely retry the same immutable submission.
      await _grove.cache.write(_draftKey, {
        'answers': answers,
        'submissionId': submission.id,
        'capturedAt': submission.capturedAt.toIso8601String(),
      });
      if (widget.training) {
        await _grove.cache.write(
          'training:$_draftKey',
          gamePackObservationEntity.encode(observation),
        );
      } else {
        await _grove.stageCreate(observation);
      }
      await _grove.cache.remove(_draftKey);
      if (mounted) setState(() => _saved = true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not save observation: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _loading
      ? const LinearProgressIndicator()
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
                  enabled: !_saving && !_saved && _submission == null,
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
              if (_saved) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(LucideIcons.circleCheck),
                  title: Text(
                    widget.training
                        ? 'Practice observation saved'
                        : 'Observation saved',
                  ),
                  subtitle: widget.training
                      ? null
                      : const Text(
                          'Check upload status for server confirmation.',
                        ),
                ),
                if (widget.onNext != null)
                  FilledButton.icon(
                    onPressed: widget.onNext,
                    icon: const Icon(LucideIcons.arrowRight),
                    label: const Text('Next match'),
                  ),
              ] else
                FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: const Icon(LucideIcons.check),
                  label: Text(
                    _saving
                        ? 'Saving…'
                        : _submission == null
                        ? 'Save observation'
                        : 'Retry save',
                  ),
                ),
            ],
          ),
        );
}
