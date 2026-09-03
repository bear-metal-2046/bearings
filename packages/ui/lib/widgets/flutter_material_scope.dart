import 'package:material_ui/material_ui.dart' as flutter;
import 'package:flutter/widgets.dart';

/// Inserts a [flutter.Material] ancestor for widgets that still import
/// `package:flutter/material.dart` after apps migrated to `material_ui`.
class FlutterMaterialScope extends StatelessWidget {
  const FlutterMaterialScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return flutter.Material(
      color: flutter.Colors.transparent,
      child: child,
    );
  }
}
