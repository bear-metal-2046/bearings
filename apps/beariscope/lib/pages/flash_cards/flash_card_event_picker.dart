import 'package:beariscope/pages/flash_cards/flash_card_deck_model.dart';
import 'package:beariscope/pages/flash_cards/flash_card_deck_provider.dart';
import 'package:beariscope/pages/flash_cards/flash_card_sheet.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/widgets/beariscope_modal.dart';
import 'package:beariscope/widgets/beariscope_search_bar.dart';
import 'package:beariscope/widgets/beariscope_status_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
  final _scroll = ScrollController();
  final _knownEvents = <String, EventOption>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(_searchChanged);
  }

  void _searchChanged() {
    setState(() {});
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toggle(String key) => setState(() {
    if (!_selected.remove(key)) {
      if (_selected.length >= maxFlashCardDeckEvents) {
        _error = 'You can include up to $maxFlashCardDeckEvents events.';
        return;
      }
      _selected.add(key);
    }
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final catalog = ref.watch(flashCardEventCatalogProvider(_year));
    final events = catalog.asData?.value ?? <EventOption>[];
    _knownEvents.addEntries(events.map((event) => MapEntry(event.key, event)));
    final query = _search.text.trim().toLowerCase();
    final filtered = events
        .where(
          (event) => '${event.name} ${event.shortName} ${event.key}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    final Widget? status = catalog.isLoading
        ? const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        : catalog.hasError
        ? BeariscopeStatusView(
            icon: LucideIcons.calendarDays,
            title: 'Events unavailable',
            subtitle: 'Could not load the $_year season.',
            action: TextButton(
              onPressed: () =>
                  ref.invalidate(flashCardEventCatalogProvider(_year)),
              child: const Text('Retry'),
            ),
          )
        : filtered.isEmpty
        ? BeariscopeStatusView(
            icon: LucideIcons.search,
            title: 'No events found.',
            subtitle: query.isEmpty
                ? 'Try a different season.'
                : 'Try another name or event code.',
          )
        : null;

    return FlashCardSheet(
      title: 'Events',
      scrollable: false,
      primaryAction: BeariscopeModalPrimaryAction(
        label:
            'Use ${_selected.length} ${_selected.length == 1 ? 'event' : 'events'}',
        icon: LucideIcons.check,
        onPressed: () => Navigator.pop(context, _selected),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchBarTheme(
              data: theme.searchBarTheme.copyWith(
                backgroundColor: WidgetStatePropertyAll(
                  colors.surfaceContainerHighest,
                ),
              ),
              child: BeariscopeSearchBar(
                controller: _search,
                hintText: 'Find an event',
                elevation: 0,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selected.length} of $maxFlashCardDeckEvents selected',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Semantics(
                      label: 'Season',
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _year,
                          icon: const Icon(LucideIcons.chevronDown, size: 16),
                          borderRadius: BorderRadius.circular(16),
                          onChanged: (year) {
                            if (year == null) return;
                            setState(() => _year = year);
                            if (_scroll.hasClients) _scroll.jumpTo(0);
                          },
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
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_selected.isNotEmpty && constraints.maxHeight >= 320)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final key in _selected)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InputChip(
                            key: ValueKey('selected-event-$key'),
                            deleteIcon: const Icon(LucideIcons.x, size: 16),
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(
                                _knownEvents[key]?.shortName ?? key,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onDeleted: () => _toggle(key),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: colors.error)),
              ),
            Expanded(
              child: Scrollbar(
                controller: _scroll,
                child: ListView.separated(
                  key: const ValueKey('event-picker-list'),
                  controller: _scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: status == null ? filtered.length : 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (status != null) return status;
                    final event = filtered[index];
                    final isSelected = _selected.contains(event.key);
                    final shape = RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isSelected ? colors.primary : Colors.transparent,
                      ),
                    );
                    return Material(
                      color: isSelected
                          ? colors.primaryContainer.withValues(alpha: .45)
                          : colors.surfaceContainerLow,
                      shape: shape,
                      clipBehavior: Clip.antiAlias,
                      child: CheckboxListTile(
                        key: ValueKey('catalog-event-${event.key}'),
                        shape: shape,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        value: isSelected,
                        onChanged: (_) => _toggle(event.key),
                        secondary: Icon(
                          event.leadingIcon,
                          color: colors.primary,
                        ),
                        title: Text(
                          event.shortName,
                          style: theme.textTheme.titleSmall,
                        ),
                        subtitle: Text(
                          event.startDate == null
                              ? event.key
                              : DateFormat.yMMMd().format(event.startDate!),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
