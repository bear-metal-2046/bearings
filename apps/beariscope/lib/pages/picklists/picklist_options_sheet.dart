import 'package:beariscope/widgets/beariscope_modal.dart';
import 'package:beariscope/widgets/library_identity_fields.dart';
import 'package:beariscope/pages/picklists/picklist_model.dart';
import 'package:beariscope/pages/picklists/picklist_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Future<void> showPicklistOptions(
  BuildContext context,
  WidgetRef ref,
  Picklist picklist,
) async {
  final library = ref.read(picklistLibraryProvider.notifier);
  if (!library.canEdit(picklist)) return;
  final changes = await BeariscopeModal.show<({String? title, String? emoji})>(
    context,
    builder: (_) => PicklistOptionsSheet(picklist: picklist),
  );
  if (changes == null || !context.mounted) return;
  ref
      .read(picklistLibraryProvider.notifier)
      .customize(picklist.id, title: changes.title, emoji: changes.emoji);
}

class PicklistOptionsSheet extends StatefulWidget {
  final Picklist picklist;
  const PicklistOptionsSheet({super.key, required this.picklist});

  @override
  State<PicklistOptionsSheet> createState() => _PicklistOptionsSheetState();
}

class _PicklistOptionsSheetState extends State<PicklistOptionsSheet> {
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
    Navigator.pop(context, (
      title: _name.text.trim() == widget.picklist.title
          ? null
          : _name.text.trim(),
      emoji: _emoji == widget.picklist.emoji ? null : _emoji,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return BeariscopeModal(
      title: 'Picklist options',
      actions: const [],
      primaryAction: BeariscopeModalPrimaryAction(
        label: 'Save changes',
        icon: LucideIcons.check,
        onPressed: _save,
      ),
      content: Form(
        key: _form,
        child: LibraryIdentityFields(
          nameController: _name,
          nameLabel: 'Picklist name',
          emoji: _emoji,
          maxLength: 200,
          onSubmitted: _save,
          onEmojiChanged: (emoji) => setState(() => _emoji = emoji),
        ),
      ),
    );
  }
}
