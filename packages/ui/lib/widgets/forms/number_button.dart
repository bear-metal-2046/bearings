import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

import 'form_style.dart';

class NumberButton extends StatefulWidget {
  const NumberButton({
    super.key,
    this.initialValue,
    this.onChanged,
    this.backgroundColor,
    required this.dataName,
    required this.width,
    required this.height,
    this.textAlignment = Alignment.bottomRight,
  });

  final Color? backgroundColor;
  final Alignment textAlignment;
  final String dataName;
  final ValueChanged<int>? onChanged;
  final double width;
  final double height;
  final int? initialValue;

  @override
  State<NumberButton> createState() => _NumberButtonState();
}

class _NumberButtonState extends State<NumberButton> {
  late int _currentVariable = widget.initialValue ?? 0;

  @override
  void didUpdateWidget(covariant NumberButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _currentVariable = widget.initialValue ?? 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ElevatedButton(
        onPressed: () {
          setState(() => _currentVariable++);
          widget.onChanged?.call(_currentVariable);
        },
        style: FormWidgetStyle.elevatedButtonStyle(
          context,
          backgroundColor:
              widget.backgroundColor ?? theme.colorScheme.surfaceContainerLow,
          foregroundColor: theme.colorScheme.onSurface,
          padding: FormWidgetStyle.cardPadding,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: AutoSizeText(
                widget.dataName,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 2,
                minFontSize: 10,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: FormWidgetStyle.controlGap - 2),
            AutoSizeText(
              _currentVariable.toString(),
              textAlign: TextAlign.center,
              maxLines: 1,
              minFontSize: 12,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
            const SizedBox(height: FormWidgetStyle.controlGap),
            Align(
              alignment: widget.textAlignment,
              child: _DecrementButton(
                onPressed: () {
                  setState(() {
                    if (_currentVariable > 0) {
                      _currentVariable--;
                    }
                  });
                  widget.onChanged?.call(_currentVariable);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecrementButton extends StatelessWidget {
  const _DecrementButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 48,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(FormWidgetStyle.borderRadius),
          border: Border.fromBorderSide(FormWidgetStyle.borderSide(context)),
        ),
        child: IconButton(
          iconSize: 24,
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(48, 48),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FormWidgetStyle.borderRadius),
            ),
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(Icons.remove, color: theme.colorScheme.onSurface),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
