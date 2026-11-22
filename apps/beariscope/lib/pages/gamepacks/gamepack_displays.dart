import 'dart:convert';

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/widgets/bearings_modal.dart';
import 'package:services/providers/gamepack_analysis_provider.dart';

Future<void> showGamePackEvidence(
  BuildContext context,
  GamePackEventAnalysis analysis,
  GamePackEvidenceRef source,
) {
  final document = analysis.evidenceDocument(source);
  return BearingsModal.show<void>(
    context,
    builder: (_) => BearingsModal(
      title: source.id,
      actions: const [],
      size: BearingsModalSize.tall,
      content: SelectableText(
        document == null
            ? 'Source record unavailable.'
            : const JsonEncoder.withIndent('  ').convert(document),
      ),
    ),
  );
}

String formatGamePackValue(GamePackValue value) => switch (value.state) {
  GamePackValueState.missing => 'Missing',
  GamePackValueState.unknown => 'Unknown',
  GamePackValueState.notApplicable => 'Not applicable',
  GamePackValueState.known => switch (value.data) {
    true => 'Yes',
    false => 'No',
    final double number => number.toString().replaceFirst(RegExp(r'\.0$'), ''),
    _ => value.toString(),
  },
};
