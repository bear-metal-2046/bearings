import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/gamepack_analysis_provider.dart';
import 'package:ui/widgets/bearings_card.dart';
import 'package:ui/widgets/bearings_spinner.dart';
import 'package:ui/widgets/bearings_status_view.dart';

import 'gamepack_displays.dart';

class GamePackTeamObservations extends ConsumerWidget {
  const GamePackTeamObservations({
    super.key,
    required this.event,
    required this.team,
    required this.release,
    required this.kinds,
    this.notesOnly = false,
  });

  final String event;
  final String team;
  final GamePack release;
  final Set<GamePackFormKind> kinds;
  final bool notesOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final definition = release.definition;
    final forms = {
      for (final form in definition.forms.where(
        (form) => kinds.contains(form.kind),
      ))
        form.id: form,
    };
    return ref
        .watch(activeGamePackObservationsProvider(event))
        .when(
          loading: () => const Center(child: BearingsSpinner()),
          error: (error, _) => BearingsStatusView(
            icon: LucideIcons.circleAlert,
            title: 'Observations unavailable',
            subtitle: '$error',
          ),
          data: (active) {
            final cards = <Widget>[];
            for (final row in active) {
              if (row.team?.id != team || row.gamePack.id != release.id) {
                continue;
              }
              final form = forms[row.formId];
              if (form == null) continue;
              final noteFields =
                  notesOnly &&
                      (form.kind == GamePackFormKind.match ||
                          form.kind == GamePackFormKind.pit)
                  ? form.controls
                        .where(
                          (control) =>
                              control.type == GamePackControlType.multiline,
                        )
                        .map((control) => control.field)
                        .toSet()
                  : null;
              if (noteFields != null &&
                  !noteFields.any(
                    (field) =>
                        row.answers[field] is String &&
                        (row.answers[field] as String).trim().isNotEmpty,
                  )) {
                continue;
              }
              cards.add(
                GamePackObservationCard(
                  observation: row,
                  release: release,
                  fields: noteFields,
                ),
              );
            }
            if (cards.isEmpty) {
              return BearingsStatusView(
                icon: LucideIcons.fileText,
                title: 'No observations recorded',
              );
            }
            return BearingsCardList(children: cards);
          },
        );
  }
}

class GamePackObservationCard extends StatelessWidget {
  const GamePackObservationCard({
    super.key,
    required this.observation,
    required this.release,
    this.fields,
    this.actions = const [],
  });

  final GamePackObservation observation;
  final GamePack release;
  final Set<String>? fields;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final row = observation;
    final definition = release.definition;
    final form = definition.formById(row.formId);
    final values = row.isRetraction
        ? const <String, GamePackValue>{}
        : definition.decodeAnswers(row.answers, formId: row.formId);
    final localTime = row.capturedAt.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final time =
        '${localizations.formatShortDate(localTime)} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(localTime))}';
    return Card.outlined(
      child: ExpansionTile(
        title: Text(
          [
            form.label,
            if (row.match != null) row.match!.id,
            if (row.team != null) row.team!.id,
          ].join(' · '),
        ),
        subtitle: Text(
          [
            if (row.isRetraction)
              'Retracted'
            else if (row.supersedes != null)
              'Correction',
            time,
          ].join(' · '),
        ),
        children: [
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 8, runSpacing: 6, children: actions),
            ),
          if (row.reason case final reason?)
            ListTile(title: Text(reason), subtitle: const Text('Reason')),
          for (final control in form.controls)
            if (values.containsKey(control.field) &&
                (fields == null || fields!.contains(control.field)))
              ListTile(
                title: Text(definition.fieldById[control.field]!.label),
                subtitle: Text(formatGamePackValue(values[control.field]!)),
              ),
        ],
      ),
    );
  }
}
