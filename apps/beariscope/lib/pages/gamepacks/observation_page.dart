import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grove/grove.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:ui/widgets/forms/gamepack_form_view.dart';
import 'package:uuid/uuid.dart';

class GamePackObservationPage extends ConsumerStatefulWidget {
  const GamePackObservationPage({
    super.key,
    required this.title,
    required this.event,
    required this.release,
    required this.kind,
    this.team,
    this.match,
    this.station,
    this.roster = const [],
    this.previous,
    this.writable = true,
  });

  final String title;
  final String event;
  final GamePack release;
  final GamePackFormKind kind;
  final String? team;
  final String? match;
  final int? station;
  final List<String> roster;
  final GamePackObservation? previous;
  final bool writable;

  @override
  ConsumerState<GamePackObservationPage> createState() =>
      _GamePackObservationPageState();
}

class _GamePackObservationPageState
    extends ConsumerState<GamePackObservationPage> {
  final _validation = GlobalKey<FormState>();
  late final _form = widget.release.definition.formFor(widget.kind);
  late Map<String, Object?> _answers =
      widget.previous?.answers ??
      _form?.defaults(
        widget.release.definition.fieldById,
        roster: widget.roster,
      ) ??
      {};
  late final _id = const Uuid().v4();
  late final _timestamp = DateTime.now().toUtc();
  String _reason = '';
  String? _error;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving || !_validation.currentState!.validate()) return;
    final form = _form!;
    final previous = widget.previous;
    final reason = _reason.trim();
    if (previous != null && reason.isEmpty) {
      setState(() => _error = 'Enter a correction reason.');
      return;
    }
    final visible = form.visibleFields(_answers);
    final answers = {
      for (final entry in _answers.entries)
        if (visible.contains(entry.key)) entry.key: entry.value,
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      widget.release.definition.validateAnswers(answers, formId: form.id);
      final grove = ref.read(bearingsGroveProvider);
      final observation = GamePackObservation(
        id: _id,
        event: EntityRef(widget.event),
        team:
            previous?.team ??
            (widget.team == null ? null : EntityRef(widget.team!)),
        match:
            previous?.match ??
            (widget.match == null ? null : EntityRef(widget.match!)),
        gamePack: EntityRef(widget.release.id),
        station: previous?.station ?? widget.station,
        scout: previous?.scout,
        form: form.id,
        capturedAt: _timestamp,
        answers: answers,
        supersedes: previous == null ? null : EntityRef(previous.id),
        reason: previous == null ? null : reason,
      );
      if (previous == null) {
        await grove.stageCreate(observation);
      } else {
        await grove.create(observation, allowOffline: false);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException ? error.message : '$error',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = _form;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      bottomNavigationBar: form == null || !widget.writable
          ? null
          : SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error case final message?)
                    Text(
                      message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(LucideIcons.check),
                    label: Text(
                      _saving
                          ? 'Saving…'
                          : widget.previous == null
                          ? 'Save observation'
                          : 'Save correction',
                    ),
                  ),
                ],
              ),
            ),
      body: form == null
          ? Center(
              child: Text(
                '${widget.kind.label} is unavailable for this event.',
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: form.pages.any((page) => page.usesGrid)
                      ? double.infinity
                      : 850,
                ),
                child: Form(
                  key: _validation,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: GamePackFormView(
                            fields: widget.release.definition.fieldById,
                            form: form,
                            answers: _answers,
                            enabled: widget.writable && !_saving,
                            onChanged: (answers) =>
                                setState(() => _answers = answers),
                          ),
                        ),
                        if (widget.writable && widget.previous != null)
                          TextFormField(
                            maxLength: 1000,
                            enabled: !_saving,
                            decoration: const InputDecoration(
                              labelText: 'Correction reason',
                            ),
                            onChanged: (value) => _reason = value,
                            validator: (value) => value?.trim().isEmpty == true
                                ? 'Enter a reason.'
                                : null,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
