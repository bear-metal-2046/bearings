import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:core/core.dart' show GamePackRelease;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/gamepack_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:ui/widgets/bearings_spinner.dart';
import 'package:ui/widgets/bearings_status_view.dart';

import 'gamepack_audit_page.dart';

class ScoutAuditPage extends ConsumerWidget {
  const ScoutAuditPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(currentEventProvider);
    final canRead =
        ref.watch(permissionCheckerProvider)?.canReadGamePackAnalysis == true;
    final assignment = canRead
        ? ref.watch(eventGamePackProvider(event))
        : const AsyncData<GamePackRelease?>(null);
    final pack = assignment.value;
    if (pack != null) {
      return GamePackAuditPage(
        key: ValueKey(event),
        event: event,
        release: pack,
      );
    }
    final main = MainViewController.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit'),
        leading: main.isDesktop
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.menu),
                onPressed: main.openDrawer,
              ),
      ),
      body: assignment.isLoading
          ? const Center(child: BearingsSpinner())
          : BearingsStatusView(
              icon: LucideIcons.clipboardList,
              title: canRead ? 'Audit unavailable' : 'Audit access required',
              subtitle:
                  assignment.error?.toString() ??
                  (canRead
                      ? 'Assign a published GamePack to this event.'
                      : 'GamePack observation access is required.'),
            ),
    );
  }
}
