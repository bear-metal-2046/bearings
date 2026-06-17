import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

import 'form_style.dart';

class Dropdown extends StatefulWidget {
  const Dropdown({
    super.key,
    this.initialIndex,
    required this.title,
    required this.backgroundColor,
    required this.items,
    required this.width,
    required this.height,
    this.onChanged,
  });

  final String title;
  final List<String> items;
  final ValueChanged<String?>? onChanged;
  final double width;
  final double height;
  final Color backgroundColor;
  final int? initialIndex;

  @override
  State<Dropdown> createState() => _DropdownState();
}

class _DropdownState extends State<Dropdown> {
  late String _dropdownValue;

  @override
  void initState() {
    super.initState();
    _dropdownValue = _resolveInitialValue();
  }

  @override
  void didUpdateWidget(covariant Dropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items ||
        oldWidget.initialIndex != widget.initialIndex) {
      _dropdownValue = _resolveInitialValue();
    }
  }

  String _resolveInitialValue() {
    if (widget.items.isEmpty) return '';

    if (widget.initialIndex != null &&
        widget.initialIndex! >= 0 &&
        widget.initialIndex! < widget.items.length) {
      return widget.items[widget.initialIndex!];
    }

    return widget.items.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.items.isEmpty) {
      return SizedBox(width: widget.width, height: widget.height);
    }

    final initialValue = widget.items.contains(_dropdownValue)
        ? _dropdownValue
        : widget.items.first;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: DropdownButtonFormField<String>(
        borderRadius: BorderRadius.circular(FormWidgetStyle.borderRadius),
        initialValue: initialValue,
        isExpanded: true,
        dropdownColor: widget.backgroundColor,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        decoration: FormWidgetStyle.textFieldDecoration(
          context: context,
          label: widget.title,
          fillColor: theme.colorScheme.surfaceContainerLow,
        ),
        items: widget.items
            .map(
              (value) => DropdownMenuItem<String>(
                value: value,
                child: AutoSizeText(
                  value,
                  maxLines: 1,
                  minFontSize: 10,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(growable: false),
        selectedItemBuilder: (context) {
          return widget.items
              .map(
                (value) => Align(
                  alignment: Alignment.centerLeft,
                  child: AutoSizeText(
                    value,
                    maxLines: 1,
                    minFontSize: 10,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false);
        },
        onChanged: (value) {
          if (value == null) return;
          setState(() => _dropdownValue = value);
          widget.onChanged?.call(value);
        },
        hint: widget.title.isEmpty
            ? null
            : AutoSizeText(
                widget.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                minFontSize: 10,
                overflow: TextOverflow.ellipsis,
              ),
      ),
    );
  }
}
