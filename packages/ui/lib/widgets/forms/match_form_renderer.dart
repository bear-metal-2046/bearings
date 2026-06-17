import 'package:auto_size_text/auto_size_text.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'big_number_widget.dart';
import 'bool_button.dart';
import 'custom_segmented_button.dart';
import 'custom_slider.dart';
import 'dropdown.dart';
import 'form_style.dart';
import 'int_textbox.dart';
import 'number_button.dart';
import 'string_textbox.dart';
import 'tristate_button.dart';

class MatchFormRenderer extends StatefulWidget {
  const MatchFormRenderer({
    super.key,
    required this.page,
    required this.initialData,
    required this.onChanged,
    this.onNextPressed,
  });

  final PageConfig page;
  final MatchFormData initialData;
  final ValueChanged<MatchFormData> onChanged;
  final VoidCallback? onNextPressed;

  @override
  State<MatchFormRenderer> createState() => _MatchFormRendererState();
}

class _MatchFormRendererState extends State<MatchFormRenderer> {
  late MatchFormData _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialData;
  }

  @override
  void didUpdateWidget(covariant MatchFormRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_shouldSyncFromParent(oldWidget.initialData, widget.initialData)) {
      _current = widget.initialData;
    }
  }

  bool _shouldSyncFromParent(MatchFormData oldData, MatchFormData newData) {
    if (oldData.id != newData.id) return true;
    if (oldData.eventKey != newData.eventKey) return true;
    if (oldData.matchNumber != newData.matchNumber) return true;
    if (oldData.pos != newData.pos) return true;
    if (oldData.season != newData.season) return true;
    if (oldData.configVersion != newData.configVersion) return true;
    if (oldData.teamNumber != newData.teamNumber) return true;
    if (oldData.scoutedBy != newData.scoutedBy) return true;
    if (oldData.lastModified != newData.lastModified) return true;
    if (!_jsonMapEquals(oldData.sections, newData.sections)) return true;
    return false;
  }

  bool _jsonMapEquals(Map<dynamic, dynamic> a, Map<dynamic, dynamic> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;

    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_jsonValueEquals(a[key], b[key])) return false;
    }

    return true;
  }

  String _normalizedLabel(ComponentConfig component) {
    final raw = component.alias.trim().isNotEmpty
        ? component.alias.trim()
        : component.fieldId.trim();
    final normalized = raw
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return component.fieldId;

    return normalized
        .split(' ')
        .map((word) {
          if (word.length <= 2) return word.toUpperCase();
          return '${word[0].toUpperCase()}${word.substring(1)}';
        })
        .join(' ');
  }

  bool _jsonListEquals(List<dynamic> a, List<dynamic> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;

    for (var i = 0; i < a.length; i++) {
      if (!_jsonValueEquals(a[i], b[i])) return false;
    }

    return true;
  }

  bool _jsonValueEquals(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) return _jsonMapEquals(a, b);
    if (a is List && b is List) return _jsonListEquals(a, b);
    return a == b;
  }

  void _onFieldChanged(String sectionId, String fieldId, dynamic value) {
    final updated = _current.copyWithField(sectionId, fieldId, value);
    setState(() => _current = updated);
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    return LayoutBuilder(
      builder: (context, constraints) {
        final hStep = constraints.maxWidth / page.width;
        final vStep = constraints.maxHeight / page.height;
        final positioned = <Widget>[];

        for (final component in page.components) {
          final storedValue = _current.getField(
            page.sectionId,
            component.fieldId,
          );
          final w = component.layout.w * hStep;
          final h = component.layout.h * vStep;

          final widget = _buildComponentWidget(
            context: context,
            component: component,
            storedValue: storedValue,
            width: w.toDouble(),
            height: h.toDouble(),
          );
          if (widget == null) continue;

          positioned.add(
            Positioned(
              top: (component.layout.y * vStep).toDouble(),
              left: (component.layout.x * hStep).toDouble(),
              child: widget,
            ),
          );
        }
        return Stack(children: positioned);
      },
    );
  }

  Widget? _buildComponentWidget({
    required BuildContext context,
    required ComponentConfig component,
    required dynamic storedValue,
    required double width,
    required double height,
  }) {
    final sectionId = widget.page.sectionId;
    final label = _normalizedLabel(component);

    switch (component.type) {
      case 'volumetric_button':
        return BigNumberWidget(
          buttons: const [1, 5, -1, -5],
          width: width,
          height: height,
          dataName: label,
          initialValue: storedValue is int ? storedValue : null,
          onChanged: (v) => _onFieldChanged(sectionId, component.fieldId, v),
        );
      case 'int_button':
        return NumberButton(
          dataName: label,
          width: width,
          height: height,
          initialValue: storedValue is int ? storedValue : null,
          onChanged: (v) => _onFieldChanged(sectionId, component.fieldId, v),
        );
      case 'int_text_box':
        return IntTextbox(
          onChanged: (v) => _onFieldChanged(sectionId, component.fieldId, v),
          dataName: label,
          width: width,
          height: height,
          initialValue: storedValue is int ? storedValue : null,
        );
      case 'toggle_switch':
      case 'checkbox':
        return BoolButton(
          dataName: label,
          width: width,
          height: height,
          initialValue: storedValue is bool ? storedValue : null,
          onChanged: (v) => _onFieldChanged(sectionId, component.fieldId, v),
        );
      case 'text_box':
        return StringTextbox(
          dataName: label,
          width: width,
          height: height,
          initialString: storedValue is String ? storedValue : null,
          onChanged: (v) => _onFieldChanged(sectionId, component.fieldId, v),
        );
      case 'dropdown':
        final rawOptions = component.parameters['options'];
        final items = rawOptions is List
            ? rawOptions.map((x) => x.toString()).toList(growable: false)
            : const <String>[];

        if (items.isEmpty) return null;

        final selectedIndex = items.indexOf(storedValue?.toString() ?? '');

        return Dropdown(
          title: label,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          items: items,
          onChanged: (v) => _onFieldChanged(sectionId, component.fieldId, v),
          initialIndex: selectedIndex == -1 ? null : selectedIndex,
          width: width,
          height: height,
        );
      case 'tristate':
        return TristateButton(
          dataName: label,
          width: width,
          height: height,
          initialValue: storedValue is int ? storedValue : null,
          onChanged: (v) => _onFieldChanged(sectionId, component.fieldId, v),
        );
      case 'slider':
        return CustomSlider(
          onChanged: (v) => _onFieldChanged(sectionId, component.fieldId, v),
          title: label,
          width: width,
          height: height,
          minValue: 0,
          maxValue: 100,
          initialValue: storedValue is num ? storedValue.toDouble() : null,
        );
      case 'segmented_button':
        final rawOptions = component.parameters['options'];
        if (rawOptions is! List) return null;

        final segments = rawOptions
            .map((x) => x.toString())
            .toList(growable: false);
        final isMultiSelect = component.parameters['multi_select'] == true;

        return CustomSegmentedButton(
          segments: segments,
          multiSelect: isMultiSelect,
          onChanged: (v) => _onFieldChanged(sectionId, component.fieldId, v),
          initialValue: isMultiSelect
              ? (storedValue is List ? storedValue : null)
              : (storedValue is int ? storedValue : null),
          width: width,
          height: height,
        );
      case 'Nxt':
        return _buildNextButton(context, component, width, height);
      default:
        debugPrint('Unsupported component type: ${component.type}');
        return null;
    }
  }

  Widget? _buildNextButton(
    BuildContext context,
    ComponentConfig component,
    double width,
    double height,
  ) {
    final onNextPressed = widget.onNextPressed;
    if (onNextPressed == null) return null;

    final rawLabel = component.parameters['label']?.toString();
    final text = component.alias.trim().isNotEmpty
        ? component.alias
        : ((rawLabel == null || rawLabel.trim().isEmpty)
              ? 'Next Match'
              : rawLabel);

    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: onNextPressed,
        style: FormWidgetStyle.elevatedButtonStyle(
          context,
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        child: AutoSizeText(
          text,
          textAlign: TextAlign.center,
          maxLines: 2,
          minFontSize: 10,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
      ),
    );
  }
}
