import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

import 'form_style.dart';

class BigNumberWidget extends StatefulWidget {
  const BigNumberWidget({
    super.key,
    this.backgroundColor,
    required this.buttons,
    required this.width,
    required this.height,
    required this.dataName,
    this.initialValue,
    required this.onChanged,
  });

  final double width;
  final double height;
  final List<int> buttons;
  final Color? backgroundColor;
  final String dataName;
  final int? initialValue;
  final ValueChanged<int>? onChanged;

  @override
  State<BigNumberWidget> createState() => _BigNumberWidgetState();
}

class _BigNumberWidgetState extends State<BigNumberWidget> {
  late int _currentValue = widget.initialValue ?? 0;

  @override
  void didUpdateWidget(covariant BigNumberWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _currentValue = widget.initialValue ?? 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final panelColor =
        widget.backgroundColor ?? theme.colorScheme.surfaceContainerLow;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: DecoratedBox(
        decoration: FormWidgetStyle.panelDecoration(
          context,
          fillColor: panelColor,
        ),
        child: Padding(
          padding: FormWidgetStyle.cardPadding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              final headerHeight = (height * 0.32).clamp(24.0, 78.0).toDouble();
              final gridHeight = (height - headerHeight)
                  .clamp(0.0, height)
                  .toDouble();
              final columns = widget.buttons.length <= 2 ? 1 : 2;
              final rows = (widget.buttons.length / columns).ceil().clamp(1, 4);
              final availableItemWidth = (width - ((columns - 1) * 8))
                  .clamp(1.0, width)
                  .toDouble();
              final availableItemHeight = (gridHeight - ((rows - 1) * 8))
                  .clamp(1.0, gridHeight + 1)
                  .toDouble();
              final childAspectRatio =
                  (availableItemWidth / columns) / (availableItemHeight / rows);
              final title = widget.dataName.trim().isEmpty
                  ? _currentValue.toString()
                  : '${widget.dataName}: $_currentValue';

              return Column(
                children: [
                  SizedBox(
                    height: headerHeight,
                    child: Center(
                      child: AutoSizeText(
                        title,
                        textAlign: TextAlign.center,
                        minFontSize: 11,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: gridHeight,
                    width: width,
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        childAspectRatio: childAspectRatio,
                        mainAxisSpacing: FormWidgetStyle.controlGap,
                        crossAxisSpacing: FormWidgetStyle.controlGap,
                      ),
                      itemCount: widget.buttons.length,
                      itemBuilder: (context, index) {
                        final value = widget.buttons[index];
                        final buttonText = value > 0
                            ? '+$value'
                            : value.toString();

                        return ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _currentValue += value;
                              if (_currentValue <= 0) {
                                _currentValue = 0;
                              }
                            });
                            widget.onChanged?.call(_currentValue);
                          },
                          style: FormWidgetStyle.elevatedButtonStyle(
                            context,
                            backgroundColor: theme.colorScheme.surface,
                            foregroundColor: theme.colorScheme.onSurface,
                          ),
                          child: AutoSizeText(
                            buttonText,
                            maxLines: 1,
                            minFontSize: 10,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
