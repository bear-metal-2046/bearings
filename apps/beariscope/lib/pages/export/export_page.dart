import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:ui/widgets/bearings_status_view.dart';

import 'gamepack_export.dart';

class ExportPage extends ConsumerWidget {
  const ExportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(permissionCheckerProvider)?.canReadGamePackAnalysis == true) {
      final event = ref.watch(currentEventProvider);
      return GamePackExportPage(key: ValueKey(event), event: event);
    }
    final main = MainViewController.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export Data'),
        leading: main.isDesktop
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.menu),
                onPressed: main.openDrawer,
              ),
      ),
      body: const BearingsStatusView(
        icon: LucideIcons.sheet,
        title: 'Export access required',
        subtitle: 'GamePack observation access is required.',
      ),
    );
  }
}
