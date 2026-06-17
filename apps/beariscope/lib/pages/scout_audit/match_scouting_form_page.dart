import 'dart:convert';

import 'package:beariscope/models/scouting_document.dart';
import 'package:beariscope/providers/scouting_data_provider.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:services/providers/api_provider.dart';
import 'package:services/providers/user_profile_provider.dart';
import 'package:ui/widgets/forms/match_form_renderer.dart';

class MatchScoutingFormPage extends ConsumerStatefulWidget {
  const MatchScoutingFormPage({
    super.key,
    required this.eventKey,
    required this.matchNumber,
    required this.pos,
    required this.teamNumber,
    this.existing,
  });

  final String eventKey;
  final int matchNumber;
  final int pos;
  final int teamNumber;
  final ScoutingDocument? existing;

  @override
  ConsumerState<MatchScoutingFormPage> createState() =>
      _MatchScoutingFormPageState();
}

class _MatchScoutingFormPageState extends ConsumerState<MatchScoutingFormPage> {
  MatchConfig? _config;
  String? _configError;
  MatchFormData? _data;
  int _pageIndex = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString(
        'packages/ui/assets/forms/ui_creator.json',
      );
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final config = MatchConfig.fromJson(json);
      final loaded = _hydrateDefaults(config, _buildInitialData(config));
      if (!mounted) return;
      setState(() {
        _config = config;
        _data = loaded;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _configError = error.toString());
    }
  }

  MatchFormData _buildInitialData(MatchConfig config) {
    final existing = widget.existing;
    if (existing != null) {
      final existingData = MatchFormData.fromJson({
        ...existing.data,
        'id': existing.id,
      });
      return existingData.copyWith(
        eventKey: widget.eventKey,
        matchNumber: widget.matchNumber,
        pos: widget.pos,
        season: config.meta.season,
        configVersion: config.meta.version,
        teamNumber: widget.teamNumber,
      );
    }

    return MatchFormData.blank(
      eventKey: widget.eventKey,
      matchNumber: widget.matchNumber,
      pos: widget.pos,
      season: config.meta.season,
      configVersion: config.meta.version,
      teamNumber: widget.teamNumber,
    );
  }

  Future<void> _save() async {
    final data = _data;
    if (data == null || _saving) return;

    setState(() => _saving = true);

    try {
      final user = await ref.read(userInfoProvider.future);
      final updated = data.copyWith(
        scoutedBy: user?.name?.trim() ?? 'Unknown User',
      );

      await ref
          .read(honeycombClientProvider)
          .post(
            '/scout/ingest',
            data: {
              'entries': [updated.toJson()],
            },
          );

      await ref.read(scoutingDataProvider.notifier).refresh();

      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save scouting data: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final data = _data;

    final title = '${_posLabel(widget.pos)} · Team ${widget.teamNumber}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Symbols.save_rounded),
            tooltip: 'Save',
          ),
        ],
      ),
      body: _configError != null
          ? Center(child: Text('Failed to load match form: $_configError'))
          : (config == null || data == null)
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: MatchFormRenderer(
                key: ValueKey(
                  '${widget.eventKey}:${widget.matchNumber}:${widget.pos}:$_pageIndex',
                ),
                page: config.pages[_pageIndex],
                initialData: data,
                onChanged: (next) => setState(() => _data = next),
                onNextPressed: _pageIndex < config.pages.length - 1
                    ? () => setState(() => _pageIndex++)
                    : null,
              ),
            ),
      bottomNavigationBar: config == null
          ? null
          : NavigationBar(
              selectedIndex: _pageIndex,
              onDestinationSelected: (index) =>
                  setState(() => _pageIndex = index),
              destinations: [
                for (var i = 0; i < config.pages.length; i++)
                  NavigationDestination(
                    icon: Icon(_iconForPageIndex(i, config.pages.length)),
                    label: config.pages[i].title.isNotEmpty
                        ? config.pages[i].title
                        : 'Page ${i + 1}',
                  ),
              ],
            ),
    );
  }

  IconData _iconForPageIndex(int index, int total) {
    if (total <= 1) return Symbols.description_rounded;
    if (index == 0) return Symbols.bolt_rounded;
    if (index == total - 1) return Symbols.sports_score_rounded;
    return Symbols.stacked_bar_chart_rounded;
  }
}

MatchFormData _hydrateDefaults(MatchConfig config, MatchFormData data) {
  final sections = <String, Map<String, dynamic>>{
    for (final entry in data.sections.entries)
      entry.key: Map<String, dynamic>.from(entry.value),
  };

  var changed = false;

  for (final page in config.pages) {
    if (page.sectionId.trim().isEmpty) continue;

    final section = Map<String, dynamic>.from(
      sections[page.sectionId] ?? const <String, dynamic>{},
    );
    var sectionChanged = false;

    for (final component in page.components) {
      final fieldId = component.fieldId.trim();
      if (fieldId.isEmpty || component.type == 'Nxt') continue;
      if (section.containsKey(fieldId)) continue;

      final defaultValue = _defaultFieldValue(component);
      if (defaultValue == null) continue;

      section[fieldId] = defaultValue;
      changed = true;
      sectionChanged = true;
    }

    if (sectionChanged) {
      sections[page.sectionId] = section;
    }
  }

  if (!changed) return data;
  return data.copyWith(sections: sections);
}

dynamic _defaultFieldValue(ComponentConfig component) {
  switch (component.type) {
    case 'volumetric_button':
    case 'int_button':
    case 'int_text_box':
    case 'tristate':
      return 0;
    case 'toggle_switch':
    case 'checkbox':
      return false;
    case 'text_box':
      return '';
    case 'slider':
      return 0.0;
    case 'segmented_button':
      final isMultiSelect = component.parameters['multi_select'] == true;
      return isMultiSelect ? <int>[] : 0;
    case 'dropdown':
      final options = component.parameters['options'];
      if (options is! List || options.isEmpty) return null;
      return options.first.toString();
    default:
      return null;
  }
}

String _posLabel(int pos) {
  final parsed = ScoutPosition.fromPosIndex(pos);
  return parsed?.displayName ?? 'Unknown Position';
}
