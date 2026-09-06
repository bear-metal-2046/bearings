import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';

/// Inserts a [material.Material] ancestor for widgets that still import
/// `package:flutter/material.dart` after apps migrated to `material_ui`.
class FlutterMaterialScope extends StatelessWidget {
  const FlutterMaterialScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return material.Material(
      type: material.MaterialType.transparency,
      child: child,
    );
  }
}
