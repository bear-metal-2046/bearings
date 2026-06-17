import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

import 'form_style.dart';

class BoolButton extends StatefulWidget {
  const BoolButton({
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
  final ValueChanged<bool> onChanged;
  final bool? initialValue;

  @override
  State<BoolButton> createState() => _BoolButtonState();
}

class _BoolButtonState extends State<BoolButton> {
  late bool _boolButtonState = widget.initialValue ?? false;

  @override
  void didUpdateWidget(covariant BoolButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        widget.initialValue != null) {
      _boolButtonState = widget.initialValue!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = _boolButtonState;
    final backgroundColor = isEnabled
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.errorContainer;
    final foregroundColor = isEnabled
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onErrorContainer;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ElevatedButton(
        style: FormWidgetStyle.elevatedButtonStyle(
          context,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          padding: FormWidgetStyle.compactPadding,
        ),
        onPressed: () {
          setState(() => _boolButtonState = !_boolButtonState);
          widget.onChanged(_boolButtonState);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Flexible(
              child: AutoSizeText(
                widget.dataName,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
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
              child: Icon(
                isEnabled ? Icons.check_rounded : Icons.close_rounded,
                key: ValueKey(isEnabled),
                size: 18,
                color: foregroundColor,
                semanticLabel: isEnabled ? 'Checked' : 'Not checked',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
