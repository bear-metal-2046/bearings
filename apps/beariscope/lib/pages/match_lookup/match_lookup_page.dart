import 'package:beariscope/pages/main_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/pages/match_lookup/match_providers.dart';
import 'package:beariscope/pages/match_lookup/match_card.dart';
import 'package:material_symbols_icons/symbols.dart';

class MatchLookupPage extends ConsumerStatefulWidget {
  const MatchLookupPage({super.key});

  @override
  ConsumerState<MatchLookupPage> createState() => _MatchLookupPageState();
}

class _MatchLookupPageState extends ConsumerState<MatchLookupPage> {
  Alliances _selectedAlliance = Alliances.all;

  @override
  Widget build(BuildContext context) {
    final controller = MainViewController.of(context);
    final teamsAsync = ref.watch(teamsProvider);
    final filteredMatches = ref.watch(filteredMatchesProvider);
    final t1 = ref.watch(team1SearchProvider);
    final t2 = ref.watch(team2SearchProvider);

    final teams = teamsAsync.maybeWhen(
      data: (data) => data
          .whereType<Map<String, dynamic>>()
          .map((json) => Team.fromJson(json))
          .toList(),
      orElse: () => <Team>[],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Match Lookup'),
        leading: controller.isDesktop
            ? null
            : IconButton(
                icon: const Icon(Symbols.menu_rounded),
                onPressed: controller.openDrawer,
              ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildTeamDropdown(
                        hint: 'Team 1',
                        onSelected: (team) =>
                            ref.read(team1SearchProvider.notifier).state = team
                                .number
                                .toString(),
                        onCleared: () =>
                            ref.read(team1SearchProvider.notifier).state = '',
                        teams: teams,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTeamDropdown(
                        hint: 'Team 2',
                        onSelected: (team) =>
                            ref.read(team2SearchProvider.notifier).state = team
                                .number
                                .toString(),
                        onCleared: () =>
                            ref.read(team2SearchProvider.notifier).state = '',
                        teams: teams,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            Center(
              child: SizedBox(
                width: 600,
                child: SegmentedButton<Alliances>(
                  segments: const [
                    ButtonSegment(value: Alliances.same, label: Text('Same')),
                    ButtonSegment(
                      value: Alliances.opposite,
                      label: Text('Opposite'),
                    ),
                    ButtonSegment(value: Alliances.all, label: Text('All')),
                  ],
                  selected: {_selectedAlliance},
                  onSelectionChanged: (newSelection) {
                    setState(() => _selectedAlliance = newSelection.first);
                    ref.read(allianceFilterProvider.notifier).state =
                        newSelection.first;
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: filteredMatches.when(
                data: (matches) {
                  if ((t1?.isEmpty ?? true) || (t2?.isEmpty ?? true)) {
                    return const Center(
                      child: Text('Search for two teams to see matches'),
                    );
                  }

                  final seenKeys = <String>{};
                  final uniqueMatches = matches
                      .where((m) => seenKeys.add(m['key'] ?? ''))
                      .toList();

                  if (uniqueMatches.isEmpty) {
                    return const Center(
                      child: Text('No matches found for these criteria.'),
                    );
                  }

                  return ListView.builder(
                    itemCount: uniqueMatches.length,
                    itemBuilder: (context, index) => MatchCard(
                      match: uniqueMatches[index],
                      highlightTeams: [t1!, t2!],
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error: $err')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamDropdown({
    required String hint,
    required ValueChanged<Team> onSelected,
    required VoidCallback onCleared,
    required List<Team> teams,
  }) {
    return Autocomplete<Team>(
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) return const Iterable<Team>.empty();
        final input = textEditingValue.text.toLowerCase();
        return teams.where(
          (team) =>
              team.name.toLowerCase().contains(input) ||
              team.number.toString().contains(input),
        );
      },
      displayStringForOption: (team) => '${team.number} ${team.name}',
      onSelected: (team) => onSelected(team),
      fieldViewBuilder:
          (context, textController, focusNode, onEditingComplete) {
            return TextField(
              controller: textController,
              focusNode: focusNode,
              onChanged: (value) {
                if (value.isEmpty) onCleared();
              },
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            );
          },
    );
  }
}
