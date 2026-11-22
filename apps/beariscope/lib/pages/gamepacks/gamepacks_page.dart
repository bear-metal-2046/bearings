import 'dart:convert';

import 'package:beariscope/providers/current_event_provider.dart';
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

class GamePacksPage extends ConsumerStatefulWidget {
  const GamePacksPage({super.key});

  @override
  ConsumerState<GamePacksPage> createState() => _GamePacksPageState();
}

class _GamePacksPageState extends ConsumerState<GamePacksPage> {
  late String _event = ref.read(currentEventProvider);
  String? _eventName;
  String? _selected;
  bool _assigning = false;

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

  Future<void> _openBuilder({
    GamePackDraft? draft,
    GamePackRelease? original,
    GamePackDesign? imported,
  }) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final release = await Navigator.of(context).push<GamePackRelease>(
      MaterialPageRoute(
        builder: (_) => GamePackWorkspacePage(
          event: _event,
          draft: draft,
          release: original,
          imported: imported,
        ),
      ),
    );
    if (mounted && release != null) {
      setState(() => _selected = release.id);
      _notice('Published ${release.definition.name}');
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

  Future<void> _assign(GamePackRelease release) async {
    final event = _event;
    final accepted = await BearingsModal.show<bool>(
      context,
      builder: (context) => BearingsModal(
        title: 'Pin this release?',
        actions: const [],
        primaryAction: BearingsModalPrimaryAction(
          label: 'Pin release',
          icon: LucideIcons.pin,
          onPressed: () => BearingsModal.complete(context, true),
        ),
        content: Text(
          '${release.definition.name} will be the collection release for $event. '
          'The event will keep this release once it is pinned.',
        ),
      ),
    );
    if (!mounted || accepted != true) return;
    setState(() => _assigning = true);
    try {
      await ref
          .read(bearingsGroveProvider)
          .create(
            EventGamePack(id: event, release: EntityRef(release.id)),
            allowOffline: false,
          );
      if (mounted) _notice('GamePack assigned to $event');
    } catch (error) {
      if (mounted) _notice('Could not assign: $error');
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  Future<void> _selectAnalysis(GamePackRelease release) async {
    final event = _event;
    setState(() => _assigning = true);
    try {
      await ref
          .read(bearingsGroveProvider)
          .update<EventGamePack>(
            event,
            (current) => EventGamePack(
              id: current.id,
              release: current.release,
              analysisRelease: current.release.id == release.id
                  ? null
                  : EntityRef(release.id),
            ),
            allowOffline: false,
          );
      if (mounted) _notice('Analysis uses ${release.definition.name}');
    } catch (error) {
      if (mounted) _notice('Could not select analysis release: $error');
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionCheckerProvider);
    final canRead = permissions?.hasPermission(gamePackReadPermission) ?? false;
    final canPublish =
        permissions?.hasPermission(gamePackPublishPermission) ?? false;
    final canReadResults =
        permissions?.hasPermission(gamePackObservationReadPermission) ?? false;
    if (!canRead) {
      return Scaffold(
        appBar: AppBar(title: const Text('GamePacks')),
        body: const Center(child: Text('GamePack read permission required')),
      );
    }
    final grove = ref.watch(bearingsGroveProvider);
    final library = canPublish
        ? ref.watch(groveQueryProvider(grove.query<GamePackRelease>()))
        : null;
    final drafts = canPublish
        ? ref.watch(groveQueryProvider(grove.query<GamePackDraft>()))
        : null;
    final saved =
        (drafts?.value?.items.toList() ?? const <GamePackDraft>[]).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final release = ref.watch(eventGamePackProvider(_event));
    final analysis = ref.watch(eventAnalysisGamePackProvider(_event));
    final published = library?.value?.items ?? const <GamePackRelease>[];
    final selected = published
        .where((pack) => pack.id == _selected)
        .firstOrNull;
    final assigned = release.value;
    final eventName =
        _eventName ?? ref.watch(competitionEventProvider(_event)).value?.name;
    final canAssign =
        release is AsyncData<GamePackRelease?> && assigned == null;
    return Scaffold(
      appBar: AppBar(title: const Text('GamePacks')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card.outlined(
                child: ListTile(
                  leading: const Icon(LucideIcons.calendarCheck),
                  title: Text(eventName ?? _event),
                  trailing: Tooltip(
                    message:
                        'Choose the event for test data and release assignment',
                    child: OutlinedButton(
                      onPressed: _assigning ? null : _selectEvent,
                      child: const Text('Change event'),
                    ),
                  ),
                  subtitle: Text(
                    release.when(
                      data: (pack) => pack == null
                          ? 'No GamePack assigned'
                          : '${pack.definition.name} · Collection release ${_shortId(pack.id)}'
                                '${analysis.value != null && analysis.value!.id != pack.id ? '\nAnalysis · ${analysis.value!.definition.name}' : ''}',
                      loading: () => 'Checking assignment…',
                      error: (error, _) => 'Assignment unavailable: $error',
                    ),
                  ),
                ),
              ),
              if (canPublish) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _assigning ? null : () => _openBuilder(),
                      icon: const Icon(LucideIcons.blocks),
                      label: const Text('New GamePack'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _assigning ? null : _importPack,
                      icon: const Icon(LucideIcons.fileUp),
                      label: const Text('Import GamePack'),
                    ),
                  ],
                ),
                if (saved.isNotEmpty)
                  ExpansionTile(
                    title: Text('Saved drafts (${saved.length})'),
                    children: [
                      for (final draft in saved)
                        ListTile(
                          title: Text(draft.name),
                          trailing: const Icon(LucideIcons.chevronRight),
                          onTap: () => _openBuilder(draft: draft),
                        ),
                    ],
                  ),
                if (drafts?.error case final error?)
                  Text('Could not load drafts: $error'),
                const SizedBox(height: 20),
                Text(
                  'Published packs',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                if (library?.error case final error?)
                  Text('Could not load packs: $error'),
                if (published.isNotEmpty)
                  BearingsSelect<String>(
                    key: ValueKey(selected?.id),
                    value: selected?.id,
                    decoration: const InputDecoration(
                      labelText: 'Select a release',
                    ),
                    items: [
                      for (final pack in published)
                        BearingsSelectItem(
                          value: pack.id,
                          child: Text(
                            '${pack.definition.name} · ${_shortId(pack.id)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _assigning
                        ? null
                        : (value) => setState(() => _selected = value),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (selected != null)
                      OutlinedButton.icon(
                        onPressed: _assigning
                            ? null
                            : () => _openBuilder(original: selected),
                        icon: const Icon(LucideIcons.copy),
                        label: const Text('Edit as new version'),
                      ),
                    if (selected != null)
                      OutlinedButton.icon(
                        onPressed: _assigning || !canAssign
                            ? null
                            : () => _assign(selected),
                        icon: const Icon(LucideIcons.link),
                        label: Text(
                          _assigning ? 'Assigning…' : 'Pin release to event',
                        ),
                      ),
                    if (selected != null &&
                        assigned != null &&
                        selected.id != analysis.value?.id)
                      OutlinedButton.icon(
                        onPressed: _assigning
                            ? null
                            : () => _selectAnalysis(selected),
                        icon: const Icon(LucideIcons.workflow),
                        label: const Text('Use for analysis'),
                      ),
                  ],
                ),
              ],
              if (assigned != null && canReadResults) ...[
                const SizedBox(height: 24),
                analysis.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text('Analysis unavailable: $error'),
                  data: (pack) => pack == null
                      ? const SizedBox.shrink()
                      : _PackAnalysisPreview(event: _event),
                ),
              ],
            ],
          ),
        ),
      ),
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
