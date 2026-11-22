import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:ui/ui.dart';

class GamePackEventPicker extends ConsumerStatefulWidget {
  const GamePackEventPicker({super.key, required this.current, this.season});
  final String current;
  final int? season;

  @override
  ConsumerState<GamePackEventPicker> createState() =>
      GamePackEventPickerState();
}

class GamePackEventPickerState extends ConsumerState<GamePackEventPicker> {
  late int _year =
      widget.season ??
      int.tryParse(widget.current.characters.take(4).toString()) ??
      DateTime.now().year;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final selection = (year: _year, team: null as String?);
    final catalog = ref.watch(competitionEventsProvider(selection));
    final last = DateTime.now().year + 1;
    final years = {
      _year,
      for (var year = last; year >= firstMirroredTbaSeason; year--) year,
    }.toList()..sort((a, b) => b.compareTo(a));
    return BearingsModal(
      title: 'Choose an event',
      actions: const [],
      scrolling: BearingsModalScrolling.content,
      size: BearingsModalSize.tall,
      content: SizedBox(
        width: 490,
        height: 370,
        child: Column(
          children: [
            if (widget.season == null)
              BearingsSelect<int>(
                value: _year,
                decoration: const InputDecoration(labelText: 'Season'),
                items: [
                  for (final year in years)
                    BearingsSelectItem(value: year, child: Text('$year')),
                ],
                onChanged: (year) {
                  if (year != null) setState(() => _year = year);
                },
              ),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Find an event',
                prefixIcon: Icon(LucideIcons.search),
              ),
              onChanged: (query) =>
                  setState(() => _query = query.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: catalog.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: TextButton(
                    onPressed: () => retryCompetitionEvents(
                      ProviderScope.containerOf(context, listen: false),
                      selection,
                    ),
                    child: const Text('Retry loading events'),
                  ),
                ),
                data: (events) {
                  final matches =
                      events
                          .where(
                            (event) => '${event.name} ${event.id}'
                                .toLowerCase()
                                .contains(_query),
                          )
                          .toList()
                        ..sort((a, b) => a.name.compareTo(b.name));
                  if (matches.isEmpty) {
                    return const Center(child: Text('No events found'));
                  }
                  return ListView.builder(
                    itemCount: matches.length,
                    itemBuilder: (context, i) {
                      final event = matches[i];
                      return ListTile(
                        title: Text(event.name),
                        subtitle: Text(event.id),
                        selected: event.id == widget.current,
                        onTap: () => BearingsModal.complete(context, event),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
