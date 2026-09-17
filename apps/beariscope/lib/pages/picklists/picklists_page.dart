import 'package:beariscope/pages/picklists/picklist_emoji_colors.dart';
import 'package:beariscope/pages/picklists/picklist_emoji.dart';
import 'package:beariscope/pages/picklists/picklist_options_sheet.dart';
import 'package:beariscope/pages/picklists/picklist_duplicate_dialog.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/picklists/picklist_model.dart';
import 'package:beariscope/pages/picklists/picklist_provider.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/widgets/beariscope_status_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

class PicklistsPage extends ConsumerWidget {
  const PicklistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = MainViewController.of(context);
    final picklists = ref.watch(picklistLibraryProvider);
    final eventKey = ref.watch(currentEventProvider);
    final eventName =
        ref
            .watch(teamEventsProvider)
            .value
            ?.where((event) => event.key == eventKey)
            .firstOrNull
            ?.displayShortName ??
        eventKey;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Picklists'),
        actions: [
          IconButton(
            tooltip: 'Refresh picklists',
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: () =>
                ref.read(picklistLibraryProvider.notifier).refresh(),
          ),
        ],
        leading: controller.isDesktop
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.menu),
                onPressed: controller.openDrawer,
              ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => ref.read(picklistLibraryProvider.notifier).refresh(),
          child: picklists.isEmpty
              ? LayoutBuilder(
                  builder: (context, constraints) => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: constraints.maxHeight,
                        child: _EmptyLibrary(
                          eventName: eventName,
                          onCreate: () => context.push('/picklists/create'),
                        ),
                      ),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    const minCardWidth = 200.0;
                    const spacing = 8.0;
                    final count =
                        ((constraints.maxWidth - 32 + spacing) /
                                (minCardWidth + spacing))
                            .floor()
                            .clamp(1, 6);
                    return CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverGrid.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: count,
                                  mainAxisSpacing: spacing,
                                  crossAxisSpacing: spacing,
                                  childAspectRatio: .82,
                                ),
                            itemCount: picklists.length,
                            itemBuilder: (context, index) =>
                                _PicklistCard(item: picklists[index]),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/picklists/create'),
        icon: const Icon(LucideIcons.plus),
        label: const Text('New Picklist'),
      ),
    );
  }
}

class _PicklistCard extends ConsumerWidget {
  final Picklist item;

  const _PicklistCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final canEdit = ref.read(picklistLibraryProvider.notifier).canEdit(item);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/picklists/${item.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: picklistThumbnailColor(item.emoji, colors),
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(child: PicklistEmoji(item.emoji, size: 64)),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _ModeBadge(mode: item.mode),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surface.withValues(alpha: .8),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${item.teamKeys.length} teams',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Last edited ${_relativeTime(item.updatedAt)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (canEdit)
                    PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'customize') {
                          await showPicklistOptions(context, ref, item);
                          return;
                        }
                        if (value == 'duplicate') {
                          await duplicatePicklist(context, ref, item);
                          return;
                        }
                        if (value == 'delete') {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Delete picklist?'),
                              content: Text(
                                item.mode == PicklistMode.offline
                                    ? '“${item.title}” will be removed from this device.'
                                    : '“${item.title}” will be removed for everyone.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  style: ButtonStyle(
                                    backgroundColor: WidgetStateProperty.all(
                                      colors.error,
                                    ),
                                    foregroundColor: WidgetStateProperty.all(
                                      colors.onError,
                                    ),
                                  ),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            ref
                                .read(picklistLibraryProvider.notifier)
                                .delete(item.id);
                          }
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'customize',
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Customize'),
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'duplicate',
                          child: ListTile(
                            leading: Icon(LucideIcons.copyPlus),
                            title: Text('Duplicate'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(
                              LucideIcons.trash,
                              color: colors.error,
                            ),
                            title: Text(
                              'Delete',
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final String eventName;
  final VoidCallback onCreate;

  const _EmptyLibrary({required this.eventName, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return BeariscopeStatusView(
      icon: LucideIcons.notebookTabs,
      title: 'No picklists yet',
      subtitle: 'Create a picklist for $eventName to get started.',
    );
  }
}

class _ModeBadge extends StatelessWidget {
  final PicklistMode mode;

  const _ModeBadge({required this.mode});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final multiplayer = mode == PicklistMode.multiplayer;
    final foreground = multiplayer
        ? colors.onTertiaryContainer
        : colors.onSurfaceVariant;
    final background = multiplayer
        ? colors.tertiaryContainer
        : colors.surfaceContainerHighest;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              multiplayer ? LucideIcons.users : LucideIcons.hardDrive,
              size: 14,
              color: foreground,
            ),
            const SizedBox(width: 5),
            Text(
              mode.label,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _relativeTime(DateTime time) {
  final elapsed = DateTime.now().difference(time);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  return '${elapsed.inDays}d ago';
}
