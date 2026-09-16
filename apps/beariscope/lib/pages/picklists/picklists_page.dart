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
        leading: controller.isDesktop
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.menu),
                onPressed: controller.openDrawer,
              ),
      ),
      body: SafeArea(
        top: false,
        child: picklists.isEmpty
            ? _EmptyLibrary(
                eventName: eventName,
                onCreate: () => context.push('/picklists/create'),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  const minCardWidth = 280.0;
                  const spacing = 16.0;
                  final count =
                      ((constraints.maxWidth + spacing) /
                              (minCardWidth + spacing))
                          .floor()
                          .clamp(1, 4);
                  return CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _OfflineBanner(eventName: eventName),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: count,
                                mainAxisSpacing: spacing,
                                crossAxisSpacing: spacing,
                                mainAxisExtent: 220,
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/picklists/create'),
        icon: const Icon(LucideIcons.plus),
        label: const Text('New Picklist'),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final String eventName;

  const _OfflineBanner({required this.eventName});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.hardDrive, color: colors.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Offline library for $eventName',
              style: TextStyle(color: colors.onSecondaryContainer),
            ),
          ),
        ],
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
                color: colors.primaryContainer,
                padding: const EdgeInsets.all(20),
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(
                        LucideIcons.listOrdered,
                        size: 48,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: .8),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('${item.teamKeys.length} teams'),
                      ),
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
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'duplicate') {
                        final copy = ref
                            .read(picklistLibraryProvider.notifier)
                            .duplicate(item.id);
                        if (copy != null && context.mounted) {
                          context.push('/picklists/${copy.id}');
                        }
                      }
                      if (value == 'delete') {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Delete picklist?'),
                            content: Text(
                              '“${item.title}” will be removed from this device.',
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
                        value: 'duplicate',
                        child: ListTile(
                          leading: Icon(LucideIcons.copyPlus),
                          title: Text('Duplicate'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(LucideIcons.trash, color: colors.error),
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
      subtitle:
          'Create a picklist for $eventName. It will stay local to this device.',
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
