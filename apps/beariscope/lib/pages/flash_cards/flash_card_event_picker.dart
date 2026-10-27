import 'package:beariscope/pages/flash_cards/flash_card_deck_model.dart';
import 'package:beariscope/pages/flash_cards/flash_card_deck_provider.dart';
import 'package:beariscope/pages/flash_cards/flash_card_sheet.dart';
import 'package:beariscope/widgets/beariscope_modal.dart';
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
  String? _error;

  @override
  void dispose() {
    _search.dispose();
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
    final headerHeight =
        56.0 + (_error == null ? 0 : 28) + (_selected.isEmpty ? 0 : 56);
    return FlashCardSheet(
      title: 'Events',
      scrollable: false,
      primaryAction: BeariscopeModalPrimaryAction(
        label:
            'Use ${_selected.length} ${_selected.length == 1 ? 'event' : 'events'}',
        icon: LucideIcons.check,
        onPressed: () => Navigator.pop(context, _selected),
      ),
      child: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _EventPickerHeaderDelegate(
              height: headerHeight,
              child: Material(
                color:
                    DialogTheme.of(context).backgroundColor ??
                    Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Find an event',
                              prefixIcon: Icon(LucideIcons.search),
                              border: OutlineInputBorder(),
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
                                constraints: const BoxConstraints(
                                  maxWidth: 180,
                                ),
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
                  ],
                ),
              ),
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
    );
  }
}

class _EventPickerHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _EventPickerHeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;

  @override
  bool shouldRebuild(_EventPickerHeaderDelegate oldDelegate) =>
      height != oldDelegate.height || child != oldDelegate.child;
}
