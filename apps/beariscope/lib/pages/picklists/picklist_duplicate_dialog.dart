import 'package:beariscope/pages/picklists/picklist_model.dart';
import 'package:beariscope/pages/picklists/picklist_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/permissions_provider.dart';

Future<void> duplicatePicklist(
  BuildContext context,
  WidgetRef ref,
  Picklist source,
) async {
  if (!ref.read(picklistLibraryProvider.notifier).canEdit(source)) return;
  final canShare =
      ref.read(authStatusProvider) == AuthStatus.authenticated &&
      (ref
              .read(permissionCheckerProvider)
              ?.hasPermission(PermissionKey.picklistsManage) ??
          false);
  final mode = await showDialog<PicklistMode>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Duplicate picklist'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text('Create a copy of “${source.title}”.'),
        ),
        for (final mode in PicklistMode.values)
          SimpleDialogOption(
            onPressed: mode == PicklistMode.multiplayer && !canShare
                ? null
                : () => Navigator.pop(context, mode),
            child: ListTile(
              enabled: mode != PicklistMode.multiplayer || canShare,
              leading: Icon(
                mode == PicklistMode.offline
                    ? Icons.devices
                    : Icons.group_outlined,
              ),
              title: Text(mode.label),
              subtitle: Text(
                mode == PicklistMode.multiplayer && !canShare
                    ? 'Requires permission to edit multiplayer picklists.'
                    : mode.description,
              ),
            ),
          ),
      ],
    ),
  );
  if (mode == null || !context.mounted) return;
  final copy = ref
      .read(picklistLibraryProvider.notifier)
      .duplicate(source.id, mode: mode);
  if (copy != null && context.mounted) context.push('/picklists/${copy.id}');
}
