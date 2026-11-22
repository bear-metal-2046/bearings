import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grove/grove.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

final _syncStatusProvider = StreamProvider.autoDispose<GroveSyncStatus>(
  (ref) => ref.watch(bearingsGroveProvider).watchSyncStatus(),
);

class UploadStatusIndicator extends ConsumerWidget {
  const UploadStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(_syncStatusProvider).value;
    if (status == null) {
      return const Tooltip(
        message: 'Checking uploads',
        child: Icon(LucideIcons.cloud),
      );
    }
    final error = status.error;
    if (status.rejected > 0 || error != null) {
      return Tooltip(
        message: error ?? '${status.rejected} uploads rejected by the server',
        child: const Icon(LucideIcons.cloudAlert, color: Colors.red),
      );
    }
    final pendingCount = status.pending;

    if (pendingCount == 0) {
      return const Tooltip(
        message: 'All uploads synced',
        child: Icon(LucideIcons.cloudCheck, color: Colors.green),
      );
    }

    return Tooltip(
      message: '$pendingCount upload${pendingCount == 1 ? '' : 's'} pending',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(LucideIcons.cloudUpload),
          Positioned(
            right: -8,
            top: -8,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                pendingCount > 99 ? '99+' : '$pendingCount',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
