import 'package:beariscope/models/match_field_ids.dart';
import 'package:beariscope/models/team_scouting_bundle.dart';
import 'package:beariscope/pages/picklists/picklist_model.dart';
import 'package:beariscope/pages/picklists/picklist_provider.dart';
import 'package:beariscope/widgets/library_identity_fields.dart';
import 'package:beariscope/widgets/beariscope_modal.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/providers/rankings_provider.dart';
import 'package:beariscope/providers/team_scouting_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/permissions_provider.dart';

enum _StartingOrder { blank, totalAverage, eventRank }

extension on _StartingOrder {
  String get label => switch (this) {
    _StartingOrder.blank => 'Blank picklist',
    _StartingOrder.totalAverage => 'Total average',
    _StartingOrder.eventRank => 'Event rank',
  };

  String get description => switch (this) {
    _StartingOrder.blank =>
      'Start with an empty canvas and add every team yourself.',
    _StartingOrder.totalAverage =>
      'Highest combined auto and teleop scoring average first.',
    _StartingOrder.eventRank => 'Current official event rank, best rank first.',
  };

  IconData get icon => switch (this) {
    _StartingOrder.blank => LucideIcons.filePlus,
    _StartingOrder.totalAverage => LucideIcons.chartNoAxesCombined,
    _StartingOrder.eventRank => LucideIcons.trophy,
  };
}

class PicklistsCreatePage extends ConsumerStatefulWidget {
  const PicklistsCreatePage({super.key, this.asSheet = false});

  final bool asSheet;

  @override
  ConsumerState<PicklistsCreatePage> createState() =>
      _PicklistsCreatePageState();
}

class _PicklistsCreatePageState extends ConsumerState<PicklistsCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController(text: 'My Picklist');
  final _teamCountController = TextEditingController(text: '24');
  String _emoji = randomPicklistEmoji();
  _StartingOrder _order = _StartingOrder.blank;
  PicklistMode _mode = PicklistMode.offline;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _teamCountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canCreateMultiplayer =
        ref
            .watch(permissionCheckerProvider)
            ?.hasPermission(PermissionKey.picklistsManage) ??
        false;

    final modal = BeariscopeModal(
      title: 'New picklist',
      actions: const [],
      size: BeariscopeModalSize.tall,
      canDismiss: !_creating,
      primaryAction: BeariscopeModalPrimaryAction(
        label: 'Create picklist',
        icon: LucideIcons.check,
        loading: _creating,
        onPressed: _create,
      ),
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LibraryIdentityFields(
              nameController: _titleController,
              nameLabel: 'Picklist name',
              emoji: _emoji,
              maxLength: 200,
              enabled: !_creating,
              onEmojiChanged: (emoji) => setState(() => _emoji = emoji),
            ),
            const SizedBox(height: 26),
            Text(
              'Picklist type',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            ...PicklistMode.values.map(
              (mode) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ModeCard(
                  mode: mode,
                  selected: mode == _mode,
                  enabled: mode == PicklistMode.offline || canCreateMultiplayer,
                  onTap: () {
                    if (!_creating) setState(() => _mode = mode);
                  },
                ),
              ),
            ),
            if (!canCreateMultiplayer)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Text(
                  'Multiplayer picklists require editing access.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 26),
            Text(
              'Choose a starting point',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            ..._StartingOrder.values.map(
              (order) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OrderCard(
                  order: order,
                  selected: order == _order,
                  onTap: () {
                    if (!_creating) setState(() => _order = order);
                  },
                ),
              ),
            ),
            AnimatedSize(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: _order == _StartingOrder.blank
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextFormField(
                        controller: _teamCountController,
                        enabled: !_creating,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Amount to add',
                          helperText:
                              'You can add, remove, and reorder teams later.',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(LucideIcons.users),
                        ),
                        validator: (value) {
                          if (_order == _StartingOrder.blank) {
                            return null;
                          }
                          final count = int.tryParse(value ?? '');
                          return count == null || count < 1
                              ? 'Enter a number greater than zero'
                              : null;
                        },
                      ),
                    ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
    if (widget.asSheet) return modal;
    return Scaffold(
      body: SafeArea(child: Center(child: modal)),
    );
  }

  Future<void> _create() async {
    if (_creating || !_formKey.currentState!.validate()) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final teams = await _prepopulatedTeams();
      final canCreateMultiplayer =
          ref
              .read(permissionCheckerProvider)
              ?.hasPermission(PermissionKey.picklistsManage) ??
          false;
      final picklist = ref
          .read(picklistLibraryProvider.notifier)
          .create(
            title: _titleController.text,
            emoji: _emoji,
            teamKeys: teams,
            mode: _mode == PicklistMode.multiplayer && canCreateMultiplayer
                ? PicklistMode.multiplayer
                : PicklistMode.offline,
          );
      if (!mounted) return;
      if (widget.asSheet) {
        BeariscopeModal.complete(context, picklist);
      } else {
        context.go('/picklists/${picklist.id}');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = 'Could not create the picklist: $error';
      });
    }
  }

  Future<List<String>> _prepopulatedTeams() async {
    if (_order == _StartingOrder.blank) return [];
    final rawTeams = await ref.read(teamsProvider.future);
    final teams = rawTeams.map(Team.fromJson).toList();
    final limit = int.parse(_teamCountController.text).clamp(1, teams.length);

    switch (_order) {
      case _StartingOrder.blank:
        break;
      case _StartingOrder.eventRank:
        final rankings = await ref.read(eventRankingsProvider.future);
        teams.sort(
          (a, b) => (rankings[a.number]?.rank ?? 999999).compareTo(
            rankings[b.number]?.rank ?? 999999,
          ),
        );
      case _StartingOrder.totalAverage:
        final bundles = await Future.wait(
          teams.map(
            (team) => ref.read(teamScoutingProvider(team.number).future),
          ),
        );
        final scores = <int, double>{
          for (final entry in teams.indexed)
            entry.$2.number: _teamTotalAverage(bundles[entry.$1]),
        };
        teams.sort(
          (a, b) => (scores[b.number] ?? 0).compareTo(scores[a.number] ?? 0),
        );
    }

    return teams.take(limit).map((team) => team.key).toList(growable: false);
  }
}

double _teamTotalAverage(TeamScoutingBundle bundle) =>
    bundle.avgMatchField(kSectionAuto, kAutoFuelScored) +
    bundle.avgMatchField(kSectionTele, kTeleFuelScored);

class _OrderCard extends StatelessWidget {
  final _StartingOrder order;
  final bool selected;
  final VoidCallback onTap;

  const _OrderCard({
    required this.order,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                order.icon,
                color: selected
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      order.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? colors.primary : Colors.transparent,
                  border: Border.all(
                    color: selected ? colors.primary : colors.outline,
                    width: 2,
                  ),
                ),
                child: selected
                    ? Icon(LucideIcons.check, size: 14, color: colors.onPrimary)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final PicklistMode mode;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = enabled
        ? (selected ? colors.onPrimaryContainer : colors.onSurface)
        : colors.onSurface.withValues(alpha: .45);
    return Material(
      color: selected && enabled
          ? colors.primaryContainer
          : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                mode == PicklistMode.multiplayer
                    ? LucideIcons.users
                    : LucideIcons.hardDrive,
                color: foreground,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled
                          ? mode.description
                          : 'Requires multiplayer access.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: foreground),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected && enabled
                      ? colors.primary
                      : Colors.transparent,
                  border: Border.all(
                    color: selected && enabled
                        ? colors.primary
                        : colors.outline,
                    width: 2,
                  ),
                ),
                child: selected && enabled
                    ? Icon(LucideIcons.check, size: 14, color: colors.onPrimary)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
