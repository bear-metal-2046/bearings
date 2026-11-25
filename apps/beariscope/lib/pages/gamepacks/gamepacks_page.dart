import 'dart:convert';

import 'package:beariscope/pages/main_view.dart';
import 'package:go_router/go_router.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/widgets/library_tile.dart';
import 'package:core/core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grove/grove.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:services/providers/gamepack_analysis_provider.dart';
import 'package:services/providers/gamepack_provider.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:services/providers/permissions_provider.dart';

import 'builder/workspace_page.dart';
import 'builder/design.dart';
import 'builder/event_picker.dart';
import 'builder/result_picker.dart';
import 'gamepack_displays.dart';

class GamePackWorkspaceRequest {
  const GamePackWorkspaceRequest({
    required this.event,
    required this.gamePack,
    required this.imported,
    required this.formsLocked,
    required this.duplicate,
    required this.onSaved,
  });

  final String event;
  final GamePack? gamePack;
  final GamePackDesign? imported;
  final bool formsLocked;
  final bool duplicate;
  final ValueChanged<GamePack> onSaved;

  GamePackWorkspacePage build() => GamePackWorkspacePage(
    event: event,
    gamePack: gamePack,
    imported: imported,
    formsLocked: formsLocked,
    duplicate: duplicate,
    onSaved: onSaved,
  );
}

class GamePacksPage extends ConsumerStatefulWidget {
  const GamePacksPage({super.key});

  @override
  ConsumerState<GamePacksPage> createState() => _GamePacksPageState();
}

class _GamePacksPageState extends ConsumerState<GamePacksPage> {
  late String _event = ref.read(currentEventProvider);
  final _searchController = TextEditingController();
  String? _eventName;
  bool _busy = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static const _supportedDocumentFields = {
    'formatVersion',
    'name',
    'season',
    'fields',
    'forms',
    'tbaFields',
    'calculations',
    'reportChoices',
    'results',
    'builderFixture',
  };

  Future<void> _selectEvent() async {
    final event = await BearingsModal.show<CompetitionEvent>(
      context,
      builder: (_) => GamePackEventPicker(current: _event),
    );
    if (mounted && event != null) {
      setState(() {
        _event = event.id;
        _eventName = event.name;
      });
    }
  }

  GamePackDesign _design(GamePack gamePack) {
    if (gamePack.document is! Json) {
      throw const FormatException(
        'Stored GamePack document is not a JSON object.',
      );
    }
    final unknown = gamePack.document.keys
        .where((key) => !_supportedDocumentFields.contains(key))
        .toList();
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Unsupported GamePack fields: ${unknown.join(', ')}',
      );
    }
    return GamePackDesign.fromJson(gamePack.document);
  }

  String? _errorFor(GamePack gamePack) {
    try {
      _design(gamePack);
      return null;
    } on Object catch (error) {
      return error is FormatException ? error.message : error.toString();
    }
  }

  bool _readyToAssign(GamePack gamePack) {
    try {
      return _design(gamePack)
          .compile()
          .forms
          .any((form) => form.controls.isNotEmpty);
    } on Object {
      return false;
    }
  }

  Future<void> _openBuilder({
    GamePack? gamePack,
    bool duplicate = false,
    bool formsLocked = false,
    GamePackDesign? imported,
  }) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    GamePack? saved;
    final request = GamePackWorkspaceRequest(
      event: _event,
      gamePack: gamePack,
      imported: imported,
      formsLocked: formsLocked,
      duplicate: duplicate,
      onSaved: (gamePack) => saved = gamePack,
    );
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      await router.push<void>('/gamepacks/editor', extra: request);
    } else {
      await Navigator.of(
        context,
        rootNavigator: true,
      ).push<void>(MaterialPageRoute<void>(builder: (_) => request.build()));
    }
    if (mounted && saved != null) {
      _notice('Saved ${saved!.name} to the GamePacks library');
    }
  }

  Future<void> _importPack() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null || !mounted) return;
      final length = await file.length();
      if (length == null || length > 1024 * 1024) {
        throw const FormatException('Select a GamePack JSON file up to 1 MB.');
      }
      final document = jsonDecode(utf8.decode(await file.readAsBytes()));
      if (document is! Json) {
        throw const FormatException('A GamePack must be a JSON object.');
      }
      if (mounted) {
        await _openBuilder(imported: GamePackDesign.fromJson(document));
      }
    } catch (error) {
      if (mounted) _notice('Could not import GamePack: $error');
    }
  }

  Future<void> _assign(GamePack gamePack, EventGamePack? binding) async {
    final event = _event;
    final accepted = await BearingsModal.show<bool>(
      context,
      builder: (context) => BearingsModal(
        title: 'Assign this GamePack?',
        actions: const [],
        primaryAction: BearingsModalPrimaryAction(
          label: 'Assign GamePack',
          icon: LucideIcons.link,
          onPressed: () => BearingsModal.complete(context, true),
        ),
        content: Text(
          '${gamePack.name} will be assigned to $event. You can change the assignment until the event has saved observations.',
        ),
      ),
    );
    if (!mounted || accepted != true) return;
    setState(() => _busy = true);
    try {
      final grove = ref.read(bearingsGroveProvider);
      if (binding == null) {
        await grove.create(
          EventGamePack(id: event, gamePack: EntityRef(gamePack.id)),
          allowOffline: false,
        );
      } else {
        await grove.update<EventGamePack>(
          event,
          (_) => EventGamePack(id: event, gamePack: EntityRef(gamePack.id)),
          allowOffline: false,
        );
      }
      if (mounted) _notice('GamePack assigned to $event');
    } catch (error) {
      if (mounted) _notice('Could not assign GamePack: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unassign(EventGamePack binding) async {
    final accepted = await BearingsModal.show<bool>(
      context,
      builder: (context) => BearingsModal(
        title: 'Unassign this GamePack?',
        actions: const [],
        primaryAction: BearingsModalPrimaryAction(
          label: 'Unassign',
          icon: LucideIcons.unlink,
          onPressed: () => BearingsModal.complete(context, true),
        ),
        content: const Text(
          'The GamePack will stay in the library. You can assign another GamePack until this event has saved observations.',
        ),
      ),
    );
    if (!mounted || accepted != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(bearingsGroveProvider)
          .update<EventGamePack>(
            binding.id,
            (_) => EventGamePack(id: binding.id, gamePack: null),
            allowOffline: false,
          );
      if (mounted) _notice('GamePack unassigned from ${binding.id}');
    } catch (error) {
      if (mounted) _notice('Could not unassign GamePack: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(GamePack gamePack) async {
    final accepted = await BearingsModal.show<bool>(
      context,
      builder: (context) => BearingsModal(
        title: 'Delete GamePack?',
        actions: const [],
        primaryAction: BearingsModalPrimaryAction(
          label: 'Delete GamePack',
          icon: LucideIcons.trash2,
          onPressed: () => BearingsModal.complete(context, true),
        ),
        content: Text(
          'Delete ${gamePack.name} from the library? Assigned GamePacks and GamePacks referenced by saved data cannot be deleted.',
        ),
      ),
    );
    if (!mounted || accepted != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(bearingsGroveProvider)
          .delete<GamePack>(gamePack.id, allowOffline: false);
      if (mounted) _notice('GamePack deleted');
    } catch (error) {
      if (mounted) _notice('Could not delete GamePack: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final main = MainViewController.maybeOf(context);
    final drawerButton = main != null && !main.isDesktop
        ? IconButton(
            tooltip: 'Open navigation',
            icon: const Icon(LucideIcons.menu),
            onPressed: main.openDrawer,
          )
        : null;
    final permissions = ref.watch(permissionCheckerProvider);
    final canRead = permissions?.hasPermission(gamePackReadPermission) ?? false;
    final canManage =
        permissions?.hasPermission(gamePackManagePermission) ?? false;
    final canReadResults =
        permissions?.hasPermission(gamePackObservationReadPermission) ?? false;
    if (!canRead) {
      return Scaffold(
        appBar: AppBar(title: const Text('GamePacks'), leading: drawerButton),
        body: const Center(child: Text('GamePack read permission required')),
      );
    }
    final grove = ref.watch(bearingsGroveProvider);
    final library = canManage
        ? ref.watch(groveQueryProvider(grove.query<GamePack>()))
        : null;
    final bindings = canManage
        ? ref.watch(groveQueryProvider(grove.query<EventGamePack>()))
        : null;
    final assignedState = ref.watch(eventGamePackProvider(_event));
    final bindingState = ref.watch(eventGamePackBindingProvider(_event));
    final hasDataState = ref.watch(eventGamePackHasDataProvider(_event));
    final gamePacks = [...?library?.value?.items]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final assigned = assignedState.value;
    final binding = bindingState.value;
    final hasData = hasDataState.value ?? true;
    final eventName =
        _eventName ?? ref.watch(competitionEventProvider(_event)).value?.name;
    return BearingsScaffold(
      title: const Text('GamePacks'),
      leading: drawerButton,
      actions: [
        if (canManage)
          IconButton(
            tooltip: 'Import GamePack',
            onPressed: _busy ? null : _importPack,
            icon: const Icon(LucideIcons.fileUp),
          ),
      ],
      content: BearingsPage(
        search: BearingsSearch(
          controller: _searchController,
          hintText: 'Search GamePacks',
        ),
        primaryAction: canManage
            ? BearingsAction(
                icon: const Icon(LucideIcons.plus),
                label: 'New GamePack',
                onPressed: _busy ? null : () => _openBuilder(),
              )
            : null,
        bodyBuilder: (context, layout) => SafeArea(
          top: false,
          bottom: false,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, searchValue, _) {
              final query = searchValue.text.trim().toLowerCase();
              final visibleGamePacks = gamePacks
                  .where(
                    (gamePack) =>
                        query.isEmpty ||
                        gamePack.name.toLowerCase().contains(query) ||
                        gamePack.id.toLowerCase().contains(query),
                  )
                  .toList();
              Widget? libraryErrorState;
              if (canManage) {
                if (library?.error case final error?) {
                  libraryErrorState = BearingsStatusView(
                    icon: LucideIcons.cloudAlert,
                    title: 'GamePack library unavailable',
                    subtitle: error.toString(),
                  );
                }
              }
              Widget? emptyState;
              if (canManage && visibleGamePacks.isEmpty) {
                if (libraryErrorState != null) {
                  emptyState = libraryErrorState;
                } else if (library?.isLoading ?? false) {
                  emptyState = const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  );
                } else if (gamePacks.isEmpty) {
                  emptyState = BearingsStatusView(
                    icon: LucideIcons.blocks,
                    title: 'No GamePacks yet',
                    subtitle:
                        'Create a GamePack for ${eventName ?? _event} to get started.',
                  );
                } else {
                  emptyState = const BearingsStatusView(
                    icon: LucideIcons.search,
                    title: 'No matching GamePacks',
                    subtitle: 'Try a different search.',
                  );
                }
              }

              final footerChildren = <Widget>[
                if (assigned != null && canManage) ...[
                  Text(
                    hasData
                        ? 'This event has saved observations. Its GamePack assignment and forms are locked; other GamePack sections remain editable.'
                        : 'This event has no observations yet. You can change or remove its assignment.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (!hasData)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _busy || binding == null
                            ? null
                            : () => _unassign(binding),
                        icon: const Icon(LucideIcons.unlink),
                        label: const Text('Unassign from event'),
                      ),
                    ),
                ],
                if (assigned != null && canReadResults)
                  _PackAnalysisPreview(event: _event),
              ];

              return LibraryGrid(
                padding: layout.scrollPadding,
                physics: const AlwaysScrollableScrollPhysics(),
                header: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card.outlined(
                      child: ListTile(
                        leading: const Icon(LucideIcons.calendarCheck),
                        title: Text(eventName ?? _event),
                        trailing: Tooltip(
                          message: 'Choose the event to assign a GamePack to',
                          child: OutlinedButton(
                            onPressed: _busy ? null : _selectEvent,
                            child: const Text('Change event'),
                          ),
                        ),
                        subtitle: Text(
                          assignedState.when(
                            data: (pack) => pack == null
                                ? 'No GamePack assigned'
                                : '${pack.name} · GamePack ${_shortId(pack.id)}',
                            loading: () => 'Checking assignment…',
                            error: (error, _) =>
                                'Assignment unavailable: $error',
                          ),
                        ),
                      ),
                    ),
                    if (emptyState != null) ...[
                      const SizedBox(height: 24),
                      emptyState,
                    ] else if (libraryErrorState != null) ...[
                      const SizedBox(height: 16),
                      libraryErrorState,
                    ],
                  ],
                ),
                footer: footerChildren.isEmpty
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 16,
                        children: footerChildren,
                      ),
                itemCount: visibleGamePacks.length,
                itemBuilder: (context, index) {
                  final gamePack = visibleGamePacks[index];
                  return _GamePackLibraryTile(
                    gamePack: gamePack,
                    error: _errorFor(gamePack),
                    assignedEvent: bindings?.value?.items
                        .where(
                          (item) =>
                              item.id != practiceGamePackKey &&
                              item.gamePack?.id == gamePack.id,
                        )
                        .map((item) => item.id)
                        .firstOrNull,
                    assignedHere: assigned?.id == gamePack.id,
                    replacesAssignment:
                        assigned != null && assigned.id != gamePack.id,
                    canAssign: !hasData && bindingState.hasValue,
                    readyToAssign: _readyToAssign(gamePack),
                    formsLocked:
                        ref
                            .watch(gamePackFormsLockedProvider(gamePack.id))
                            .value ??
                        true,
                    busy: _busy,
                    onEdit: (formsLocked) => _openBuilder(
                      gamePack: gamePack,
                      formsLocked: formsLocked,
                    ),
                    onDuplicate: () =>
                        _openBuilder(gamePack: gamePack, duplicate: true),
                    onDelete: () => _delete(gamePack),
                    onAssign: () => _assign(gamePack, binding),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _GamePackLibraryAction { edit, duplicate, delete, assign }

class _GamePackLibraryTile extends StatelessWidget {
  const _GamePackLibraryTile({
    required this.gamePack,
    required this.error,
    required this.assignedEvent,
    required this.assignedHere,
    required this.replacesAssignment,
    required this.canAssign,
    required this.readyToAssign,
    required this.formsLocked,
    required this.busy,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onAssign,
  });

  final GamePack gamePack;
  final String? error;
  final String? assignedEvent;
  final bool assignedHere;
  final bool replacesAssignment;
  final bool canAssign;
  final bool readyToAssign;
  final bool formsLocked;
  final bool busy;
  final ValueChanged<bool> onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onAssign;

  String get _assignmentLabel => assignedHere
      ? 'Assigned here'
      : replacesAssignment
      ? 'Replace assignment'
      : assignedEvent == null
      ? 'Assign to event'
      : 'Also assign here';

  Future<void> _showOptions(BuildContext context) async {
    final action = await BearingsModal.show<_GamePackLibraryAction>(
      context,
      builder: (modalContext) {
        final colors = Theme.of(modalContext).colorScheme;
        void choose(_GamePackLibraryAction action) =>
            BearingsModal.complete(modalContext, action);

        return BearingsModal(
          title: gamePack.name,
          actions: const [],
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error case final error?)
                Text('This GamePack cannot be opened: $error')
              else ...[
                ListTile(
                  leading: const Icon(LucideIcons.pencil),
                  title: Text(formsLocked ? 'Edit other sections' : 'Edit'),
                  subtitle: formsLocked
                      ? const Text('Saved observations lock the forms.')
                      : null,
                  onTap: () => choose(_GamePackLibraryAction.edit),
                ),
                ListTile(
                  leading: const Icon(LucideIcons.copy),
                  title: const Text('Duplicate GamePack'),
                  onTap: () => choose(_GamePackLibraryAction.duplicate),
                ),
                const Divider(),
                ListTile(
                  leading: Icon(
                    assignedHere ? LucideIcons.check : LucideIcons.link,
                  ),
                  title: Text(_assignmentLabel),
                  subtitle: Text(
                    assignedHere
                        ? 'Active for the selected event.'
                        : !readyToAssign
                        ? 'Complete setup before assigning.'
                        : !canAssign
                        ? 'The selected event’s assignment cannot be changed.'
                        : 'Use for scouting at the selected event.',
                  ),
                  onTap: canAssign && readyToAssign && !assignedHere
                      ? () => choose(_GamePackLibraryAction.assign)
                      : null,
                ),
              ],
              const Divider(),
              ListTile(
                leading: Icon(LucideIcons.trash2, color: colors.error),
                title: Text(
                  'Delete GamePack',
                  style: TextStyle(color: colors.error),
                ),
                onTap: () => choose(_GamePackLibraryAction.delete),
              ),
            ],
          ),
        );
      },
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case _GamePackLibraryAction.edit:
        onEdit(formsLocked);
      case _GamePackLibraryAction.duplicate:
        onDuplicate();
      case _GamePackLibraryAction.delete:
        onDelete();
      case _GamePackLibraryAction.assign:
        onAssign();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final malformed = error != null;
    return LibraryTile(
      key: ValueKey('gamepack-${gamePack.id}'),
      title: malformed ? 'Problem GamePack' : gamePack.name,
      caption: malformed
          ? 'ID ${_shortId(gamePack.id)}'
          : [
              if (assignedHere)
                'Assigned to this event'
              else if (assignedEvent != null)
                'Assigned to $assignedEvent'
              else
                'Not assigned to an event',
              if (formsLocked) 'Forms locked',
            ].join(' · '),
      color: malformed ? colors.errorContainer : colors.primaryContainer,
      thumbnail: Icon(
        malformed ? LucideIcons.circleAlert : LucideIcons.blocks,
        size: 56,
        color: malformed ? colors.onErrorContainer : colors.onPrimaryContainer,
      ),
      onTap: () {
        if (busy) return;
        if (malformed) {
          _showOptions(context);
        } else {
          onEdit(formsLocked);
        }
      },
      options: IconButton(
        tooltip: 'GamePack options for ${gamePack.name}',
        icon: const Icon(LucideIcons.ellipsis, size: 20),
        onPressed: busy ? null : () => _showOptions(context),
      ),
      footer: !malformed && !readyToAssign
          ? Text(
              'Complete setup before assigning',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            )
          : null,
    );
  }
}

class _PackAnalysisPreview extends ConsumerStatefulWidget {
  const _PackAnalysisPreview({required this.event});
  final String event;

  @override
  ConsumerState<_PackAnalysisPreview> createState() =>
      _PackAnalysisPreviewState();
}

class _PackAnalysisPreviewState extends ConsumerState<_PackAnalysisPreview> {
  String? _id;
  String? _previewScope;

  @override
  Widget build(BuildContext context) {
    return ref
        .watch(gamePackEventAnalysisProvider(widget.event))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('Could not load analysis inputs: $error'),
          data: (analysis) {
            if (analysis == null) return const SizedBox.shrink();
            final catalog = analysis.analysis.definition.analysis;
            final fields = catalog.catalog.entries.toList();
            final field =
                fields.where((item) => item.key.output == _id).firstOrNull ??
                fields
                    .where(
                      (item) =>
                          item.value.origin != GamePackResultOrigin.schedule,
                    )
                    .firstOrNull;
            if (field == null) return const SizedBox.shrink();
            final session = analysis.session(catalog);
            final grain = field.value.grain;
            final contexts = grain == null || grain == GamePackGrain.event
                ? const <GamePackScope>[]
                : session.contexts(grain);
            String scopeLabel(GamePackScope choice) => [
              choice.match,
              choice.alliance,
              choice.team,
            ].nonNulls.join(' · ');
            final scope =
                contexts
                    .where((choice) => scopeLabel(choice) == _previewScope)
                    .firstOrNull ??
                contexts.firstOrNull;
            GameGraphEvaluation? evaluated;
            String? failure;
            try {
              evaluated = session.evaluate(field.key, scope: scope);
            } catch (error) {
              failure = error.toString();
            }
            final result = evaluated?.result;
            final evidence =
                result?.allEvidence.toSet() ?? const <GamePackEvidenceRef>{};
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Analysis preview',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (analysis.offline) const Text('Showing cached event inputs'),
                OutlinedButton.icon(
                  icon: const Icon(LucideIcons.listFilter),
                  label: const Text('Choose field or calculation'),
                  onPressed: () async {
                    final choice = await pickGamePackResult(
                      context,
                      title: 'Preview a field',
                      options: catalog.catalog,
                    );
                    if (!mounted || choice == null) return;
                    setState(() {
                      _id = choice.output;
                      _previewScope = null;
                    });
                  },
                ),
                if (scope != null)
                  BearingsSelect<String>(
                    key: ValueKey((field.key.output, scopeLabel(scope))),
                    value: scopeLabel(scope),
                    decoration: InputDecoration(
                      labelText: grain?.label ?? 'Preview context',
                    ),
                    items: [
                      for (final choice in contexts)
                        BearingsSelectItem(
                          value: scopeLabel(choice),
                          child: Text(scopeLabel(choice)),
                        ),
                    ],
                    onChanged: (value) => setState(() => _previewScope = value),
                  ),
                if (failure != null) Text(failure),
                if (result != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(field.value.label),
                    subtitle: Text(switch (result.data) {
                      final List<GamePackValue> rows => '${rows.length} rows',
                      _ => result.toString(),
                    }),
                  ),
                if (evidence.isNotEmpty)
                  ExpansionTile(
                    title: Text('Contributing records (${evidence.length})'),
                    children: [
                      for (final source in evidence)
                        ListTile(
                          dense: true,
                          title: Text(source.id),
                          subtitle: Text(source.type),
                          onTap: () =>
                              showGamePackEvidence(context, analysis, source),
                        ),
                    ],
                  ),
              ],
            );
          },
        );
  }
}

String _shortId(String id) => id.split('-').first;
