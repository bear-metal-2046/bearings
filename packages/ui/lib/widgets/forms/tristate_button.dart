import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:pressable_flutter/pressable_flutter.dart';

import 'form_style.dart';

class TristateButton extends StatefulWidget {
  const TristateButton({
    super.key,
    this.initialValue,
    required this.dataName,
    required this.width,
    required this.height,
    required this.onChanged,
  });

  final String dataName;
  final double width;
  final double height;
  final ValueChanged<int> onChanged;
  final int? initialValue;

  @override
  State<TristateButton> createState() => _TristateButtonState();
}

class _TristateButtonState extends State<TristateButton> {
  late int _currentState = widget.initialValue ?? 0;

  @override
  void didUpdateWidget(covariant TristateButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        widget.initialValue != null) {
      _currentState = widget.initialValue!;
    }
  }

  Color _backgroundColor(ColorScheme colorScheme) {
    switch (_currentState) {
      case 0:
        return colorScheme.errorContainer;
      case 1:
        return colorScheme.primaryContainer;
      case 2:
        return colorScheme.tertiaryContainer;
      default:
        return colorScheme.surfaceContainerHighest;
    }
  }

  String get _stateLabel {
    switch (_currentState) {
      case 0:
        return 'NO';
      case 1:
        return 'YES';
      case 2:
        return 'MAYBE';
      default:
        return 'UNKNOWN';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Pressable(
        child: ElevatedButton(
          style: FormWidgetStyle.elevatedButtonStyle(
            context,
            backgroundColor: _backgroundColor(theme.colorScheme),
            foregroundColor: theme.colorScheme.onSurface,
            padding: FormWidgetStyle.compactPadding,
          ),
          onPressed: () {
            setState(() {
              _currentState = (_currentState + 1) % 3;
            });
            widget.onChanged(_currentState);
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Flexible(
                child: AutoSizeText(
                  widget.dataName,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  minFontSize: 10,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AnimatedSwitcher(
                duration: FormWidgetStyle.motionFast,
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeOut,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: AutoSizeText(
                  _stateLabel,
                  key: ValueKey(_stateLabel),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  minFontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
