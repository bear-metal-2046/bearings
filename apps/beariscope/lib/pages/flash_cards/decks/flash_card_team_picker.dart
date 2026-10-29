import 'package:beariscope/pages/flash_cards/decks/flash_card_deck_provider.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/widgets/beariscope_modal.dart';
import 'package:beariscope/widgets/beariscope_search_bar.dart';
import 'package:beariscope/widgets/beariscope_status_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

class FlashCardTeamPicker extends ConsumerStatefulWidget {
  const FlashCardTeamPicker({
    super.key,
    required this.eventKeys,
    required this.excludedTeams,
  });

  final Set<String> eventKeys;
  final Set<int> excludedTeams;

  @override
  ConsumerState<FlashCardTeamPicker> createState() =>
      _FlashCardTeamPickerState();
}

enum _TeamFilter { all, included, removed }

class _FlashCardTeamPickerState extends ConsumerState<FlashCardTeamPicker> {
  late final _excluded = {...widget.excludedTeams};
  final _search = TextEditingController();
  final _scroll = ScrollController();
  _TeamFilter _filter = _TeamFilter.all;

  @override
  void initState() {
    super.initState();
    _search.addListener(_searchChanged);
  }

  void _searchChanged() {
    setState(() {});
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toggle(int number) => setState(() {
    if (!_excluded.remove(number)) _excluded.add(number);
  });

  Future<void> _copyTeamNumbers(List<Team> teams) async {
    String message;
    try {
      await Clipboard.setData(
        ClipboardData(
          text: teams
              .where((team) => !_excluded.contains(team.number))
              .map((team) => team.number)
              .join(', '),
        ),
      );
      message = 'Team numbers copied.';
    } catch (_) {
      message = 'Could not copy the team numbers.';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rosters = {
      for (final event in widget.eventKeys)
        event: ref.watch(flashCardEventRosterProvider(event)),
    };
    final failed = rosters.values.any((roster) => roster.hasError);
    final ready = rosters.values.every((roster) => roster.asData != null);
    final teams = ready
        ? combineFlashCardRosters({
            for (final entry in rosters.entries)
              entry.key: entry.value.requireValue,
          })
        : <Team>[];
    final included = teams
        .where((team) => !_excluded.contains(team.number))
        .length;
    final removed = teams.length - included;
    final filtered = teams.where((team) {
      final isRemoved = _excluded.contains(team.number);
      return teamMatchesSearch(team, _search.text) &&
          switch (_filter) {
            _TeamFilter.all => true,
            _TeamFilter.included => !isRemoved,
            _TeamFilter.removed => isRemoved,
          };
    }).toList();
    final Widget? status = failed
        ? BeariscopeStatusView(
            icon: LucideIcons.users,
            title: 'Could not load all teams.',
            subtitle: 'Try again to edit the full roster.',
            action: TextButton(
              onPressed: () {
                for (final entry in rosters.entries) {
                  if (entry.value.hasError) {
                    ref.invalidate(flashCardEventRosterProvider(entry.key));
                  }
                }
              },
              child: const Text('Retry'),
            ),
          )
        : !ready
        ? const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        : filtered.isEmpty
        ? BeariscopeStatusView(
            icon: _filter == _TeamFilter.removed
                ? LucideIcons.circleCheck
                : LucideIcons.search,
            title: _filter == _TeamFilter.removed && _search.text.trim().isEmpty
                ? 'No removed teams'
                : 'No teams found.',
            subtitle:
                _filter == _TeamFilter.removed && _search.text.trim().isEmpty
                ? 'Every team is included in your deck.'
                : 'Try another name, number, or filter.',
          )
        : null;

    return BeariscopeModal(
      size: BeariscopeModalSize.tall,
      title: 'Teams',
      scrolling: BeariscopeModalScrolling.content,
      actions: [
        BeariscopeModalAction(
          label: 'Copy team numbers',
          icon: LucideIcons.copy,
          onPressed: ready && included > 0
              ? () => _copyTeamNumbers(teams)
              : null,
        ),
      ],
      primaryAction: BeariscopeModalPrimaryAction(
        label: 'Use $included ${included == 1 ? 'team' : 'teams'}',
        icon: LucideIcons.check,
        onPressed: ready ? () => Navigator.pop(context, _excluded) : null,
      ),
      content: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchBarTheme(
              data: theme.searchBarTheme.copyWith(
                backgroundColor: WidgetStatePropertyAll(
                  colors.surfaceContainerHighest,
                ),
              ),
              child: BeariscopeSearchBar(
                controller: _search,
                hintText: 'Find a team',
                elevation: 0,
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (filter, label) in [
                    (_TeamFilter.all, 'All ${teams.length}'),
                    (_TeamFilter.included, 'In deck $included'),
                    (_TeamFilter.removed, 'Removed $removed'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _filter == filter,
                        onSelected: ready
                            ? (_) {
                                setState(() => _filter = filter);
                                if (_scroll.hasClients) _scroll.jumpTo(0);
                              }
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            if (constraints.maxHeight >= 320)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Select the teams you want to study.',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            Expanded(
              child: Scrollbar(
                controller: _scroll,
                child: ListView.separated(
                  key: const ValueKey('team-picker-list'),
                  controller: _scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: status == null ? filtered.length : 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (status != null) return status;
                    final team = filtered[index];
                    final isRemoved = _excluded.contains(team.number);
                    final shape = RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    );
                    return Material(
                      color: colors.surfaceContainerLow,
                      shape: shape,
                      clipBehavior: Clip.antiAlias,
                      child: Tooltip(
                        message: isRemoved
                            ? 'Restore team ${team.number}'
                            : 'Remove team ${team.number}',
                        child: CheckboxListTile(
                          key: ValueKey('deck-team-${team.number}'),
                          shape: shape,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          value: !isRemoved,
                          onChanged: (_) => _toggle(team.number),
                          secondary: Container(
                            constraints: const BoxConstraints(minWidth: 64),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isRemoved
                                  ? colors.surfaceContainerHigh
                                  : colors.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${team.number}',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: isRemoved
                                    ? colors.onSurfaceVariant
                                    : colors.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text(
                            team.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: isRemoved
                                  ? colors.onSurfaceVariant
                                  : colors.onSurface,
                            ),
                          ),
                          subtitle: isRemoved
                              ? const Text('Removed from deck')
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
