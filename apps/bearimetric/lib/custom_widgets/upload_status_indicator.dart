import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bearimetric/data/upload_queue.dart';

class UploadStatusIndicator extends ConsumerWidget {
  const UploadStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount = ref.watch(
      uploadQueueProvider.select((queue) => queue.length),
    );

    if (pendingCount == 0) {
      return const Tooltip(
        message: 'All uploads synced',
        child: Icon(Icons.cloud_done, color: Colors.green),
      );
    }

    return Tooltip(
      message: '$pendingCount upload${pendingCount == 1 ? '' : 's'} pending',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.cloud_upload),
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
