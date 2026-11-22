import 'package:material_ui/material_ui.dart';

class GamePackEditorActionBar extends StatelessWidget {
  const GamePackEditorActionBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.surfaceContainerHigh,
        shape: StadiumBorder(side: BorderSide(color: colors.outlineVariant)),
        shadows: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: .16),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: const StadiumBorder(),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
