import 'package:beariscope/pages/gamepacks/builder/event_picker.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grove/grove.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:services/providers/gamepack_provider.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:ui/ui.dart';

class PracticeSettingsPage extends ConsumerStatefulWidget {
  const PracticeSettingsPage({super.key});

  @override
  ConsumerState<PracticeSettingsPage> createState() =>
      _PracticeSettingsPageState();
}

class _PracticeSettingsPageState extends ConsumerState<PracticeSettingsPage> {
  CompetitionEvent? _event;
  String? _packId;
  bool _saving = false;
  String? _error;

  Future<void> _chooseEvent(String current) async {
    final event = await BearingsModal.show<CompetitionEvent>(
      context,
      builder: (_) => GamePackEventPicker(current: current),
    );
    if (mounted && event != null) setState(() => _event = event);
  }

  Future<void> _save(String event, String pack, EventGamePack? previous) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final assignment = EventGamePack(
      id: practiceGamePackKey,
      gamePack: EntityRef(pack),
      practiceEvent: EntityRef(event),
    );
    try {
      final grove = ref.read(bearingsGroveProvider);
      if (previous == null) {
        await grove.create(assignment, allowOffline: false);
      } else {
        await grove.update<EventGamePack>(
          assignment.id,
          (_) => assignment,
          allowOffline: false,
        );
      }
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Practice settings saved')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save practice settings: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const title = 'Bearimetric Practice';
    final permissions = ref.watch(permissionCheckerProvider);
    if (permissions?.hasPermission(gamePackReadPermission) != true ||
        permissions?.hasPermission(gamePackManagePermission) != true) {
      return Scaffold(
        appBar: AppBar(title: const Text(title)),
        body: const Center(child: Text('GamePack management access required')),
      );
    }

    final binding = ref.watch(
      eventGamePackBindingProvider(practiceGamePackKey),
    );
    final assignment = binding.value;
    final event = _event?.id ?? assignment?.practiceEvent?.id;
    final eventName =
        _event?.name ??
        (event == null
            ? null
            : ref.watch(competitionEventProvider(event)).value?.name);
    final pack = _packId ?? assignment?.gamePack?.id;
    final grove = ref.watch(bearingsGroveProvider);
    final library = ref.watch(groveQueryProvider(grove.query<GamePack>()));
    final packs = [...?library.value?.items.where(_isAssignable)]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final packAvailable = packs.any((candidate) => candidate.id == pack);

    final canSave =
        !_saving &&
        binding.hasValue &&
        event != null &&
        packAvailable &&
        (event != assignment?.practiceEvent?.id ||
            pack != assignment?.gamePack?.id);

    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          BearingsSettingGroup(
            title: 'Practice setup',
            children: [
              ListTile(
                leading: const Icon(LucideIcons.calendar),
                title: const Text('Practice event'),
                subtitle: Text(eventName ?? event ?? 'Choose an event'),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: _saving
                    ? null
                    : () =>
                          _chooseEvent(event ?? ref.read(currentEventProvider)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: library.isLoading && packs.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : library.hasError
                    ? const Text('The GamePack library is unavailable.')
                    : packs.isEmpty
                    ? const Text(
                        'Create a GamePack with scouting questions to use it for practice.',
                      )
                    : BearingsSelect<String>(
                        value: packAvailable ? pack : null,
                        decoration: const InputDecoration(
                          labelText: 'Practice GamePack',
                        ),
                        items: [
                          for (final candidate in packs)
                            BearingsSelectItem(
                              value: candidate.id,
                              child: Text(
                                candidate.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _packId = value),
                      ),
              ),
              if (binding.hasError)
                const ListTile(
                  title: Text(
                    'The current practice assignment is unavailable.',
                  ),
                ),
              if (_error case final error?)
                ListTile(
                  title: Text(error),
                  textColor: Theme.of(context).colorScheme.error,
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.icon(
                    onPressed: canSave
                        ? () => _save(event, pack!, assignment)
                        : null,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.check),
                    label: const Text('Save practice settings'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isAssignable(GamePack gamePack) {
    try {
      return gamePack.definition.forms.any((form) => form.controls.isNotEmpty);
    } on FormatException {
      return false;
    }
  }
}
