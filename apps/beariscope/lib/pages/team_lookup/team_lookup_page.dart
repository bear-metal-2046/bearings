// dart format width=120

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:beariscope/models/match_field_ids.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/rankings_provider.dart';
import 'package:beariscope/providers/team_scouting_provider.dart';
import 'package:beariscope/widgets/beariscope_card.dart';
import 'package:beariscope/widgets/team_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/providers/api_provider.dart';

final collectedTeamsProvider = StateProvider<List<String>>((ref) => []);
final isDraggingProvider = StateProvider<bool>((ref) => false);
final picklistSheetHoverHapticPlayedProvider = StateProvider<bool>((ref) => false);
final picklistSheetHeaderOnlyProvider = StateProvider<bool>((ref) => true);

enum PicklistSheetState { hidden, dragging, collapsed, expanded }

final picklistSheetStateProvider = StateProvider<PicklistSheetState>((ref) {
  return PicklistSheetState.hidden;
});

class PicklistSheetConfig {
  final double height;
  final bool raiseSearchBar;

  const PicklistSheetConfig({required this.height, required this.raiseSearchBar});
}

PicklistSheetConfig picklistSheetConfigForState(PicklistSheetState state) {
  switch (state) {
    case PicklistSheetState.hidden:
      return const PicklistSheetConfig(height: 0, raiseSearchBar: false);

    case PicklistSheetState.dragging:
      return const PicklistSheetConfig(height: 180, raiseSearchBar: false);

    case PicklistSheetState.collapsed:
      return const PicklistSheetConfig(height: 72, raiseSearchBar: true);

    case PicklistSheetState.expanded:
      return const PicklistSheetConfig(height: 700, raiseSearchBar: true);
  }
}

class TeamLookupPage extends ConsumerStatefulWidget {
  const TeamLookupPage({super.key});

  @override
  ConsumerState<TeamLookupPage> createState() => _TeamLookupPageState();
}

class _TeamLookupPageState extends ConsumerState<TeamLookupPage> with SingleTickerProviderStateMixin {
  final TextEditingController _searchTermTEC = TextEditingController();
  final ValueNotifier<double> _sheetHeightNotifier = ValueNotifier<double>(0);

  late final AnimationController _sheetAnimationController;

  late Animation<double> _sheetHeightAnimation;

  double _sheetMaxHeight = 700;

  bool _isUserDraggingSheet = false;
  bool _didRestoreSheetHeight = false;

  @override
  void initState() {
    super.initState();

    _sheetAnimationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));

    _sheetHeightAnimation = Tween<double>(
      begin: 0,
      end: 0,
    ).animate(CurvedAnimation(parent: _sheetAnimationController, curve: Curves.easeOutCirc));

    _sheetAnimationController.addListener(() {
      if (!_isUserDraggingSheet) {
        _sheetHeightNotifier.value = _sheetHeightAnimation.value;
      }
    });

    ref.listenManual<PicklistSheetState>(picklistSheetStateProvider, (_, next) {
      if (_isUserDraggingSheet) {
        return;
      }

      _animateToState(next);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final currentState = ref.read(picklistSheetStateProvider);
    if (currentState == PicklistSheetState.hidden || _isUserDraggingSheet) {
      return;
    }

    final double targetHeight = switch (currentState) {
      PicklistSheetState.collapsed =>
        picklistSheetConfigForState(currentState).height + MediaQuery.of(context).padding.bottom,
      PicklistSheetState.expanded => _sheetMaxHeight,
      _ => 0,
    };

    if (!_didRestoreSheetHeight) {
      _didRestoreSheetHeight = true;
      _sheetHeightNotifier.value = targetHeight;
      return;
    }

    if ((_sheetHeightNotifier.value - targetHeight).abs() > 0.5) {
      _animateToState(currentState);
    }
  }

  void _animateToState(PicklistSheetState state) {
    final targetHeight = switch (state) {
      PicklistSheetState.collapsed => picklistSheetConfigForState(state).height + MediaQuery.of(context).padding.bottom,
      PicklistSheetState.expanded => _sheetMaxHeight,
      _ => picklistSheetConfigForState(state).height,
    };

    _sheetHeightAnimation = Tween<double>(
      begin: _sheetHeightNotifier.value,
      end: targetHeight,
    ).animate(CurvedAnimation(parent: _sheetAnimationController, curve: Curves.easeOutCirc));

    _sheetAnimationController
      ..reset()
      ..forward();
  }

  void _snapSheet({required double velocity}) {
    final collapsedHeight = picklistSheetConfigForState(PicklistSheetState.collapsed).height;
    final midpoint = (collapsedHeight + _sheetMaxHeight) / 2;

    final targetState = velocity.abs() > 150
        ? (velocity < 0 ? PicklistSheetState.expanded : PicklistSheetState.collapsed)
        : (_sheetHeightNotifier.value >= midpoint ? PicklistSheetState.expanded : PicklistSheetState.collapsed);

    final currentState = ref.read(picklistSheetStateProvider);

    if (currentState == targetState) {
      _animateToState(targetState);
      return;
    } else {
      HapticFeedback.lightImpact(); // Only haptic when state actually changes
    }

    ref.read(picklistSheetStateProvider.notifier).state = targetState;
  }

  @override
  void dispose() {
    _searchTermTEC.dispose();
    _sheetHeightNotifier.dispose();
    _sheetAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = MainViewController.of(context);
    final selectedEvent = ref.watch(currentEventProvider);
    final teamsAsync = ref.watch(teamsProvider);

    final selectedSort = ref.watch(teamSortProvider);
    final rankingsAsync = ref.watch(eventRankingsProvider);
    final rankings = switch (rankingsAsync) {
      AsyncData(:final value) => value,
      _ => const <int, TeamRanking>{},
    };
    bool isAscending = ref.read(teamSortProvider.notifier).getIsAscending();

    Future<void> onRefresh() async {
      final client = ref.read(honeycombClientProvider);
      client.invalidateCache('/teams', queryParams: {'event': selectedEvent});
      client.invalidateCache('/rankings', queryParams: {'event': selectedEvent});
      client.invalidateCache('/event/$selectedEvent/team_media');
      ref.invalidate(teamsProvider);
      ref.invalidate(eventRankingsProvider);
      ref.invalidate(eventTeamMediaProvider);
      try {
        await Future.wait([
          ref.read(teamsProvider.future),
          ref.read(eventRankingsProvider.future),
          ref.read(eventTeamMediaProvider.future),
        ]);
      } catch (_) {
        // Keep current cached data visible if refresh fails.
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Teams'),
        leading: controller.isDesktop
            ? null
            : IconButton(icon: const Icon(LucideIcons.menu), onPressed: controller.openDrawer),
        actions: [
          PopupMenuButton<TeamSortOptions>(
            icon: Icon(isAscending ? LucideIcons.arrowUpNarrowWide : LucideIcons.arrowDownWideNarrow),
            tooltip: 'Sort',
            itemBuilder: (context) => TeamSortOptions.values
                .map(
                  (sort) => CheckedPopupMenuItem<TeamSortOptions>(
                    value: sort,
                    checked: selectedSort.sort == sort,
                    child: Row(
                      children: [
                        Text(sort.label),
                        if (selectedSort.sort == sort) Icon(isAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                )
                .toList(),
            onSelected: (TeamSortOptions newSort) {
              if (ref.read(teamSortProvider.notifier).getSort() == newSort) {
                isAscending = !isAscending;
              }

              ref.read(teamSortProvider.notifier).setSort(newSort, isAscending);
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final picklistSheetState = ref.watch(picklistSheetStateProvider);
          final collapsedHeight = picklistSheetConfigForState(PicklistSheetState.collapsed).height;
          final expandedHeight = picklistSheetConfigForState(PicklistSheetState.expanded).height;
          _sheetMaxHeight = math.min(expandedHeight, constraints.maxHeight - 24);

          final double searchBarBottom = picklistSheetConfigForState(picklistSheetState).raiseSearchBar
              ? collapsedHeight + 8
              : 8;

          return Stack(
            children: [
              teamsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(child: Text('Error: $error')),
                data: (teams) {
                  final collectedTeams = ref.watch(collectedTeamsProvider);

                  final teamList = teams.whereType<Map<String, dynamic>>().map((json) => Team.fromJson(json)).toList();

                  final searchTerm = _searchTermTEC.text.trim().toLowerCase();

                  var filteredTeams = searchTerm.isEmpty
                      ? teamList
                      : teamList.where((team) {
                          final teamName = team.name.toLowerCase();

                          final teamNumber = team.number.toString();

                          final teamKey = team.key.toLowerCase();

                          return teamName.contains(searchTerm) ||
                              teamNumber.contains(searchTerm) ||
                              teamKey.contains(searchTerm);
                        }).toList();

                  filteredTeams = List.of(filteredTeams);

                  final customSortScores = <int, double>{};
                  if (selectedSort.sort == TeamSortOptions.custom) {
                    for (final team in filteredTeams) {
                      customSortScores[team.number] = ref
                          .watch(teamScoutingProvider(team.number))
                          .when(
                            data: (bundle) =>
                                bundle.avgMatchField(kSectionTele, kTeleFuelScored) +
                                bundle.avgMatchField(kSectionAuto, kAutoFuelScored),
                            error: (_, _) => 0,
                            loading: () => 0,
                          );
                    }
                  }

                  switch (selectedSort.sort) {
                    case TeamSortOptions.teamNumber:
                      if (isAscending) {
                        filteredTeams.sort((a, b) => a.number.compareTo(b.number));
                      } else {
                        filteredTeams.sort((a, b) => b.number.compareTo(a.number));
                      }
                    case TeamSortOptions.rank:
                      if (isAscending) {
                        filteredTeams.sort((a, b) {
                          // Teams without a rank go to the end
                          final rankA = rankings[a.number]?.rank ?? 999999;
                          final rankB = rankings[b.number]?.rank ?? 999999;
                          return rankA.compareTo(rankB);
                        });
                      } else {
                        filteredTeams.sort((a, b) {
                          final rankA = rankings[a.number]?.rank ?? 0;
                          final rankB = rankings[b.number]?.rank ?? 0;
                          return rankB.compareTo(rankA);
                        });
                      }
                    case TeamSortOptions.custom:
                      filteredTeams.sort((a, b) {
                        final rankA = customSortScores[a.number] ?? 0;
                        final rankB = customSortScores[b.number] ?? 0;
                        if (isAscending) {
                          return rankA.compareTo(rankB);
                        } else {
                          return rankB.compareTo(rankA);
                        }
                      });
                  }

                  if (filteredTeams.isEmpty) {
                    return const Center(child: Text('No teams found'));
                  }

                  return RefreshIndicator(
                    onRefresh: onRefresh,
                    child: BeariscopeCardList(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                      children: filteredTeams.map((team) {
                        final isCollected = collectedTeams.contains(team.key);

                        return LongPressDraggable<String>(
                          data: team.key,
                          maxSimultaneousDrags: isCollected ? 0 : null,
                          onDragStarted: () {
                            HapticFeedback.selectionClick();

                            ref.read(isDraggingProvider.notifier).state = true;

                            ref.read(picklistSheetStateProvider.notifier).state = PicklistSheetState.dragging;
                          },
                          onDragEnd: (_) {
                            ref.read(isDraggingProvider.notifier).state = false;

                            final teams = ref.read(collectedTeamsProvider);

                            ref.read(picklistSheetStateProvider.notifier).state = teams.isEmpty
                                ? PicklistSheetState.hidden
                                : PicklistSheetState.collapsed;
                          },
                          feedback: SizedBox(
                            width: math.min(constraints.maxWidth - 32, 600),
                            child: Transform.rotate(
                              angle: 0.05,
                              child: Material(
                                elevation: 16,
                                color: Colors.transparent,
                                child: Opacity(opacity: 0.95, child: TeamCard(teamKey: team.key)),
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(opacity: 0.5, child: TeamCard(teamKey: team.key)),
                          child: Opacity(
                            opacity: isCollected ? 0.5 : 1,
                            child: TeamCard(teamKey: team.key),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),

              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                left: 8,
                right: 8,
                bottom: searchBarBottom,
                child: SafeArea(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragEnd: (details) {
                      if ((details.primaryVelocity ?? 0) > 0) {
                        FocusScope.of(context).unfocus();
                      }
                    },
                    child: SearchBar(
                      controller: _searchTermTEC,
                      hintText: 'Team name or number',
                      padding: const WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.symmetric(horizontal: 16.0)),
                      leading: const Icon(LucideIcons.search),
                      trailing: _searchTermTEC.text.isNotEmpty
                          ? [
                              IconButton(
                                icon: const Icon(LucideIcons.x),
                                onPressed: () {
                                  _searchTermTEC.clear();
                                  setState(() {});
                                },
                              ),
                            ]
                          : null,
                      onChanged: (_) {
                        setState(() {});
                      },
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<double>(
                valueListenable: _sheetHeightNotifier,
                builder: (context, sheetHeight, _) {
                  if (sheetHeight <= 0) {
                    return const SizedBox.shrink();
                  }

                  return Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: math.min(sheetHeight, _sheetMaxHeight),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragStart:
                          picklistSheetState == PicklistSheetState.collapsed ||
                              picklistSheetState == PicklistSheetState.expanded
                          ? (_) {
                              _isUserDraggingSheet = true;

                              _sheetAnimationController.stop();
                            }
                          : null,
                      onVerticalDragUpdate:
                          picklistSheetState == PicklistSheetState.collapsed ||
                              picklistSheetState == PicklistSheetState.expanded
                          ? (details) {
                              _sheetHeightNotifier.value = (_sheetHeightNotifier.value - details.delta.dy)
                                  .clamp(collapsedHeight, _sheetMaxHeight)
                                  .toDouble();
                            }
                          : null,
                      onVerticalDragEnd:
                          picklistSheetState == PicklistSheetState.collapsed ||
                              picklistSheetState == PicklistSheetState.expanded
                          ? (details) {
                              _isUserDraggingSheet = false;

                              _snapSheet(velocity: details.primaryVelocity ?? 0);
                            }
                          : null,
                      child: TeamPicklistSheet(
                        state: picklistSheetState,
                        expanded:
                            math.min(sheetHeight, _sheetMaxHeight) >
                            picklistSheetConfigForState(PicklistSheetState.collapsed).height +
                                MediaQuery.of(context).padding.bottom +
                                2, // 2 is height of the divider, just to make it clear
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class TeamPicklistSheet extends ConsumerStatefulWidget {
  final PicklistSheetState state;
  final bool expanded;

  const TeamPicklistSheet({super.key, required this.state, required this.expanded});

  @override
  ConsumerState<TeamPicklistSheet> createState() => _TeamPicklistSheetState();
}

class _TeamPicklistSheetState extends ConsumerState<TeamPicklistSheet> {
  bool _lastReached = false;
  bool _showCopyCheck = false;
  Timer? _copyIconResetTimer;

  void _handleCopyTeamNumbers(List<String> collectedTeams) {
    final teamNumbers = collectedTeams
        .map((teamKey) => RegExp(r'\d+').firstMatch(teamKey)?.group(0) ?? teamKey)
        .join(',');

    Clipboard.setData(ClipboardData(text: teamNumbers));

    setState(() {
      _showCopyCheck = true;
    });

    _copyIconResetTimer?.cancel();
    _copyIconResetTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;

      setState(() {
        _showCopyCheck = false;
      });
    });
  }

  @override
  void dispose() {
    _copyIconResetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collectedTeams = ref.watch(collectedTeamsProvider);
    final headerOnly = ref.watch(picklistSheetHeaderOnlyProvider);

    final isDragging = ref.watch(isDraggingProvider);

    final teamsAsync = ref.watch(teamsProvider);
    String describeTeam(String teamKey) {
      return teamsAsync.when(
        loading: () => teamKey,
        error: (_, _) => teamKey,
        data: (teams) {
          final teamList = teams.whereType<Map<String, dynamic>>().map((json) => Team.fromJson(json)).toList();

          for (final team in teamList) {
            if (team.key == teamKey || team.number.toString() == teamKey) {
              return '${team.name} (${team.number})';
            }
          }

          return teamKey;
        },
      );
    }

    final theme = Theme.of(context);

    return DragTarget<String>(
      onMove: (details) {
        if (ref.read(picklistSheetHoverHapticPlayedProvider)) {
          return;
        }

        HapticFeedback.selectionClick();
        ref.read(picklistSheetHoverHapticPlayedProvider.notifier).state = true;
      },
      onLeave: (data) {
        ref.read(picklistSheetHoverHapticPlayedProvider.notifier).state = false;
      },
      onAcceptWithDetails: (details) {
        final teamKey = details.data;

        final currentList = ref.read(collectedTeamsProvider);

        if (!currentList.contains(teamKey)) {
          HapticFeedback.mediumImpact();

          ref.read(collectedTeamsProvider.notifier).state = [...currentList, teamKey];

          ref.read(picklistSheetHoverHapticPlayedProvider.notifier).state = false;

          ref.read(picklistSheetStateProvider.notifier).state = PicklistSheetState.collapsed;
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: isHovering ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.1),
                blurRadius: 20,
                spreadRadius: 5,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: isDragging
                ? Stack(
                    fit: StackFit.expand,
                    alignment: AlignmentGeometry.center,
                    children: [
                      Positioned(
                        top: 12,
                        child: Container(
                          height: 4,
                          width: 32,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurfaceVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.arrowDownToLine, color: theme.colorScheme.primary, size: 32),
                          const SizedBox(height: 8),
                          Flexible(
                            child: Text(
                              collectedTeams.isEmpty
                                  ? 'Drop to start a picklist'
                                  : 'Drop to add below ${describeTeam(collectedTeams.last)}',
                              textAlign: TextAlign.center,
                              softWrap: true,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Column(
                    children: [
                      SizedBox(
                        height: 72,
                        child: Stack(
                          alignment: AlignmentGeometry.center,
                          children: [
                            Positioned(
                              top: 0,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  final currentState = ref.read(picklistSheetStateProvider);

                                  if (currentState == PicklistSheetState.hidden ||
                                      currentState == PicklistSheetState.dragging) {
                                    return;
                                  }

                                  HapticFeedback.lightImpact();

                                  ref
                                      .read(picklistSheetStateProvider.notifier)
                                      .state = currentState == PicklistSheetState.expanded
                                      ? PicklistSheetState.collapsed
                                      : PicklistSheetState.expanded;
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Container(
                                    height: 4,
                                    width: 32,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 16,
                              child: Row(
                                children: [
                                  Container(
                                    height: 32,
                                    width: 32,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(LucideIcons.listOrdered, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Picklist', style: theme.textTheme.titleMedium),
                                      Text(
                                        '${collectedTeams.length} team${collectedTeams.length == 1 ? '' : 's'}',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (collectedTeams.isNotEmpty)
                              Positioned(
                                right: 16,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      key: const ValueKey('picklist-header-toggle'),
                                      tooltip: headerOnly ? 'Show Full Cards' : 'Show Labels Only',
                                      icon: Icon(
                                        headerOnly ? LucideIcons.panelTopOpen : LucideIcons.panelTopClose,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        ref.read(picklistSheetHeaderOnlyProvider.notifier).state = !headerOnly;
                                      },
                                    ),
                                    IconButton(
                                      tooltip: 'Clear picklist',
                                      icon: const Icon(LucideIcons.trash2, size: 20),
                                      onPressed: () async {
                                        final shouldClear = await showDialog<bool>(
                                          context: context,
                                          builder: (dialogContext) {
                                            return AlertDialog(
                                              title: const Text('Clear picklist?'),
                                              content: const Text('This will remove all teams from the picklist.'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () {
                                                    Navigator.of(dialogContext).pop(false);
                                                  },
                                                  child: const Text('Cancel'),
                                                ),
                                                TextButton(
                                                  onPressed: () {
                                                    Navigator.of(dialogContext).pop(true);
                                                  },
                                                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                                                  child: const Text('Clear'),
                                                ),
                                              ],
                                            );
                                          },
                                        );

                                        if (shouldClear != true) {
                                          return;
                                        }

                                        ref.read(collectedTeamsProvider.notifier).state = [];

                                        ref.read(picklistSheetStateProvider.notifier).state = PicklistSheetState.hidden;
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton.filledTonal(
                                      tooltip: 'Copy team numbers',
                                      icon: Icon(_showCopyCheck ? LucideIcons.check : LucideIcons.copy),
                                      style: ButtonStyle(
                                        foregroundColor: WidgetStateProperty.all(theme.colorScheme.onTertiaryContainer),
                                        backgroundColor: WidgetStateProperty.all(theme.colorScheme.tertiaryContainer),
                                      ),
                                      onPressed: () {
                                        _handleCopyTeamNumbers(collectedTeams);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (widget.expanded) const Divider(height: 2),

                      if (widget.expanded)
                        Expanded(
                          child: ReorderableListView.builder(
                            key: const PageStorageKey<String>('team_picklist_sheet_list'),
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),

                            buildDefaultDragHandles: false,
                            proxyDecorator: (child, index, animation) {
                              final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCirc);

                              return AnimatedBuilder(
                                animation: curved,
                                child: child,
                                builder: (context, child) {
                                  final t = curved.value;

                                  return Transform.scale(
                                    scale: lerpDouble(1.0, 1.03, t)!,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.shadow.withValues(alpha: lerpDouble(0.0, 0.18, t)!),
                                            blurRadius: lerpDouble(0, 24, t)!,
                                            spreadRadius: lerpDouble(0, 1, t)!,
                                            offset: Offset(0, lerpDouble(0, 8, t)!),
                                          ),
                                        ],
                                      ),
                                      child: child,
                                    ),
                                  );
                                },
                              );
                            },
                            onReorderStart: (_) {
                              HapticFeedback.selectionClick();
                            },
                            onReorderEnd: (_) {
                              HapticFeedback.selectionClick();
                            },
                            onReorderItem: (oldIndex, newIndex) {
                              final updatedTeams = [...collectedTeams];

                              final moved = updatedTeams.removeAt(oldIndex);
                              updatedTeams.insert(newIndex, moved);

                              ref.read(collectedTeamsProvider.notifier).state = updatedTeams;
                            },
                            itemCount: collectedTeams.length,
                            itemBuilder: (context, index) {
                              final teamKey = collectedTeams[index];

                              return Padding(
                                key: ValueKey(teamKey),
                                padding: const EdgeInsets.only(bottom: 8),
                                child: ReorderableDelayedDragStartListener(
                                  index: index,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Dismissible(
                                      key: ValueKey('dismiss-$teamKey'),
                                      direction: DismissDirection.endToStart,
                                      background: Container(
                                        alignment: Alignment.centerRight,
                                        padding: const EdgeInsets.symmetric(horizontal: 20),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.errorContainer,
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: Icon(LucideIcons.trash2, color: theme.colorScheme.error),
                                      ),
                                      onUpdate: (details) {
                                        if (details.reached != _lastReached) {
                                          _lastReached = details.reached;

                                          if (details.reached) {
                                            HapticFeedback.selectionClick();
                                          }
                                        }
                                      },
                                      onDismissed: (_) {
                                        final updatedTeams = [...collectedTeams]..remove(teamKey);

                                        ref.read(collectedTeamsProvider.notifier).state = updatedTeams;

                                        if (updatedTeams.isEmpty) {
                                          ref.read(picklistSheetStateProvider.notifier).state =
                                              PicklistSheetState.hidden;
                                        }
                                      },
                                      child: Row(
                                        mainAxisSize: MainAxisSize.max,
                                        children: [
                                          SizedBox(width: 20, child: Text('${index + 1}', textAlign: TextAlign.center)),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: TeamCard(teamKey: teamKey, headerOnly: headerOnly),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class SortByFieldItem extends StatefulWidget {
  final double total;
  final VoidCallback? onAddNew;

  const SortByFieldItem({super.key, required this.total, this.onAddNew});

  @override
  State<StatefulWidget> createState() {
    return SortByFieldItemState();
  }
}

class SortByFieldItemState extends State<SortByFieldItem> {
  String sectionId = '';
  String dataId = '';

  List<DropdownMenuEntry<String>> generateDropdownMenuItems(List<String> list) {
    List<DropdownMenuEntry<String>> finalList = [];
    for (var item in list) {
      finalList.add(DropdownMenuEntry(value: item, label: item));
    }
    return finalList;
  }

  List<String> sectionIdToDataPointsList(String sectionId) {
    switch (sectionId) {
      case 'auto':
        return kAutoDataList;
      case 'tele':
        return kTeleDataList;
      case 'endgame':
        return kEndgameDataList;
      default:
        return kTeleDataList;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Row(
        children: [
          DropdownMenu<String>(
            dropdownMenuEntries: generateDropdownMenuItems(kSectionsList),
            onSelected: (item) {
              if (item != null) {
                sectionId = item;
              }
            },
          ),
          DropdownMenu<String>(
            dropdownMenuEntries: generateDropdownMenuItems(sectionIdToDataPointsList(sectionId)),
            onSelected: (item) {
              if (item != null) {
                dataId = item;
              }
            },
          ),
          SizedBox.shrink(child: TextField(onChanged: (text) {})),
        ],
      ),
      trailing: ElevatedButton(
        onPressed: () {
          widget.onAddNew;
        },
        child: Icon(LucideIcons.circlePlus),
      ),
    );
  }
}
