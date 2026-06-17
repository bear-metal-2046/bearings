import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

import 'form_style.dart';

class CustomSegmentedButton extends StatefulWidget {
  const CustomSegmentedButton({
    super.key,
    this.initialValue,
    required this.segments,
    required this.onChanged,
    required this.width,
    required this.height,
    this.multiSelect = false,
    this.selectedColor,
    this.unselectedColor,
  });

  final List<String> segments;
  final ValueChanged<dynamic> onChanged;
  final double width;
  final double height;
  final Color? selectedColor;
  final Color? unselectedColor;
  final dynamic initialValue;
  final bool multiSelect;

  @override
  State<CustomSegmentedButton> createState() => _CustomSegmentedButtonState();
}

class _CustomSegmentedButtonState extends State<CustomSegmentedButton> {
  late List<bool> _isSelected;

  @override
  void initState() {
    super.initState();
    _isSelected = _buildSelection(widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant CustomSegmentedButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue ||
        oldWidget.multiSelect != widget.multiSelect ||
        oldWidget.segments != widget.segments) {
      _isSelected = _buildSelection(widget.initialValue);
    }
  }

  List<bool> _buildSelection(dynamic initialValue) {
    if (widget.segments.isEmpty) return const <bool>[];

    if (widget.multiSelect) {
      if (initialValue is List) {
        final selected = initialValue;
        return List.generate(
          widget.segments.length,
          (index) =>
              selected.contains(index) ||
              selected.contains(widget.segments[index]),
        );
      }
      return List.filled(widget.segments.length, false);
    }

    var selectedIndex = 0;
    if (initialValue is int) {
      selectedIndex = initialValue;
    } else if (initialValue is String) {
      selectedIndex = widget.segments.indexOf(initialValue);
      if (selectedIndex == -1) selectedIndex = 0;
    }
    return List.generate(
      widget.segments.length,
      (index) => index == selectedIndex,
    );
  }

  void _handleTap(int index) {
    setState(() {
      if (widget.multiSelect) {
        _isSelected[index] = !_isSelected[index];
        widget.onChanged([
          for (var i = 0; i < _isSelected.length; i++)
            if (_isSelected[i]) i,
        ]);
      } else {
        for (var i = 0; i < _isSelected.length; i++) {
          _isSelected[i] = i == index;
        }
        widget.onChanged(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segmentCount = widget.segments.length;
    if (segmentCount == 0) {
      return SizedBox(width: widget.width, height: widget.height);
    }

    final selectedColor =
        widget.selectedColor ?? theme.colorScheme.primaryContainer;
    final unselectedColor =
        widget.unselectedColor ?? theme.colorScheme.surfaceContainerLowest;
    final outlineColor = theme.colorScheme.outlineVariant;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FormWidgetStyle.borderRadius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: outlineColor, width: 1.0),
            borderRadius: BorderRadius.circular(FormWidgetStyle.borderRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              for (var i = 0; i < segmentCount; i++)
                Expanded(
                  child: Material(
                    color: _isSelected[i] ? selectedColor : unselectedColor,
                    child: InkWell(
                      onTap: () => _handleTap(i),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: outlineColor, width: 1.0),
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: AutoSizeText(
                              widget.segments[i],
                              maxLines: 2,
                              minFontSize: 9,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: _isSelected[i]
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
