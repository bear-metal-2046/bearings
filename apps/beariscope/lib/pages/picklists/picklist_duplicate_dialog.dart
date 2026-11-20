import 'package:ui/widgets/bearings_modal.dart';
import 'package:beariscope/pages/picklists/picklist_model.dart';
import 'package:beariscope/pages/picklists/picklist_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/permissions_provider.dart';

Future<Picklist?> duplicatePicklist(
  BuildContext context,
  WidgetRef ref,
  Picklist source,
) async {
  if (!ref.read(picklistLibraryProvider.notifier).canEdit(source)) return null;
  final canShare =
      ref.read(authStatusProvider) == AuthStatus.authenticated &&
      (ref.read(permissionCheckerProvider)?.hasAllPermissions([
            PermissionKey.picklistsRead,
            PermissionKey.picklistsManage,
          ]) ??
          false);
  final mode = await BearingsModal.show<PicklistMode>(
    context,
    builder: (context) => BearingsModal(
      title: 'Duplicate picklist',
      actions: const [],
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create a copy of "${source.title}".',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          const _DuplicateModeOption(mode: PicklistMode.offline),
          const Divider(height: 1, indent: 52, endIndent: 12),
          Consumer(
            builder: (context, ref, _) => _DuplicateModeOption(
              mode: PicklistMode.multiplayer,
              disabledReason: !canShare
                  ? 'Requires multiplayer editing permission.'
                  : ref.watch(sharedPicklistsOfflineProvider)
                  ? 'Reconnect to create a multiplayer copy.'
                  : null,
            ),
          ),
        ],
      ),
    ),
  );
  if (mode == null || !context.mounted) return null;
  try {
    return await ref
        .read(picklistLibraryProvider.notifier)
        .duplicate(source.id, mode: mode);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not duplicate the picklist: $error')),
      );
    }
    return null;
  }
}

class _DuplicateModeOption extends StatelessWidget {
  const _DuplicateModeOption({required this.mode, this.disabledReason});

  final PicklistMode mode;
  final String? disabledReason;

  bool get enabled => disabledReason == null;

  @override
  Widget build(BuildContext context) => ListTile(
    enabled: enabled,
    visualDensity: VisualDensity.compact,
    leading: Icon(
      mode == PicklistMode.offline ? LucideIcons.laptop : LucideIcons.users,
    ),
    title: Text(mode.label),
    subtitle: Text(disabledReason ?? mode.description),
    trailing: Icon(
      enabled ? LucideIcons.chevronRight : LucideIcons.lockKeyhole,
      size: 18,
    ),
    onTap: enabled ? () => Navigator.pop(context, mode) : null,
  );
}
