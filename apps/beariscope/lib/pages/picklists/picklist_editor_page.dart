import 'package:beariscope/pages/picklists/picklist_emoji.dart';
// dart format width=120

import 'dart:async';

import 'package:beariscope/pages/picklists/picklist_options_sheet.dart';

import 'package:beariscope/pages/picklists/picklist_presence_stack.dart';

import 'dart:math' as math;

import 'package:beariscope/models/match_field_ids.dart';
import 'package:beariscope/models/team_scouting_bundle.dart';
import 'package:beariscope/pages/picklists/picklist_model.dart';
import 'package:beariscope/pages/picklists/picklist_provider.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/providers/rankings_provider.dart';
import 'package:beariscope/providers/team_scouting_provider.dart';
import 'package:beariscope/widgets/beariscope_search_bar.dart';
import 'package:beariscope/widgets/beariscope_status_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

class PicklistEditorPage extends ConsumerStatefulWidget {
  final String picklistId;

  const PicklistEditorPage({super.key, required this.picklistId});

  @override
  ConsumerState<PicklistEditorPage> createState() => _PicklistEditorPageState();
}

class _PicklistEditorPageState extends ConsumerState<PicklistEditorPage>
    with SingleTickerProviderStateMixin {
  static const _collapsedSheetHeight = 64.0;

  final _dragPosition = ValueNotifier<Offset?>(null);
  final _dragPresentation = _DragPresentation();
  final _sheetHeight = ValueNotifier<double>(_collapsedSheetHeight);
  late final AnimationController _sheetController;
  late Animation<double> _sheetAnimation;
  Timer? _copyResetTimer;
  PicklistLibraryNotifier? _library;
  bool _showCopyCheck = false;
  bool _mobileLibraryExpanded = false;
  bool _isDesktopLayout = false;
  bool _draggingSheet = false;
  double _safeAreaBottom = 0;
  String? _draggingTeam;

  bool get _isDraggingTeam => _draggingTeam != null;
  double _mobileMaxHeight = 560;

  double get _collapsedSheetExtent => _collapsedSheetHeight + _safeAreaBottom;

  @override
  void initState() {
    super.initState();
    _sheetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _sheetAnimation = const AlwaysStoppedAnimation(_collapsedSheetHeight);
    _sheetController.addListener(() {
      if (!_draggingSheet) _sheetHeight.value = _sheetAnimation.value;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final previousCollapsedExtent = _collapsedSheetExtent;
    _safeAreaBottom = MediaQuery.paddingOf(context).bottom;
    if ((_sheetHeight.value - previousCollapsedExtent).abs() < .5) {
      _sheetHeight.value = _collapsedSheetExtent;
    }
  }

  @override
  void dispose() {
    _library?.close(widget.picklistId);
    _copyResetTimer?.cancel();
    _sheetController.dispose();
    _sheetHeight.dispose();
    _dragPosition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final picklist = ref
        .watch(picklistLibraryProvider)
        .where((item) => item.id == widget.picklistId)
        .firstOrNull;
    if (picklist == null) return _missingPicklist();

    _library = ref.read(picklistLibraryProvider.notifier);
    final session = _library!.open(picklist.id);
    final canEdit = _library!.canEdit(picklist);

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 850;
        _isDesktopLayout = desktop;

        final editor = _PicklistSurface(
          picklist: picklist,
          canEdit: canEdit,
          isDraggingTeam: _isDraggingTeam,
          dragPosition: _dragPosition,
          onDraggingChanged: _setTeamDragging,
          onInsertTeam: (teamKey, index) =>
              _insertTeam(picklist, teamKey, index),
          onRemoveTeam: (teamKey) => _removeTeam(picklist, teamKey),
        );

        return _DragPresentationScope(
          presentation: _dragPresentation,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).colorScheme.surface,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(1),
                child: Divider(height: 1, thickness: 1),
              ),
              leading: IconButton(
                tooltip: 'Back to Picklists',
                onPressed: () => context.go('/picklists'),
                icon: const Icon(LucideIcons.arrowLeft),
              ),
              titleSpacing: 0,
              title: Tooltip(
                message: canEdit
                    ? 'Edit picklist name and emoji'
                    : picklist.title,
                child: TextButton(
                  onPressed: canEdit
                      ? () => showPicklistOptions(context, ref, picklist)
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(48, 48),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PicklistEmoji(picklist.emoji, size: 26),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          picklist.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      if (canEdit) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.expand_more, size: 20),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                if (session != null)
                  PicklistPresenceStack(presence: session.presence),
                if (desktop)
                  IconButton(
                    tooltip: 'Copy team numbers',
                    onPressed: picklist.teamKeys.isEmpty
                        ? null
                        : () => _copyTeams(picklist.teamKeys),
                    icon: AnimatedSwitcher(
                      duration: _motionDuration(context),
                      child: Icon(
                        _showCopyCheck ? LucideIcons.check : LucideIcons.copy,
                        key: ValueKey(_showCopyCheck),
                      ),
                    ),
                  ),
                if (canEdit)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'clear') _confirmClear(picklist);
                      if (value == 'copy') _copyTeams(picklist.teamKeys);
                    },
                    tooltip: 'Picklist options',
                    itemBuilder: (context) => [
                      if (!desktop)
                        PopupMenuItem(
                          value: 'copy',
                          enabled: picklist.teamKeys.isNotEmpty,
                          child: ListTile(
                            leading: Icon(LucideIcons.copy),
                            title: Text('Copy team numbers'),
                          ),
                        ),
                      PopupMenuItem(
                        enabled: canEdit,
                        value: 'clear',
                        child: Row(
                          children: [
                            Icon(LucideIcons.trash2),
                            SizedBox(width: 12),
                            Text('Clear picklist'),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            body: LayoutBuilder(
              builder: (context, bodyConstraints) {
                _mobileMaxHeight = math.max(
                  _collapsedSheetExtent,
                  math.min(700, bodyConstraints.maxHeight * .8),
                );
                return desktop
                    ? SafeArea(
                        top: false,
                        child: _desktopBody(picklist, editor, canEdit),
                      )
                    : _mobileBody(picklist, editor, canEdit);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _desktopBody(Picklist picklist, Widget editor, bool canEdit) {
    if (!canEdit) return editor;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 340,
          child: _returnTarget(
            picklist,
            _TeamLibrary(
              returning: _isDraggingTeam,
              selectedTeamKeys: picklist.teamKeys.toSet(),
              onAdd: (teamKey) =>
                  _insertTeam(picklist, teamKey, picklist.teamKeys.length),
              onDraggingChanged: _setTeamDragging,
              onDragUpdate: (position) => _dragPosition.value = position,
            ),
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        Expanded(child: editor),
      ],
    );
  }

  Widget _mobileBody(Picklist picklist, Widget editor, bool canEdit) {
    if (!canEdit) return editor;
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: _collapsedSheetExtent),
          child: editor,
        ),
        ValueListenableBuilder<double>(
          valueListenable: _sheetHeight,
          builder: (context, height, _) => Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: height.clamp(_collapsedSheetExtent, _mobileMaxHeight),
            child: _returnTarget(
              picklist,
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.shadow
                          .withValues(alpha: .22),
                      blurRadius: 24,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  surfaceTintColor: Colors.transparent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleMobileLibrary,
                        onVerticalDragStart: (_) {
                          _draggingSheet = true;
                          _sheetController.stop();
                        },
                        onVerticalDragUpdate: (details) {
                          _sheetHeight
                              .value = (_sheetHeight.value - details.delta.dy)
                              .clamp(_collapsedSheetExtent, _mobileMaxHeight)
                              .toDouble();
                        },
                        onVerticalDragCancel: () {
                          _draggingSheet = false;
                          _snapMobileLibrary(0);
                        },
                        onVerticalDragEnd: (details) {
                          _draggingSheet = false;
                          _snapMobileLibrary(details.primaryVelocity ?? 0);
                        },
                        child: Semantics(
                          button: true,
                          label: 'Toggle team library',
                          child: _TeamLibraryHeader(
                            selectedCount: picklist.teamKeys.length,
                            expanded: height > _collapsedSheetExtent + 10,
                            returning: _isDraggingTeam,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: _safeAreaBottom),
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.topCenter,
                              minHeight: math.max(
                                160,
                                _mobileMaxHeight - _collapsedSheetExtent,
                              ),
                              maxHeight: math.max(
                                160,
                                _mobileMaxHeight - _collapsedSheetExtent,
                              ),
                              child: _TeamLibrary(
                                selectedTeamKeys: picklist.teamKeys.toSet(),
                                onAdd: (teamKey) => _insertTeam(
                                  picklist,
                                  teamKey,
                                  picklist.teamKeys.length,
                                ),
                                onDraggingChanged: _setTeamDragging,
                                onDragUpdate: (position) =>
                                    _dragPosition.value = position,
                                showHeader: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _setTeamDragging(String? value) {
    if (!mounted || _draggingTeam == value) return;
    setState(() => _draggingTeam = value);
    if (value == null) _dragPosition.value = null;
    if (value != null) FocusManager.instance.primaryFocus?.unfocus();
    if (!_isDesktopLayout) {
      _animateSheet(
        value != null
            ? _collapsedSheetExtent
            : (_mobileLibraryExpanded
                  ? _mobileMaxHeight
                  : _collapsedSheetExtent),
      );
    }
  }

  Widget _returnTarget(Picklist picklist, Widget child) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => _removeTeam(picklist, details.data),
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: _motionDuration(context),
        curve: Curves.easeOutCubic,
        foregroundDecoration: BoxDecoration(
          color: candidates.isNotEmpty
              ? Theme.of(context).colorScheme.primary.withValues(alpha: .12)
              : Colors.transparent,
          border: Border.all(
            color: candidates.isNotEmpty
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      ),
    );
  }

  void _removeTeam(Picklist picklist, String teamKey) {
    if (!(_library?.canEdit(picklist) ?? false)) return;
    _setTeamDragging(null);
    final index = picklist.teamKeys.indexOf(teamKey);
    if (index < 0) return;
    HapticFeedback.mediumImpact();
    ref.read(picklistLibraryProvider.notifier).removeTeam(picklist.id, teamKey);
  }

  void _insertTeam(Picklist picklist, String teamKey, int index) {
    if (!(_library?.canEdit(picklist) ?? false)) return;
    if (!_isDesktopLayout && _isDraggingTeam) _mobileLibraryExpanded = false;
    _setTeamDragging(null);
    HapticFeedback.mediumImpact();
    final teams = [...picklist.teamKeys];
    final previous = teams.indexOf(teamKey);
    if (previous >= 0) {
      teams.removeAt(previous);
      if (previous < index) index--;
    }
    teams.insert(index.clamp(0, teams.length), teamKey);
    ref.read(picklistLibraryProvider.notifier).setTeams(picklist.id, teams);
  }

  void _toggleMobileLibrary() {
    HapticFeedback.lightImpact();
    _mobileLibraryExpanded = !_mobileLibraryExpanded;
    _animateSheet(
      _mobileLibraryExpanded ? _mobileMaxHeight : _collapsedSheetExtent,
    );
  }

  void _snapMobileLibrary(double velocity) {
    final midpoint = (_mobileMaxHeight + _collapsedSheetExtent) / 2;
    final expand = velocity.abs() > 150
        ? velocity < 0
        : _sheetHeight.value >= midpoint;
    _mobileLibraryExpanded = expand;
    HapticFeedback.lightImpact();
    _animateSheet(expand ? _mobileMaxHeight : _collapsedSheetExtent);
  }

  void _animateSheet(double target) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _sheetController.stop();
      _sheetHeight.value = target;
      return;
    }
    _sheetAnimation = Tween<double>(begin: _sheetHeight.value, end: target)
        .animate(
          CurvedAnimation(parent: _sheetController, curve: Curves.easeOutCubic),
        );
    _sheetController
      ..reset()
      ..forward();
  }

  Widget _missingPicklist() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Picklist'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BeariscopeStatusView(
              icon: LucideIcons.listX,
              title: 'Picklist unavailable',
              subtitle: 'This picklist is not available for the current event.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/picklists'),
              child: const Text('Back to Picklists'),
            ),
          ],
        ),
      ),
    );
  }

  void _copyTeams(List<String> teamKeys) {
    final numbers = teamKeys
        .map((key) => RegExp(r'\d+').firstMatch(key)?.group(0) ?? key)
        .join(',');
    Clipboard.setData(ClipboardData(text: numbers));
    setState(() => _showCopyCheck = true);
    _copyResetTimer?.cancel();
    _copyResetTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _showCopyCheck = false);
    });
  }

  Future<void> _confirmClear(Picklist picklist) async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear this picklist?'),
        content: const Text(
          'All teams will be removed. The empty picklist will remain in your library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (clear == true) {
      ref.read(picklistLibraryProvider.notifier).setTeams(picklist.id, []);
    }
  }
}

class _TeamLibraryHeader extends StatelessWidget {
  final int selectedCount;
  final bool? expanded;
  final bool returning;

  const _TeamLibraryHeader({
    required this.selectedCount,
    this.expanded,
    this.returning = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (expanded != null)
            Positioned(
              top: 8,
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(LucideIcons.bot, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        returning ? 'Drop to return' : 'Library',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (MediaQuery.textScalerOf(context).scale(14) <= 17)
                        Text(
                          returning
                              ? 'Return to team library'
                              : '$selectedCount teams in picklist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                ),
                if (expanded != null)
                  Icon(
                    expanded! ? LucideIcons.chevronDown : LucideIcons.chevronUp,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamLibrary extends ConsumerStatefulWidget {
  final Set<String> selectedTeamKeys;
  final ValueChanged<String> onAdd;
  final ValueChanged<String?> onDraggingChanged;
  final ValueChanged<Offset> onDragUpdate;
  final bool showHeader;
  final bool returning;

  const _TeamLibrary({
    required this.selectedTeamKeys,
    required this.onAdd,
    required this.onDraggingChanged,
    required this.onDragUpdate,
    this.showHeader = true,
    this.returning = false,
  });

  @override
  ConsumerState<_TeamLibrary> createState() => _TeamLibraryState();
}

class _TeamLibraryState extends ConsumerState<_TeamLibrary> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_searchChanged);
  }

  void _searchChanged() => setState(() {});

  @override
  void dispose() {
    _searchController
      ..removeListener(_searchChanged)
      ..dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedSort = ref.watch(teamSortProvider);
    final rankings =
        ref.watch(eventRankingsProvider).value ?? const <int, TeamRanking>{};
    final mediaRecords =
        ref.watch(eventTeamMediaProvider).value ?? const <TeamMediaRecord>[];
    final avatarByTeam = <String, Uint8List>{};
    for (final record in mediaRecords) {
      if (!record.isAvatar || record.base64Image == null) continue;
      for (final key in record.teamKeys) {
        if (record.preferred || !avatarByTeam.containsKey(key)) {
          avatarByTeam[key] = record.base64Image!;
        }
      }
    }
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          if (widget.showHeader)
            _TeamLibraryHeader(
              selectedCount: widget.selectedTeamKeys.length,
              returning: widget.returning,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: BeariscopeSearchBar(
                    focusNode: _searchFocusNode,
                    controller: _searchController,
                    hintText: 'Team name or number',
                    elevation: 0,
                  ),
                ),
                PopupMenuButton<TeamSortOptions>(
                  tooltip: 'Sort teams',
                  icon: Icon(
                    selectedSort.isAscending
                        ? LucideIcons.arrowUpNarrowWide
                        : LucideIcons.arrowDownWideNarrow,
                  ),
                  itemBuilder: (context) => TeamSortOptions.values
                      .map(
                        (sort) => CheckedPopupMenuItem<TeamSortOptions>(
                          value: sort,
                          checked: selectedSort.sort == sort,
                          child: Text(sort.label),
                        ),
                      )
                      .toList(),
                  onSelected: (sort) {
                    final ascending = selectedSort.sort == sort
                        ? !selectedSort.isAscending
                        : sort == TeamSortOptions.teamNumber ||
                              sort == TeamSortOptions.rank;
                    ref
                        .read(teamSortProvider.notifier)
                        .setSort(sort, ascending);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ref
                .watch(teamsProvider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) =>
                      Center(child: Text('Could not load teams: $error')),
                  data: (rawTeams) {
                    final teams = rawTeams
                        .map(Team.fromJson)
                        .where(
                          (team) =>
                              teamMatchesSearch(team, _searchController.text),
                        )
                        .toList();
                    _sortTeams(teams, selectedSort, rankings);
                    if (teams.isEmpty) {
                      return const BeariscopeStatusView(
                        icon: LucideIcons.users,
                        title: 'No teams found',
                        subtitle: 'Try adjusting your search or selecting another event.',
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: teams.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) => Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: _draggableTeam(
                            teams[index],
                            avatarByTeam[teams[index].key],
                          ),
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  Widget _draggableTeam(Team team, [Uint8List? avatarBytes]) {
    final selected = widget.selectedTeamKeys.contains(team.key);
    return _EditorTeamTile(
      teamKey: team.key,
      team: team,
      avatarBytes: avatarBytes,
      selected: selected,
      onDraggingChanged: widget.onDraggingChanged,
      onDragUpdate: widget.onDragUpdate,
      action: IconButton(
        tooltip: selected ? 'Already in picklist' : 'Add team ${team.number}',
        onPressed: selected ? null : () => widget.onAdd(team.key),
        icon: Icon(selected ? LucideIcons.check : LucideIcons.plus, size: 20),
      ),
    );
  }

  void _sortTeams(
    List<Team> teams,
    TeamSort selectedSort,
    Map<int, TeamRanking> rankings,
  ) {
    final scores = <int, double>{};
    final safety = <int, (int, int, int)>{};
    final needsScouting =
        selectedSort.sort != TeamSortOptions.teamNumber &&
        selectedSort.sort != TeamSortOptions.rank;
    if (needsScouting) {
      for (final team in teams) {
        final bundle = ref.watch(teamScoutingProvider(team.number)).value;
        if (bundle == null) continue;
        scores[team.number] = _totalAverage(bundle);
        safety[team.number] = _safetyStats(bundle);
      }
    }
    teams.sort((a, b) {
      final comparison = switch (selectedSort.sort) {
        TeamSortOptions.teamNumber => a.number.compareTo(b.number),
        TeamSortOptions.rank => (rankings[a.number]?.rank ?? 999999).compareTo(
          rankings[b.number]?.rank ?? 999999,
        ),
        TeamSortOptions.custom => (scores[a.number] ?? 0).compareTo(
          scores[b.number] ?? 0,
        ),
        TeamSortOptions.defense => (safety[a.number]?.$1 ?? 0).compareTo(
          safety[b.number]?.$1 ?? 0,
        ),
        TeamSortOptions.noShow => (safety[a.number]?.$2 ?? 0).compareTo(
          safety[b.number]?.$2 ?? 0,
        ),
        TeamSortOptions.brokeDown => (safety[a.number]?.$3 ?? 0).compareTo(
          safety[b.number]?.$3 ?? 0,
        ),
      };
      return selectedSort.isAscending ? comparison : -comparison;
    });
  }
}

Duration _motionDuration(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 220);

class _PicklistTeamCard extends StatelessWidget {
  final String teamKey;
  final Team? team;
  final Uint8List? avatarBytes;

  const _PicklistTeamCard({required this.teamKey, this.team, this.avatarBytes});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          const SizedBox(width: 12),
          SizedBox(
            width: 32,
            height: 32,
            child: avatarBytes == null
                ? Icon(LucideIcons.bot, color: colors.onSurfaceVariant)
                : Image.memory(
                    avatarBytes!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) =>
                        Icon(LucideIcons.bot, color: colors.onSurfaceVariant),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team?.number.toString() ?? teamKey.replaceFirst('frc', ''),
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  team?.name ?? 'Team',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DragPresentation {
  final feedbackKey = GlobalKey();
  Widget Function(int? rank)? cardBuilder;
}

class _DragPresentationScope extends InheritedWidget {
  final _DragPresentation presentation;

  const _DragPresentationScope({
    required this.presentation,
    required super.child,
  });

  static _DragPresentation of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_DragPresentationScope>()!
      .presentation;

  @override
  bool updateShouldNotify(_DragPresentationScope oldWidget) =>
      presentation != oldWidget.presentation;
}

/// Continue the drag in the overlay until the real destination card is ready.
class _LandingTeamCard extends StatefulWidget {
  final Rect begin;
  final Rect Function() destination;
  final Widget sourceCard;
  final Widget destinationCard;
  final VoidCallback onComplete;

  const _LandingTeamCard({
    required this.begin,
    required this.destination,
    required this.sourceCard,
    required this.destinationCard,
    required this.onComplete,
  });

  @override
  State<_LandingTeamCard> createState() => _LandingTeamCardState();
}

class _LandingTeamCardState extends State<_LandingTeamCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 300),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) widget.onComplete();
        });
    // The reorder and scroll extent must finish layout before measuring the slot.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final progress = Curves.easeOutCubic.transform(_controller.value);
      final rect = progress == 0
          ? widget.begin
          : Rect.lerp(widget.begin, widget.destination(), progress)!;
      return Positioned.fromRect(
        rect: rect,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: Material(
              key: const ValueKey('picklist-landing-card'),
              // The flight already animates elevation every frame. Material's
              // implicit animation would lag behind and get cut off at landing.
              animationDuration: Duration.zero,
              elevation: 12 * (1 - progress),
              borderRadius: BorderRadius.circular(12),
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox(
                  width: rect.width,
                  height: 64,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      widget.sourceCard,
                      Opacity(opacity: progress, child: widget.destinationCard),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// One card presentation for the library, ranked list, and drag overlay.
/// Feedback uses the source width and density, so picking up a card never reshapes it.
class _EditorTeamTile extends StatelessWidget {
  final String teamKey;
  final Team? team;
  final Uint8List? avatarBytes;
  final bool selected;
  final bool draggable;
  final int? rank;
  final Widget action;
  final ValueChanged<String?> onDraggingChanged;
  final ValueChanged<Offset> onDragUpdate;

  const _EditorTeamTile({
    required this.teamKey,
    this.team,
    this.avatarBytes,
    required this.action,
    required this.onDraggingChanged,
    required this.onDragUpdate,
    this.selected = false,
    this.draggable = true,
    this.rank,
  });

  Widget _card(BuildContext context, {int? landingRank}) {
    final rank = landingRank ?? this.rank;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          if (rank != null)
            SizedBox(
              width: 28,
              child: AnimatedSwitcher(
                duration: _motionDuration(context),
                child: Text(
                  '$rank',
                  key: ValueKey(rank),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
          Expanded(
            child: _PicklistTeamCard(
              team: team,
              teamKey: teamKey,
              avatarBytes: avatarBytes,
            ),
          ),
          if (landingRank == null)
            action
          else
            const SizedBox(
              width: 48,
              height: 48,
              child: Icon(LucideIcons.gripVertical, size: 20),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final presentation = _DragPresentationScope.of(context);
      final card = AnimatedSize(
        duration: _motionDuration(context),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedOpacity(
          opacity: selected ? .5 : 1,
          duration: _motionDuration(context),
          child: _card(context),
        ),
      );
      if (selected || !draggable) return card;
      final feedback = SizedBox(
        width: constraints.maxWidth,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: _motionDuration(context),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Transform.scale(
            scale: 1 + .025 * value,
            child: Material(
              key: presentation.feedbackKey,
              animationDuration: Duration.zero,
              elevation: 12 * value,
              borderRadius: BorderRadius.circular(12),
              child: child,
            ),
          ),
          child: _card(context),
        ),
      );
      void start() {
        presentation.cardBuilder = (rank) => _card(context, landingRank: rank);
        HapticFeedback.selectionClick();
        onDraggingChanged(teamKey);
      }

      final placeholder = AnimatedOpacity(
        opacity: .2,
        duration: _motionDuration(context),
        child: card,
      );
      return _AdaptiveTeamDrag(
        teamKey: teamKey,
        feedback: feedback,
        placeholder: placeholder,
        onStart: start,
        onUpdate: onDragUpdate,
        onEnd: () => onDraggingChanged(null),
        child: card,
      );
    },
  );
}

/// Choose by pointer, not screen width: tablets can have mice and laptops touch.
class _AdaptiveTeamDrag extends StatefulWidget {
  final String teamKey;
  final Widget feedback;
  final Widget placeholder;
  final Widget child;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  const _AdaptiveTeamDrag({
    required this.teamKey,
    required this.feedback,
    required this.placeholder,
    required this.child,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  @override
  State<_AdaptiveTeamDrag> createState() => _AdaptiveTeamDragState();
}

class _AdaptiveTeamDragState extends State<_AdaptiveTeamDrag> {
  bool _mouse = false;
  bool _active = false;

  void _start() {
    _active = true;
    widget.onStart();
  }

  void _end(DraggableDetails details) {
    _finish();
  }

  void _finish() {
    if (!_active) return;
    _active = false;
    widget.onEnd();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.grab,
    onEnter: (_) {
      if (!_active) setState(() => _mouse = true);
    },
    onExit: (_) {
      if (!_active) setState(() => _mouse = false);
    },
    child: _mouse
        ? Draggable<String>(
            data: widget.teamKey,
            maxSimultaneousDrags: 1,
            feedback: widget.feedback,
            onDragStarted: _start,
            onDragUpdate: (details) => widget.onUpdate(details.globalPosition),
            onDragEnd: _end,
            onDragCompleted: _finish,
            onDraggableCanceled: (_, _) => _finish(),
            childWhenDragging: widget.placeholder,
            child: widget.child,
          )
        : LongPressDraggable<String>(
            data: widget.teamKey,
            maxSimultaneousDrags: 1,
            delay: const Duration(milliseconds: 250),
            feedback: widget.feedback,
            onDragStarted: _start,
            onDragUpdate: (details) => widget.onUpdate(details.globalPosition),
            onDragEnd: _end,
            onDragCompleted: _finish,
            onDraggableCanceled: (_, _) => _finish(),
            childWhenDragging: widget.placeholder,
            child: widget.child,
          ),
  );
}

class _PicklistSurface extends ConsumerStatefulWidget {
  final Picklist picklist;
  final bool canEdit;
  final bool isDraggingTeam;
  final ValueNotifier<Offset?> dragPosition;
  final ValueChanged<String?> onDraggingChanged;
  final void Function(String teamKey, int index) onInsertTeam;
  final ValueChanged<String> onRemoveTeam;

  const _PicklistSurface({
    required this.picklist,
    required this.canEdit,
    required this.isDraggingTeam,
    required this.dragPosition,
    required this.onDraggingChanged,
    required this.onInsertTeam,
    required this.onRemoveTeam,
  });

  @override
  ConsumerState<_PicklistSurface> createState() => _PicklistSurfaceState();
}

class _PicklistSurfaceState extends ConsumerState<_PicklistSurface> {
  final _scrollController = ScrollController();
  Timer? _scrollTimer;
  double _scrollStep = 0;
  String? _landingTeam;
  OverlayEntry? _landingOverlay;

  void _finishLanding() {
    _landingOverlay?.remove();
    _landingOverlay?.dispose();
    _landingOverlay = null;
    if (mounted && _landingTeam != null) setState(() => _landingTeam = null);
  }

  void _acceptTeam(String teamKey, int index) {
    final presentation = _DragPresentationScope.of(context);
    final feedback = presentation.feedbackKey.currentContext
        ?.findRenderObject();
    final cardBuilder = presentation.cardBuilder;
    _finishLanding();
    if (!widget.isDraggingTeam ||
        feedback is! RenderBox ||
        cardBuilder == null ||
        MediaQuery.disableAnimationsOf(context)) {
      widget.onInsertTeam(teamKey, index);
      return;
    }
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final begin = MatrixUtils.transformRect(
      feedback.getTransformTo(overlayBox),
      Offset.zero & feedback.size,
    );
    final previous = widget.picklist.teamKeys.indexOf(teamKey);
    final rank = (index - (previous >= 0 && previous < index ? 1 : 0)).clamp(
      0,
      widget.picklist.teamKeys.length - (previous >= 0 ? 1 : 0),
    );
    final sourceCard = cardBuilder(null);
    final destinationCard = cardBuilder(rank + 1);
    setState(() => _landingTeam = teamKey);
    widget.onInsertTeam(teamKey, index);
    _landingOverlay = OverlayEntry(
      builder: (context) => _LandingTeamCard(
        begin: begin,
        destination: () {
          final box = this.context.findRenderObject()! as RenderBox;
          final width = math.min(720.0, box.size.width - 24);
          final scroll = _scrollController.hasClients
              ? _scrollController.offset
              : 0.0;
          final offset = box.localToGlobal(
            Offset((box.size.width - width) / 2, rank * 72.0 + 4 - scroll),
            ancestor: overlayBox,
          );
          return offset & Size(width, 64);
        },
        sourceCard: sourceCard,
        destinationCard: destinationCard,
        onComplete: _finishLanding,
      ),
    );
    overlay.insert(_landingOverlay!);
  }

  @override
  void initState() {
    super.initState();
    widget.dragPosition.addListener(_dragMoved);
  }

  void _dragMoved() {
    final position = widget.dragPosition.value;
    if (position == null) {
      _stopScrolling();
    } else {
      _trackDrag(position);
    }
  }

  @override
  void didUpdateWidget(covariant _PicklistSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isDraggingTeam) _stopScrolling();
  }

  void _stopScrolling() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _scrollStep = 0;
  }

  void _trackDrag(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPosition);
    if (local.dx < 0 ||
        local.dx > box.size.width ||
        local.dy < 0 ||
        local.dy > box.size.height) {
      _stopScrolling();
      return;
    }
    final y = local.dy;
    _scrollStep = y < 90 ? -8 : (y > box.size.height - 72 ? 8 : 0);
    if (_scrollStep == 0) {
      _stopScrolling();
      return;
    }
    _scrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      _scrollController.jumpTo(
        (position.pixels + _scrollStep).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  @override
  void dispose() {
    _landingOverlay?.remove();
    _landingOverlay?.dispose();
    _stopScrolling();
    widget.dragPosition.removeListener(_dragMoved);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teams = widget.picklist.teamKeys;
    final resolvedTeams = {
      for (final raw
          in ref.watch(teamsProvider).value ?? const <Map<String, dynamic>>[])
        Team.fromJson(raw).key: Team.fromJson(raw),
    };
    final mediaRecords =
        ref.watch(eventTeamMediaProvider).value ?? const <TeamMediaRecord>[];
    final avatarByTeam = <String, Uint8List>{};
    for (final record in mediaRecords) {
      if (!record.isAvatar || record.base64Image == null) continue;
      for (final key in record.teamKeys) {
        if (record.preferred || !avatarByTeam.containsKey(key)) {
          avatarByTeam[key] = record.base64Image!;
        }
      }
    }
    if (!widget.canEdit) {
      if (teams.isEmpty) return const SizedBox.expand();
      return _AnimatedRanking(
        teamKeys: teams,
        controller: _scrollController,
        itemBuilder: (context, index) => Center(
          key: ValueKey(teams[index]),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _EditorTeamTile(
                teamKey: teams[index],
                team: resolvedTeams[teams[index]],
                avatarBytes: avatarByTeam[teams[index]],
                rank: index + 1,
                draggable: false,
                onDraggingChanged: widget.onDraggingChanged,
                onDragUpdate: (position) =>
                    widget.dragPosition.value = position,
                action: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
    }
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => false,

      onLeave: (_) => _stopScrolling(),
      builder: (context, candidates, rejected) => teams.isEmpty
          ? _InsertionDropZone(
              active: widget.isDraggingTeam,
              index: 0,
              expandedEmptyState: true,
              onAccept: _acceptTeam,
            )
          : _AnimatedRanking(
              teamKeys: teams,
              landingTeam: _landingTeam,
              controller: _scrollController,
              insertionBuilder: (context, index) => widget.isDraggingTeam
                  ? _InsertionDropZone(
                      active: true,
                      index: index,
                      onAccept: _acceptTeam,
                    )
                  : const SizedBox.shrink(),
              leadingInsertionBuilder: (context, index) => widget.isDraggingTeam
                  ? _InsertionDropZone(
                      active: true,
                      index: index,
                      onAccept: _acceptTeam,
                      alignment: Alignment.topCenter,
                    )
                  : const SizedBox.shrink(),
              trailingInsertionBuilder: (context, index) =>
                  widget.isDraggingTeam
                  ? _InsertionDropZone(
                      active: true,
                      index: index,
                      onAccept: _acceptTeam,
                      fillAvailableSpace: true,
                      alignment: Alignment.topCenter,
                      dividerTop: 36,
                    )
                  : const SizedBox.shrink(),
              itemBuilder: (context, index) => Center(
                key: ValueKey(teams[index]),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: IgnorePointer(
                      ignoring: _landingTeam == teams[index],
                      child: Opacity(
                        opacity: _landingTeam == teams[index] ? 0 : 1,
                        child: _EditorTeamTile(
                          teamKey: teams[index],
                          team: resolvedTeams[teams[index]],
                          avatarBytes: avatarByTeam[teams[index]],
                          rank: index + 1,
                          onDraggingChanged: widget.onDraggingChanged,
                          onDragUpdate: (position) =>
                              widget.dragPosition.value = position,
                          action: PopupMenuButton<String>(
                            icon: const Icon(
                              LucideIcons.gripVertical,
                              size: 20,
                            ),
                            onSelected: (value) {
                              if (value == 'remove') {
                                widget.onRemoveTeam(teams[index]);
                              }
                              if (value == 'up') {
                                widget.onInsertTeam(teams[index], index - 1);
                              }
                              if (value == 'down') {
                                widget.onInsertTeam(teams[index], index + 2);
                              }
                            },
                            itemBuilder: (context) => [
                              if (index > 0)
                                const PopupMenuItem(
                                  value: 'up',
                                  child: ListTile(
                                    leading: Icon(LucideIcons.moveUp),
                                    title: Text('Move up'),
                                  ),
                                ),
                              if (index < teams.length - 1)
                                const PopupMenuItem(
                                  value: 'down',
                                  child: ListTile(
                                    leading: Icon(LucideIcons.moveDown),
                                    title: Text('Move down'),
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'remove',
                                child: ListTile(
                                  leading: Icon(LucideIcons.squareMinus),
                                  title: Text('Remove from list'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Keep cards mounted by team identity so every affected row slides to its rank.
/// Rows have a fixed 64-pixel card and 8 pixels of spacing, including during drag.
class _AnimatedRanking extends StatelessWidget {
  final List<String> teamKeys;
  final String? landingTeam;
  final ScrollController controller;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? insertionBuilder;
  final IndexedWidgetBuilder? leadingInsertionBuilder;
  final IndexedWidgetBuilder? trailingInsertionBuilder;

  const _AnimatedRanking({
    required this.teamKeys,
    required this.controller,
    required this.itemBuilder,
    this.insertionBuilder,
    this.leadingInsertionBuilder,
    this.trailingInsertionBuilder,
    this.landingTeam,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: math.max(constraints.maxHeight, teamKeys.length * 72.0 + 24),
        child: Stack(
          children: [
            for (var index = 0; index < teamKeys.length; index++)
              AnimatedPositioned(
                key: ValueKey(teamKeys[index]),
                duration: teamKeys[index] == landingTeam
                    ? Duration.zero
                    : _motionDuration(context),
                curve: Curves.easeOutCubic,
                top: index * 72.0,
                left: 0,
                right: 0,
                child: itemBuilder(context, index),
              ),
            if (leadingInsertionBuilder != null)
              Positioned(
                key: const ValueKey('picklist-insertion-0'),
                top: 0,
                height: 36,
                left: 0,
                right: 0,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: SizedBox.expand(
                      child: leadingInsertionBuilder!(context, 0),
                    ),
                  ),
                ),
              ),
            if (insertionBuilder != null)
              for (var index = 1; index < teamKeys.length; index++)
                Positioned(
                  key: ValueKey('picklist-insertion-$index'),
                  top: index * 72.0 - 36,
                  height: 72,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: SizedBox.expand(
                        child: insertionBuilder!(context, index),
                      ),
                    ),
                  ),
                ),
            if (trailingInsertionBuilder != null)
              Positioned(
                key: ValueKey('picklist-insertion-${teamKeys.length}'),
                top: (teamKeys.length - 1) * 72.0 + 36,
                bottom: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: SizedBox.expand(
                      child: trailingInsertionBuilder!(
                        context,
                        teamKeys.length,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _InsertionDropZone extends StatelessWidget {
  final bool active;
  final int index;
  final bool expandedEmptyState;
  final bool fillAvailableSpace;
  final Alignment alignment;
  final double? dividerTop;
  final void Function(String teamKey, int index) onAccept;

  const _InsertionDropZone({
    required this.active,
    required this.index,
    required this.onAccept,
    this.expandedEmptyState = false,
    this.fillAvailableSpace = false,
    this.alignment = Alignment.center,
    this.dividerTop,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) {
        HapticFeedback.selectionClick();
        return true;
      },
      onAcceptWithDetails: (details) => onAccept(details.data, index),
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty;
        if (!expandedEmptyState) {
          return SizedBox(
            height: fillAvailableSpace ? null : 8,
            child: dividerTop == null
                ? Align(
                    alignment: alignment,
                    child: _InsertionDivider(hovering: hovering),
                  )
                : Stack(
                    children: [
                      Positioned(
                        top: dividerTop,
                        left: 0,
                        right: 0,
                        child: _InsertionDivider(hovering: hovering),
                      ),
                    ],
                  ),
          );
        }
        return AnimatedContainer(
          duration: _motionDuration(context),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: hovering ? colors.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hovering || active ? colors.primary : Colors.transparent,
            ),
          ),
          alignment: Alignment.center,
          child: SingleChildScrollView(
            child: BeariscopeStatusView(
              icon: LucideIcons.listPlus,
              iconColor: colors.primary,
              title: hovering ? 'Drop to add first' : 'Picklist is empty',
              subtitle: hovering ? null : 'Drag from the library to add',
            ),
          ),
        );
      },
    );
  }
}

class _InsertionDivider extends StatelessWidget {
  final bool hovering;

  const _InsertionDivider({required this.hovering});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: _motionDuration(context),
    height: 3,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: hovering
          ? Theme.of(context).colorScheme.primary
          : Colors.transparent,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

double _totalAverage(TeamScoutingBundle bundle) =>
    bundle.avgMatchField(kSectionAuto, kAutoFuelScored) +
    bundle.avgMatchField(kSectionTele, kTeleFuelScored);

(int, int, int) _safetyStats(TeamScoutingBundle bundle) {
  var defense = 0;
  var noShow = 0;
  var breakdown = 0;
  for (final doc in bundle.matchDocs) {
    final playedDefense =
        _truthy(
          TeamScoutingBundle.getMatchField(
            doc.raw,
            kSectionEndgame,
            kEndPlayedDefenseOffShift,
          ),
        ) ||
        _truthy(
          TeamScoutingBundle.getMatchField(
            doc.raw,
            kSectionEndgame,
            kEndPlayedDefenseOnShift,
          ),
        );
    final absent = _truthy(
      TeamScoutingBundle.getMatchField(doc.raw, kSectionEndgame, kEndNoShow),
    );
    final failed =
        _truthy(
          TeamScoutingBundle.getMatchField(
            doc.raw,
            kSectionTele,
            kTeleStoppedWorking,
          ),
        ) ||
        _truthy(
          TeamScoutingBundle.getMatchField(
            doc.raw,
            kSectionTele,
            kTeleLostComms,
          ),
        );
    if (playedDefense) defense++;
    if (absent) noShow++;
    if (failed) breakdown++;
  }
  return (defense, noShow, breakdown);
}

bool _truthy(Object? value) {
  if (value is bool) return value;
  if (value is num) return value > 0;
  final text = value?.toString().toLowerCase();
  return text == 'true' || text == '1' || text == 'y';
}
