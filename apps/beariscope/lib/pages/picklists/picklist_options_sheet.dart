import 'package:ui/widgets/bearings_modal.dart';
import 'package:ui/widgets/bearings_alert_dialog.dart';
import 'package:beariscope/widgets/library_identity_fields.dart';
import 'package:beariscope/pages/picklists/picklist_duplicate_dialog.dart';
import 'package:beariscope/pages/picklists/picklist_model.dart';
import 'package:beariscope/pages/picklists/picklist_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Future<void> showPicklistOptions(
  BuildContext context,
  WidgetRef ref,
  Picklist picklist,
) async {
  final library = ref.read(picklistLibraryProvider.notifier);
  if (!library.canEdit(picklist)) return;
  final copy = await BearingsModal.show<Picklist>(
    context,
    builder: (_) => PicklistOptionsSheet(picklist: picklist),
  );
  if (copy != null && context.mounted) context.push('/picklists/${copy.id}');
}

class PicklistOptionsSheet extends ConsumerStatefulWidget {
  final Picklist picklist;
  const PicklistOptionsSheet({super.key, required this.picklist});

  @override
  ConsumerState<PicklistOptionsSheet> createState() =>
      _PicklistOptionsSheetState();
}

class _PicklistOptionsSheetState extends ConsumerState<PicklistOptionsSheet> {
  late final _name = TextEditingController(text: widget.picklist.title);
  late String _emoji = widget.picklist.emoji;
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    // Leave untouched fields alone if a teammate changed them while this was open.
    ref
        .read(picklistLibraryProvider.notifier)
        .customize(
          widget.picklist.id,
          title: _name.text.trim() == widget.picklist.title
              ? null
              : _name.text.trim(),
          emoji: _emoji == widget.picklist.emoji ? null : _emoji,
        );
    BearingsModal.complete(context);
  }

  Future<void> _duplicate() async {
    FocusScope.of(context).unfocus();
    final copy = await duplicatePicklist(context, ref, widget.picklist);
    if (copy != null && mounted) BearingsModal.complete(context, copy);
  }

  Future<void> _delete() async {
    final picklist = widget.picklist;
    final confirmed = await BearingsAlertDialog.show<bool>(
      context: context,
      title: 'Delete picklist?',
      message: picklist.mode == PicklistMode.offline
          ? '“${picklist.title}” will be removed from this device.'
          : '“${picklist.title}” will be removed for everyone.',
      actions: const [
        BearingsAlertAction(label: 'Cancel', result: false),
        BearingsAlertAction(
          label: 'Delete',
          result: true,
          role: BearingsAlertActionRole.destructive,
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    ref.read(picklistLibraryProvider.notifier).delete(picklist.id);
    BearingsModal.complete(context);
  }

  @override
  Widget build(BuildContext context) {
    final picklist = ref
        .watch(picklistLibraryProvider)
        .where((item) => item.id == widget.picklist.id)
        .firstOrNull;
    final canEdit =
        picklist != null &&
        ref.read(picklistLibraryProvider.notifier).canEdit(picklist);
    return BearingsModal(
      title: 'Picklist options',
      actions: [
        BearingsModalAction(
          label: 'Duplicate picklist',
          icon: LucideIcons.copyPlus,
          enabled: canEdit,
          onPressed: _duplicate,
        ),
        BearingsModalAction(
          label: 'Delete picklist',
          icon: LucideIcons.trash2,
          enabled: canEdit,
          onPressed: _delete,
        ),
      ],
      primaryAction: BearingsModalPrimaryAction(
        label: 'Save changes',
        icon: LucideIcons.check,
        onPressed: _save,
        enabled: canEdit,
      ),
      content: Form(
        key: _form,
        child: LibraryIdentityFields(
          nameController: _name,
          nameLabel: 'Picklist name',
          emoji: _emoji,
          maxLength: 200,
          enabled: canEdit,
          onSubmitted: _save,
          onEmojiChanged: (emoji) => setState(() => _emoji = emoji),
        ),
      ),
    );
  }
}
