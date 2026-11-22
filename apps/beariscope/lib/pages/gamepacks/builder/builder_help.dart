import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/widgets/bearings_modal.dart';

enum GamePackBuilderSection {
  forms('Scout forms', LucideIcons.clipboardList),
  metrics('Metrics', LucideIcons.calculator),
  outputHome('Views & exports', LucideIcons.layoutDashboard),
  card('Team card', LucideIcons.contact),
  details('Team details', LucideIcons.layoutDashboard),
  sorting('Sorting & filters', LucideIcons.listFilter),
  exports('Export sheets', LucideIcons.sheet),
  review('Review & publish', LucideIcons.clipboardCheck);

  const GamePackBuilderSection(this.label, this.icon);
  final String label;
  final IconData icon;

  static const outputs = [card, details, sorting, exports];

  String get description => switch (this) {
    forms => 'Design what scouts record.',
    metrics => 'Turn scouting answers and official scores into metrics.',
    outputHome => 'Choose where teammates see and export scouting results.',
    card => 'Choose what appears at a glance in team lists and match previews.',
    details =>
      'Build the detailed view for Team Lookup and picklist Quick View.',
    sorting => 'Choose how teammates can sort and filter team lists.',
    exports => 'Choose the columns and rows in the scouting workbook.',
    review => 'Check your draft before creating a release.',
  };

  List<(String, String)> get tips => switch (this) {
    forms => [
      (
        'Choose a scouting form',
        'Match scouting, strategy scouting, pit scouting, and observations each have a starter page.',
      ),
      (
        'Add questions',
        'Enter a label and answer type. Every question is available as an input to metrics and outputs.',
      ),
      (
        'Preview your form',
        'Try answering the questions and check any visibility rules.',
      ),
    ],
    metrics => [
      (
        'Build a calculation',
        'Start with a value from scouting or official data. Add a step such as Average to transform it.',
      ),
      (
        'Link a TBA value',
        'Switch to Official values and choose a field from the current test data.',
      ),
      (
        'Edit test data',
        'Choose a season event for official scores and add test scouting reports using your draft forms.',
      ),
    ],
    outputHome => [
      (
        'Choose an output',
        'Edit team cards, team details, sorting and filters, or the export workbook.',
      ),
    ],
    card || details => [
      (
        'Add a block',
        'Choose a metric row, chart, or another display that fits the team view.',
      ),
      (
        'Choose the values',
        'Use a scouting answer, an official score, or a calculation.',
      ),
      (
        'Check the preview',
        'Open Edit test data in the app bar to change the inputs used in previews.',
      ),
    ],
    sorting => [
      ('Add a sort', 'Choose which metric can order the team list.'),
      (
        'Add a filter',
        'Choose a value and condition teammates can use to narrow a team list.',
      ),
    ],
    exports => [
      (
        'Add a sheet',
        'Choose whether each row represents a team, match, or scouting report.',
      ),
      (
        'Add columns',
        'Choose the values to include and arrange them in export order.',
      ),
    ],
    review => [
      (
        'Fix any issues',
        'Select an issue to open the area that needs attention.',
      ),
      (
        'Publish a release',
        'The published release appears in the GamePacks library. Pin it to the event when it is ready for collection.',
      ),
    ],
  };
}

Future<void> showGamePackBuilderHelp(
  BuildContext context,
  GamePackBuilderSection section,
) => BearingsModal.show<void>(
  context,
  builder: (_) => BearingsModal(
    title: 'Builder guide',
    actions: const [],
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(section.label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final (title, detail) in section.tips)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(title),
            subtitle: Text(detail),
          ),
      ],
    ),
  ),
);
