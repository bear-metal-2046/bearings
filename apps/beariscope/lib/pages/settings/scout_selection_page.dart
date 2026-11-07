import 'package:ui/widgets/bearings_popup_menu.dart';
import 'package:ui/widgets/bearings_alert_dialog.dart';
import 'package:ui/widgets/bearings_modal.dart';

import 'dart:convert';

import 'package:ui/widgets/bearings_card.dart';
import 'package:ui/widgets/bearings_scaffold.dart';
import 'package:ui/widgets/bearings_status_view.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/providers/api_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:ui/widgets/bearings_spinner.dart';

class CurrentScout extends Notifier<String> {
  @override
  String build() => 'None';

  void newScout(String scout) => state = scout;
}

class ScoutSelectionPage extends ConsumerStatefulWidget {
  const ScoutSelectionPage({super.key});

  @override
  ConsumerState<ScoutSelectionPage> createState() => _ScoutSelectionPageState();
}

class _ScoutSelectionPageState extends ConsumerState<ScoutSelectionPage> {
  final FocusNode _pageFocusNode = FocusNode();
  final TextEditingController _searchTEC = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _addScoutTEC = TextEditingController();
  final TextEditingController newNameTEC = TextEditingController();
  List<Map<String, String>>? _optimisticScouts;
  final _scoutsProvider = FutureProvider<List<dynamic>>((ref) {
    return ref
        .watch(honeycombClientProvider)
        .get<List<dynamic>>('/scouts', cachePolicy: CachePolicy.networkFirst);
  });

  List<Map<String, String>> _normalizeScouts(List<dynamic> data) {
    final scouts = data.map((item) {
      return {"name": item["name"] as String, "uuid": item["uuid"] as String};
    }).toList()..sort((a, b) => a["name"]!.compareTo(b["name"]!));
    return scouts;
  }

  Future<void> _refreshScouts() async {
    final client = ref.read(honeycombClientProvider);
    client.invalidateCache('/scouts');
    ref.invalidate(_scoutsProvider);
    try {
      await ref.read(_scoutsProvider.future);
      if (mounted) {
        setState(() => _optimisticScouts = null);
      }
    } catch (_) {
      // Keep existing optimistic/cached state if refresh fails.
    }
  }

  @override
  void initState() {
    super.initState();
    _searchTEC.addListener(_handleSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pageFocusNode.requestFocus();
    });
  }

  void _handleSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchTEC.removeListener(_handleSearchChanged);
    _searchTEC.dispose();
    _searchFocusNode.dispose();
    _pageFocusNode.dispose();
    _addScoutTEC.dispose();
    newNameTEC.dispose();
    super.dispose();
  }

  List<Widget> buildScoutList(List<Map<String, String>> scouts) {
    final permissionChecker = ref.read(permissionCheckerProvider);
    final canManageScouts =
        permissionChecker?.hasPermission(PermissionKey.scoutsManage) ?? false;

    return scouts.map((scout) {
      final name = scout["name"]!;
      final id = scout["uuid"]!;

      return BearingsCard(
        title: name,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canManageScouts)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: IconButton(
                  onPressed: () async {
                    newNameTEC.clear();
                    await BearingsModal.show<void>(
                      context,
                      useRootNavigator: true,
                      builder: (context) => BearingsModal(
                        title: 'Rename Scout',
                        content: TextField(
                          controller: newNameTEC,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'New name',
                          ),
                        ),
                        actions: const [],
                        primaryAction: BearingsModalPrimaryAction(
                          label: 'Rename',
                          icon: LucideIcons.check,
                          onPressed: () async {
                            if (newNameTEC.text.isNotEmpty) {
                              final previous = List<Map<String, String>>.from(
                                _optimisticScouts ??
                                    _normalizeScouts(
                                      ref.read(_scoutsProvider).asData?.value ??
                                          const [],
                                    ),
                              );

                              setState(() {
                                _optimisticScouts =
                                    previous
                                        .map(
                                          (entry) => entry['uuid'] == id
                                              ? {
                                                  'name': newNameTEC.text,
                                                  'uuid': id,
                                                }
                                              : entry,
                                        )
                                        .toList()
                                      ..sort(
                                        (a, b) =>
                                            a['name']!.compareTo(b['name']!),
                                      );
                              });

                              try {
                                await ref
                                    .read(honeycombClientProvider)
                                    .put(
                                      '/scouts/$id',
                                      data: {"name": newNameTEC.text},
                                    );
                                await _refreshScouts();
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              } catch (e) {
                                if (mounted) {
                                  setState(() => _optimisticScouts = previous);
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Failed to rename scout: $e',
                                          ),
                                        ),
                                      );
                                }
                              }
                            }
                          },
                        ),
                      ),
                    );
                  },
                  icon: Icon(LucideIcons.pencil, size: 20),
                ),
              ),
            if (canManageScouts)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: IconButton(
                  onPressed: () async {
                    final confirmed = await BearingsAlertDialog.show<bool>(
                      context: context,
                      title: 'Delete Scout',
                      message: 'Are you sure you want to delete this scout?',
                      actions: const [
                        BearingsAlertAction(label: 'Cancel', result: false),
                        BearingsAlertAction(
                          label: 'Delete',
                          result: true,
                          role: BearingsAlertActionRole.destructive,
                        ),
                      ],
                    );
                    if (confirmed == true) {
                      final previous = List<Map<String, String>>.from(
                        _optimisticScouts ??
                            _normalizeScouts(
                              ref.read(_scoutsProvider).asData?.value ??
                                  const [],
                            ),
                      );
                      setState(() {
                        _optimisticScouts = previous
                            .where((entry) => entry['uuid'] != id)
                            .toList();
                      });

                      try {
                        await ref
                            .read(honeycombClientProvider)
                            .delete('/scouts/$id');
                        await _refreshScouts();
                      } catch (e) {
                        if (mounted) {
                          setState(() => _optimisticScouts = previous);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to delete scout: $e'),
                            ),
                          );
                        }
                      }
                    }
                  },
                  icon: Icon(LucideIcons.trash2, size: 20),
                ),
              ),
          ],
        ),
      );
    }).toList();
  }

  List<String> _parseCsvNames(String input) {
    final normalized = input.replaceAll(RegExp(r',\s+'), ',');
    return normalized
        .split(RegExp(r'[\r\n,]+'))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<void> _importFromCsv() async {
    final result = await BearingsModal.show<_CsvImportResult>(
      context,
      useRootNavigator: true,
      builder: (context) => const _CsvImportDialog(),
    );

    if (!mounted || result == null) return;

    final names = _parseCsvNames(result.csvText);
    if (names.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No names found in CSV.')));
      return;
    }

    for (final name in names) {
      await ref
          .read(honeycombClientProvider)
          .post('/scouts', data: {"name": name});
    }

    await _refreshScouts();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Imported ${names.length} scouts.')));
  }

  KeyEventResult _handleTypeToSearch(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.character == null ||
        _searchFocusNode.hasFocus) {
      return KeyEventResult.ignored;
    }

    final character = event.character!;
    _searchFocusNode.requestFocus();
    Future.microtask(() {
      if (!mounted) return;
      _searchTEC.text += character;
      _searchTEC.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchTEC.text.length),
      );
    });
    return KeyEventResult.handled;
  }

  Future<void> _showAddScoutDialog() async {
    _addScoutTEC.clear();
    await BearingsModal.show<void>(
      context,
      useRootNavigator: true,
      builder: (context) => BearingsModal(
        title: 'Add Scout',
        content: TextField(
          controller: _addScoutTEC,
          decoration: const InputDecoration(labelText: 'Scout name'),
        ),
        actions: const [],
        primaryAction: BearingsModalPrimaryAction(
          label: 'Add',
          icon: LucideIcons.check,
          onPressed: () async {
            if (_addScoutTEC.text.isNotEmpty) {
              final previous = List<Map<String, String>>.from(
                _optimisticScouts ??
                    _normalizeScouts(
                      ref.read(_scoutsProvider).asData?.value ?? const [],
                    ),
              );
              setState(() {
                _optimisticScouts = [
                  ...previous,
                  {
                    'name': _addScoutTEC.text,
                    'uuid': 'temp-${DateTime.now().microsecondsSinceEpoch}',
                  },
                ]..sort((a, b) => a['name']!.compareTo(b['name']!));
              });

              try {
                await ref
                    .read(honeycombClientProvider)
                    .post('/scouts', data: {"name": _addScoutTEC.text});
                await _refreshScouts();
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              } catch (e) {
                if (mounted) {
                  setState(() => _optimisticScouts = previous);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(content: Text('Failed to add scout: $e')),
                  );
                }
              }
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scoutsAsync = ref.watch(_scoutsProvider);
    final permissionChecker = ref.watch(permissionCheckerProvider);
    final canManageScouts =
        permissionChecker?.hasPermission(PermissionKey.scoutsManage) ?? false;
    return Focus(
      focusNode: _pageFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) => _handleTypeToSearch(event),
      child: BearingsScaffold(
        title: const Text('Scouts'),
        titleSpacing: 8,
        actions: [
          if (canManageScouts)
            BearingsPopupMenu.overflow(
              menuChildren: [
                BearingsMenuItem(
                  leadingIcon: const Icon(LucideIcons.import),
                  onPressed: _importFromCsv,
                  child: const Text('Import From CSV'),
                ),
              ],
            )
          else
            const SizedBox(width: 48),
        ],
        content: BearingsPage(
          search: BearingsSearch(
            controller: _searchTEC,
            focusNode: _searchFocusNode,
            hintText: 'Search scouts',
          ),
          primaryAction: canManageScouts
              ? BearingsAction(
                  icon: const Icon(LucideIcons.plus),
                  label: 'Add Scout',
                  onPressed: _showAddScoutDialog,
                )
              : null,
          bodyBuilder: (context, layout) => scoutsAsync.when(
            loading: () => const Center(child: BearingsSpinner()),
            error: (err, stack) => BearingsStatusView(
              icon: LucideIcons.circleAlert,
              iconColor: Theme.of(context).colorScheme.error,
              title: 'Scouts unavailable',
              subtitle: 'Error loading scouts: $err',
              action: FilledButton.icon(
                onPressed: _refreshScouts,
                icon: const Icon(LucideIcons.rotateCw),
                label: const Text('Retry'),
              ),
            ),
            data: (data) {
              final scoutData = _normalizeScouts(data);
              final source = _optimisticScouts ?? scoutData;

              final searchQuery = _searchTEC.text.trim().toLowerCase();
              final filteredScouts = source.where((scout) {
                return scout['name']!.toLowerCase().contains(searchQuery);
              }).toList();

              if (filteredScouts.isEmpty) {
                final hasSearch = searchQuery.isNotEmpty;
                return RefreshIndicator(
                  onRefresh: _refreshScouts,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: layout.scrollPadding,
                    children: [
                      SizedBox(
                        height: 320,
                        child: BearingsStatusView(
                          icon: LucideIcons.users,
                          title: hasSearch
                              ? 'No matching scouts'
                              : 'No scouts found',
                          subtitle: hasSearch
                              ? 'Try adjusting your search.'
                              : 'Add a scout to get started.',
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _refreshScouts,
                child: BearingsCardList(
                  padding: layout.scrollPadding,
                  children: buildScoutList(filteredScouts),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _CsvImportMode { file, paste }

class _CsvImportResult {
  const _CsvImportResult(this.csvText);

  final String csvText;
}

class _CsvImportDialog extends StatefulWidget {
  const _CsvImportDialog();

  @override
  State<_CsvImportDialog> createState() => _CsvImportDialogState();
}

class _CsvImportDialogState extends State<_CsvImportDialog> {
  _CsvImportMode _mode = _CsvImportMode.file;
  PlatformFile? _selectedFile;
  String? _fileContents;
  final TextEditingController _pasteController = TextEditingController();

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Select CSV',
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );

    if (files.isEmpty) return;
    final file = files.single;
    late final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to read file contents.')),
      );
      return;
    }

    setState(() {
      _selectedFile = file;
      _fileContents = utf8.decode(bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final canImport = _mode == _CsvImportMode.file
        ? (_fileContents?.trim().isNotEmpty ?? false)
        : _pasteController.text.trim().isNotEmpty;

    return BearingsModal(
      title: 'Import From CSV',
      actions: const [],
      primaryAction: BearingsModalPrimaryAction(
        label: 'Import',
        icon: LucideIcons.check,
        enabled: canImport,
        onPressed: () {
          final csvText = _mode == _CsvImportMode.file
              ? _fileContents ?? ''
              : _pasteController.text;
          Navigator.of(context).pop(_CsvImportResult(csvText));
        },
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<_CsvImportMode>(
            segments: const [
              ButtonSegment<_CsvImportMode>(
                value: _CsvImportMode.file,
                label: Text('File'),
              ),
              ButtonSegment<_CsvImportMode>(
                value: _CsvImportMode.paste,
                label: Text('Paste'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) {
              setState(() => _mode = selection.first);
            },
          ),
          const SizedBox(height: 16),
          if (_mode == _CsvImportMode.file) ...[
            const Text('Upload a CSV file from your device'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(LucideIcons.file),
              label: const Text('Select file'),
              onPressed: _pickFile,
            ),
            const SizedBox(height: 8),
            if (_selectedFile != null)
              Text(
                _selectedFile!.name,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
          ] else ...[
            const Text('Paste a comma-separated list of scout names'),
            const SizedBox(height: 12),
            TextField(
              controller: _pasteController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'John Scout,Jane Scout',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
    );
  }
}
