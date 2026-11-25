import 'package:bearimetric/data/scouting_store.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:grove/grove.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/grove_provider.dart';

final _syncStatusProvider = StreamProvider.autoDispose<GroveSyncStatus>(
  (ref) => ref.watch(bearingsGroveProvider).watchSyncStatus(),
);

int _olderRejections(List<Json> rows, GroveSyncStatus? status) {
  final accountedFor = rows.fold<int>(
    0,
    (count, row) => count + ((row['rejectedIds'] as List?)?.length ?? 0),
  );
  final rejected = (status?.rejected ?? 0) - accountedFor;
  return rejected < 0 ? 0 : rejected;
}

class UploadStatusIndicator extends ConsumerWidget {
  const UploadStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(_syncStatusProvider).value;
    final rows = ref.watch(scoutingRecordsProvider).value ?? [];
    final queued = rows
        .where((row) => scoutingUploadLabel(row) == 'Queued')
        .length;
    final needsAttention =
        rows.any((row) => row['error'] != null) ||
        _olderRejections(rows, status) > 0 ||
        status?.error != null;
    final pending = queued > 0 || (status?.pending ?? 0) > 0;
    final colors = Theme.of(context).colorScheme;

    return IconButton(
      tooltip: 'Scouting uploads',
      icon: Icon(
        needsAttention
            ? LucideIcons.cloudAlert
            : pending
            ? LucideIcons.cloudUpload
            : status == null
            ? LucideIcons.cloud
            : LucideIcons.cloudCheck,
        color: needsAttention
            ? colors.error
            : pending
            ? colors.primary
            : null,
      ),
      onPressed: () async {
        final target = await showDialog<ScoutingUploadTarget>(
          context: context,
          builder: (_) => const _UploadList(),
        );
        if (target != null && context.mounted) {
          context.go('/gamepack-match', extra: target);
        }
      },
    );
  }
}

class _UploadList extends ConsumerWidget {
  const _UploadList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(scoutingRecordsProvider);
    final sync = ref.watch(_syncStatusProvider).value;
    return AlertDialog(
      title: const Text('Scouting uploads'),
      content: SizedBox(
        width: 460,
        child: records.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text('Could not open local scouting records.'),
          data: (rows) {
            final older = _olderRejections(rows, sync);
            if (rows.isEmpty && older == 0 && sync?.error == null) {
              return const Text('No matches saved on this device yet.');
            }
            return ListView(
              shrinkWrap: true,
              children: [
                if (sync?.error case final error?) Text(error),
                if (older > 0)
                  Text(
                    '$older older uploads need attention. Reopen their matches to check for saved answers.',
                  ),
                for (final row in rows.reversed) _UploadRow(row: row),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _UploadRow extends ConsumerWidget {
  const _UploadRow({required this.row});

  final Json row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ScoutingUploadTarget(row);
    final position = ScoutPosition.fromPosIndex(target.station);
    final training = row['training'] == true;
    final match = target.match.split('_').last.toUpperCase();
    final status = scoutingUploadLabel(row);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('$match · ${position?.displayName ?? ''}'),
      subtitle: Text(
        [
          training ? 'Training' : target.event,
          status,
          if (row['error'] case final String error) error,
        ].join(' · '),
      ),
      trailing: row['error'] != null && row['ready'] != null
          ? IconButton(
              tooltip: 'Retry $match upload',
              icon: const Icon(LucideIcons.refreshCw),
              onPressed: () async {
                try {
                  await ref
                      .read(scoutingStoreProvider)
                      .retry(row['key'] as String);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not retry this upload.'),
                      ),
                    );
                  }
                }
              },
            )
          : training || position == null
          ? null
          : const Icon(LucideIcons.chevronRight),
      onTap: training || position == null
          ? null
          : () => Navigator.of(context).pop(target),
    );
  }
}
