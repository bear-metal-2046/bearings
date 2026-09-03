import 'package:beariscope/pages/main_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/providers/permissions_provider.dart';

// Mock data model for the POC stage
class MockPicklist {
  final String title;
  final List<String> activeEditors; // Initials or image URLs
  final Color themeColor;
  MockPicklist({
    required this.title,
    required this.activeEditors,
    required this.themeColor,
  });
}

class PicklistsPage extends ConsumerStatefulWidget {
  const PicklistsPage({super.key});
  @override
  ConsumerState<PicklistsPage> createState() => PicklistsPageState();
}

class PicklistsPageState extends ConsumerState<PicklistsPage> {
  // Mock data representing shared items
  final List<MockPicklist> samplePicklists = [
    MockPicklist(
      title: 'Championship Strategy',
      activeEditors: ['JJ', 'NG', 'JB'],
      themeColor: Colors.blue.shade100,
    ),
    MockPicklist(
      title: 'Quals Defense Focus',
      activeEditors: ['MS'],
      themeColor: Colors.green.shade100,
    ),
    MockPicklist(
      title: 'Playoff Underdogs',
      activeEditors: [],
      themeColor: Colors.purple.shade100,
    ),
    MockPicklist(
      title: 'High Note Scorers',
      activeEditors: ['WP', 'JS'],
      themeColor: Colors.orange.shade100,
    ),
  ];
  @override
  Widget build(BuildContext context) {
    final controller = MainViewController.of(context);
    final permissionChecker = ref.watch(permissionCheckerProvider);
    final canCreatePicklists =
        permissionChecker?.hasPermission(PermissionKey.picklistsManage) ??
        false;
    const minCardWidth = 280.0;
    const cardHeight = 240.0;
    const spacing = 16.0;
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount =
                ((constraints.maxWidth + spacing) / (minCardWidth + spacing))
                    .floor()
                    .clamp(1, 999);
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                mainAxisExtent: cardHeight,
              ),
              itemCount: samplePicklists.length,
              itemBuilder: (context, index) {
                final item = samplePicklists[index];
                return Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  elevation: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Container(
                              color: item.themeColor,
                              child: const Center(
                                child: Icon(
                                  LucideIcons.listOrdered,
                                  size: 40,
                                  color: Colors.black38,
                                ),
                              ),
                            ),
                            if (item.activeEditors.isNotEmpty)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(
                                    item.activeEditors.length,
                                    (index) => Align(
                                      widthFactor: 0.65,
                                      child: CircleAvatar(
                                        radius: 15,
                                        backgroundColor: Theme.of(context)
                                            .cardColor,
                                        child: CircleAvatar(
                                          radius: 13,
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .primaryContainer,
                                          child: Text(
                                            item.activeEditors[index],
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onPrimaryContainer,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                LucideIcons.moreVertical,
                                size: 20,
                              ),
                              onSelected: (value) {
                                if (value == 'delete') {
                                  // POC Action placeholder
                                }
                              },
                              itemBuilder: (BuildContext context) => [
                                const PopupMenuItem(
                                  value: 'open',
                                  child: Text('Open'),
                                ),
                                const PopupMenuItem(
                                  value: 'duplicate',
                                  child: Text('Duplicate'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: canCreatePicklists
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/picklists/create'),
              icon: const Icon(LucideIcons.plus),
              label: const Text('New Picklist'),
            )
          : null,
    );
  }
}
