import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/up_next/nexus_up_next_tab.dart';
import 'package:beariscope/pages/up_next/schedule_up_next_tab.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/nexus_event_key_provider.dart';
import 'package:beariscope/providers/tba_preferences_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

enum _EventAction { openTba, openStatbotics, openNexus, openFrcEvents }

class UpNextPage extends ConsumerStatefulWidget {
  const UpNextPage({super.key});

  static final DateFormat timeFormat = DateFormat("EEEE, MMM d 'at' h:mm a");

  @override
  ConsumerState<UpNextPage> createState() => _UpNextPageState();
}

class _UpNextPageState extends ConsumerState<UpNextPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _nexusTabActive = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_handleTabChanged);
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;
    final isNexusTab = _tabController.index == 1;
    if (_nexusTabActive == isNexusTab) return;
    setState(() => _nexusTabActive = isNexusTab);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = MainViewController.of(context);
    final currentEventKey = ref.watch(currentEventProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Up Next'),
        leading: controller.isDesktop
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.menu),
                onPressed: controller.openDrawer,
              ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Schedule'),
            Tab(text: 'Nexus'),
          ],
        ),
        actions: [
          PopupMenuButton<_EventAction>(
            icon: const Icon(LucideIcons.ellipsisVertical),
            tooltip: 'More options',
            onSelected: (action) => _handleAction(action, currentEventKey, ref),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _EventAction.openTba,
                child: ListTile(
                  leading: Icon(LucideIcons.externalLink),
                  title: Text('View Event in TBA'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _EventAction.openStatbotics,
                child: ListTile(
                  leading: Icon(LucideIcons.externalLink),
                  title: Text('View Event in Statbotics'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _EventAction.openFrcEvents,
                child: ListTile(
                  leading: Icon(LucideIcons.externalLink),
                  title: Text('View Event in FIRST Events'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _EventAction.openNexus,
                child: ListTile(
                  leading: Icon(LucideIcons.externalLink),
                  title: Text('Open Schedule in Nexus'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ScheduleUpNextTab(timeFormat: UpNextPage.timeFormat),
          NexusUpNextTab(isActive: _nexusTabActive),
        ],
      ),
    );
  }

  Future<void> _handleAction(
    _EventAction action,
    String eventKey,
    WidgetRef ref,
  ) async {
    switch (action) {
      case _EventAction.openTba:
        launchUrl(
          ref.tbaWebsiteUri('/event/$eventKey'),
          mode: LaunchMode.externalApplication,
        );
      case _EventAction.openStatbotics:
        launchUrl(
          Uri.parse('https://www.statbotics.io/event/$eventKey'),
          mode: LaunchMode.externalApplication,
        );
      case _EventAction.openNexus:
        final nexusEventKey =
            await ref.read(nexusEventKeyProvider.future) ?? eventKey;
        launchUrl(
          Uri.parse(
            'https://frc.nexus/en/event/$nexusEventKey/team/2046/matches',
          ),
          mode: LaunchMode.externalApplication,
        );
      case _EventAction.openFrcEvents:
        launchUrl(
          Uri.parse(
            'https://frc-events.firstinspires.org/${eventKey.substring(0, 4)}/${eventKey.substring(4)}',
          ),
          mode: LaunchMode.externalApplication,
        );
    }
  }
}
