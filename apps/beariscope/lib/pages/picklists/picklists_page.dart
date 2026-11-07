import 'package:beariscope/widgets/library_tile.dart';
import 'package:ui/widgets/bearings_modal.dart';
import 'package:beariscope/pages/picklists/picklists_create_page.dart';
import 'package:beariscope/pages/picklists/picklist_emoji_colors.dart';
import 'package:beariscope/pages/picklists/picklist_emoji.dart';
import 'package:beariscope/pages/picklists/picklist_options_sheet.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/picklists/picklist_model.dart';
import 'package:beariscope/pages/picklists/picklist_provider.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:ui/widgets/bearings_scaffold.dart';
import 'package:ui/widgets/bearings_status_view.dart';
import 'package:beariscope/widgets/screenshot_guard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

class PicklistsPage extends ConsumerStatefulWidget {
  const PicklistsPage({super.key});

  @override
  ConsumerState<PicklistsPage> createState() => _PicklistsPageState();
}

class _PicklistsPageState extends ConsumerState<PicklistsPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _create(BuildContext context) async {
    final picklist = await BearingsModal.show<Picklist>(
      context,
      builder: (_) => const PicklistsCreatePage(asSheet: true),
    );
    if (context.mounted && picklist != null) {
      context.push('/picklists/${picklist.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = MainViewController.of(context);
    final picklists = ref.watch(picklistLibraryProvider);
    final eventKey = ref.watch(currentEventProvider);
    final eventName =
        ref
            .watch(teamEventsProvider)
            .value
            ?.where((event) => event.key == eventKey)
            .firstOrNull
            ?.shortName ??
        eventKey;
    return ScreenshotGuard(
      child: BearingsScaffold(
        title: const Text('Picklists'),
        leading: controller.isDesktop
            ? null
            : IconButton(
                tooltip: 'Open navigation',
                icon: const Icon(LucideIcons.menu),
                onPressed: controller.openDrawer,
              ),
        actions: [
          IconButton(
            tooltip: 'Refresh picklists',
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: () =>
                ref.read(picklistLibraryProvider.notifier).refresh(),
          ),
        ],
        content: BearingsPage(
          search: BearingsSearch(
            controller: _searchController,
            hintText: 'Search picklists',
          ),
          primaryAction: BearingsAction(
            icon: const Icon(LucideIcons.plus),
            label: 'New picklist',
            onPressed: () => _create(context),
          ),
          bodyBuilder: (context, layout) => SafeArea(
            top: false,
            bottom: false,
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(picklistLibraryProvider.notifier).refresh(),
              child: ValueListenableBuilder(
                valueListenable: _searchController,
                builder: (context, value, _) {
                  final query = value.text.trim().toLowerCase();
                  final matches = picklists
                      .where((item) => item.title.toLowerCase().contains(query))
                      .toList();
                  if (matches.isEmpty) {
                    return CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: layout.scrollPadding,
                            child: picklists.isEmpty
                                ? _EmptyLibrary(eventName: eventName)
                                : const BearingsStatusView(
                                    icon: LucideIcons.search,
                                    title: 'No matching picklists',
                                    subtitle: 'Try a different search.',
                                  ),
                          ),
                        ),
                      ],
                    );
                  }
                  return LibraryGrid(
                    padding: layout.scrollPadding,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: matches.length,
                    itemBuilder: (context, index) =>
                        _PicklistCard(item: matches[index]),
                  );
                },
              ),
            ),
          ),
        ),
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
    return LibraryTile(
      key: ValueKey('picklist-${item.id}'),
      title: item.title,
      caption:
          '${item.teamKeys.length} ${item.teamKeys.length == 1 ? 'team' : 'teams'} · ${item.mode.label}',
      color: picklistThumbnailColor(item.emoji, colors),
      thumbnail: PicklistEmoji(item.emoji, size: 56),
      onTap: () => context.push('/picklists/${item.id}'),
      footer: Text(
        'Edited ${_relativeTime(item.updatedAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: colors.onSurfaceVariant),
      ),
      options: canEdit
          ? IconButton(
              tooltip: 'Picklist options for ${item.title}',
              icon: const Icon(LucideIcons.ellipsis, size: 20),
              onPressed: () => showPicklistOptions(context, ref, item),
            )
          : null,
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final String eventName;

  const _EmptyLibrary({required this.eventName});

  @override
  Widget build(BuildContext context) {
    return BearingsStatusView(
      icon: LucideIcons.notebookTabs,
      title: 'No picklists yet',
      subtitle: 'Create a picklist for $eventName to get started.',
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
