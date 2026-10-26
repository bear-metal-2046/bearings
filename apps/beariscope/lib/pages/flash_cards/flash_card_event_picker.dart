import 'package:beariscope/pages/flash_cards/flash_card_deck_model.dart';
import 'package:beariscope/pages/flash_cards/flash_card_deck_provider.dart';
import 'package:beariscope/pages/flash_cards/flash_card_sheet.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

class FlashCardEventPicker extends ConsumerStatefulWidget {
  const FlashCardEventPicker({super.key, required this.selected});
  final Set<String> selected;
  @override
  ConsumerState<FlashCardEventPicker> createState() =>
      _FlashCardEventPickerState();
}

class _FlashCardEventPickerState extends ConsumerState<FlashCardEventPicker> {
  late final Set<String> _selected = {...widget.selected};
  late int _year = _selected.isEmpty
      ? DateTime.now().year
      : int.parse(_selected.last.substring(0, 4));
  final _search = TextEditingController();
  final _keys = TextEditingController();
  bool _manual = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _keys.dispose();
    super.dispose();
  }

  void _toggle(String key) => setState(() {
    if (!_selected.remove(key)) {
      if (_selected.length >= maxFlashCardDeckEvents) {
        _error = 'You can include up to 32 events.';
        return;
      }
      _selected.add(key);
    }
    _error = null;
  });

  void _addKeys() {
    try {
      final keys = _keys.text
          .split(RegExp(r'[\s,;]+'))
          .where((key) => key.isNotEmpty)
          .map(normalizeFlashCardEventKey)
          .toSet();
      if (keys.isEmpty) {
        throw const FormatException('Enter at least one event key.');
      }
      if ({..._selected, ...keys}.length > maxFlashCardDeckEvents) {
        throw const FormatException('You can include up to 32 events.');
      }
      setState(() {
        _selected.addAll(keys);
        _keys.clear();
        _error = null;
        _manual = false;
      });
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(flashCardEventCatalogProvider(_year));
    final events = catalog.asData?.value ?? <EventOption>[];
    final query = _search.text.trim().toLowerCase();
    final filtered = events
        .where(
          (event) => '${event.name} ${event.key}'.toLowerCase().contains(query),
        )
        .toList();
    final names = {for (final event in events) event.key: event.shortName};
    return FlashCardSheet(
      title: 'Events',
      scrollable: false,
      footer: FilledButton(
        onPressed: () => Navigator.pop(context, _selected),
        child: Text(
          'Use ${_selected.length} ${_selected.length == 1 ? 'event' : 'events'}',
        ),
      ),
      child: SizedBox(
        height: 480,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Find an event',
                            prefixIcon: const Icon(LucideIcons.search),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: 'Add event keys',
                              onPressed: () =>
                                  setState(() => _manual = !_manual),
                              icon: Icon(
                                _manual ? LucideIcons.x : LucideIcons.keyRound,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 104,
                        child: DropdownButtonFormField<int>(
                          initialValue: _year,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Year',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            if (_year > DateTime.now().year + 1)
                              DropdownMenuItem(
                                value: _year,
                                child: Text('$_year'),
                              ),
                            for (
                              var year = DateTime.now().year + 1;
                              year >= 1992;
                              year--
                            )
                              DropdownMenuItem(
                                value: year,
                                child: Text('$year'),
                              ),
                          ],
                          onChanged: (year) {
                            if (year != null) setState(() => _year = year);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_manual) ...[
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('deck-event-keys'),
                      controller: _keys,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'Event keys',
                        hintText: '2026wabon, 2026pncmp',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: 'Add events',
                          onPressed: _addKeys,
                          icon: const Icon(LucideIcons.plus),
                        ),
                      ),
                      onSubmitted: (_) => _addKeys(),
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_selected.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 48,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _selected.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (context, index) {
                          final key = _selected.elementAt(index);
                          return InputChip(
                            key: ValueKey('selected-event-$key'),
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(
                                names[key] ?? key,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onDeleted: () => _toggle(key),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
            if (catalog.isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (catalog.hasError)
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const Text('Events unavailable'),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(flashCardEventCatalogProvider(_year)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else if (filtered.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No events found.')),
                ),
              )
            else
              SliverList.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final event = filtered[index];
                  return CheckboxListTile(
                    key: ValueKey('catalog-event-${event.key}'),
                    contentPadding: EdgeInsets.zero,
                    value: _selected.contains(event.key),
                    onChanged: (_) => _toggle(event.key),
                    title: Text(event.shortName),
                    subtitle: Text(event.key),
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
