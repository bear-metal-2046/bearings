import 'package:beariscope/pages/picklists/picklist_emoji.dart';
import 'package:beariscope/pages/picklists/picklist_model.dart';
import 'package:beariscope/pages/picklists/picklist_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stupid_simple_sheet/stupid_simple_sheet.dart';

Future<void> showPicklistOptions(
  BuildContext context,
  WidgetRef ref,
  Picklist picklist,
) async {
  final library = ref.read(picklistLibraryProvider.notifier);
  if (!library.canEdit(picklist)) return;
  final changes = await Navigator.of(context)
      .push<({String? title, String? emoji})>(
        StupidSimpleSheetRoute(
          originateAboveBottomViewInset: true,
          child: PicklistOptionsSheet(picklist: picklist),
        ),
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
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
          child: Material(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Picklist options',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close options',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: PicklistEmoji(_emoji, size: 56),
                              ),
                            ),
                            TextFormField(
                              controller: _name,
                              decoration: const InputDecoration(
                                labelText: 'Picklist name',
                                border: OutlineInputBorder(),
                              ),
                              maxLength: 200,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _save(),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Give your picklist a name.'
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Choose an emoji',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => setState(
                                    () => _emoji = randomPicklistEmoji(),
                                  ),
                                  icon: const Icon(Icons.shuffle, size: 18),
                                  label: const Text('Surprise me'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                for (final emoji in picklistEmojis)
                                  Semantics(
                                    selected: _emoji == emoji,
                                    label: 'Use $emoji as thumbnail',
                                    child: SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: Material(
                                        color: _emoji == emoji
                                            ? colors.primaryContainer
                                            : colors.surfaceContainerLow,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          side: BorderSide(
                                            color: _emoji == emoji
                                                ? colors.primary
                                                : Colors.transparent,
                                            width: 2,
                                          ),
                                        ),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          onTap: () =>
                                              setState(() => _emoji = emoji),
                                          child: Center(
                                            child: PicklistEmoji(
                                              emoji,
                                              size: 26,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('Save changes'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
