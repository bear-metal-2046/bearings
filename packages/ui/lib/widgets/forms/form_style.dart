import 'package:flutter/material.dart';

class FormWidgetStyle {
  const FormWidgetStyle._();

  static const double borderRadius = 0;
  static const double borderWidth = 1.1;
  static const EdgeInsets cardPadding = EdgeInsets.all(8);
  static const EdgeInsets compactPadding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 8,
  );
  static const double controlGap = 8;
  static const Duration motionFast = Duration(milliseconds: 140);
  static const VisualDensity compactDensity = VisualDensity(
    horizontal: -1,
    vertical: -1,
  );

  static BorderSide borderSide(BuildContext context, {Color? color}) {
    return BorderSide(
      color: color ?? Theme.of(context).colorScheme.outlineVariant,
      width: borderWidth,
    );
  }

  static RoundedRectangleBorder shape(
    BuildContext context, {
    Color? borderColor,
    double? radius,
  }) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius ?? borderRadius),
      side: borderSide(context, color: borderColor),
    );
  }

  static BoxDecoration panelDecoration(
    BuildContext context, {
    Color? fillColor,
    Color? borderColor,
  }) {
    final theme = Theme.of(context);
    return BoxDecoration(
      color: fillColor ?? theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.fromBorderSide(borderSide(context, color: borderColor)),
    );
  }

  static ButtonStyle elevatedButtonStyle(
    BuildContext context, {
    required Color backgroundColor,
    Color? foregroundColor,
    EdgeInsetsGeometry padding = compactPadding,
    double? radius,
  }) {
    final theme = Theme.of(context);
    return ElevatedButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor ?? theme.colorScheme.onSurface,
      surfaceTintColor: Colors.transparent,
      overlayColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
      shape: shape(context, radius: radius),
      padding: padding,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: Size.zero,
      visualDensity: compactDensity,
      animationDuration: motionFast,
      elevation: 0,
    );
  }

  static InputDecoration textFieldDecoration({
    required BuildContext context,
    required String label,
    Color? fillColor,
    Color? outlineColor,
  }) {
    final theme = Theme.of(context);
    final resolvedOutline = outlineColor ?? theme.colorScheme.outlineVariant;
    final resolvedFill = fillColor ?? theme.colorScheme.surfaceContainerLow;

    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: borderSide(context, color: color),
    );

    return InputDecoration(
      filled: true,
      fillColor: resolvedFill,
      isDense: true,
      alignLabelWithHint: true,
      labelText: label,
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      floatingLabelStyle: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
      border: border(resolvedOutline),
      enabledBorder: border(resolvedOutline),
      errorBorder: border(theme.colorScheme.error),
      focusedErrorBorder: border(theme.colorScheme.error),
      focusedBorder: border(theme.colorScheme.primary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }
}
