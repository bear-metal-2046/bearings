import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'bearings_popup_menu.dart';

class BearingsSelectItem<T> {
  const BearingsSelectItem({required this.value, required this.child});

  final T? value;
  final Widget child;
}

/// A controlled, labeled single selection using the shared anchored menu.
class BearingsSelect<T> extends StatelessWidget {
  const BearingsSelect({
    super.key,
    this.value,
    required this.items,
    required this.onChanged,
    this.decoration = const InputDecoration(),
    this.hint,
  });

  final T? value;
  final List<BearingsSelectItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final Widget? hint;

  @override
  Widget build(BuildContext context) {
    final selected = items.where((item) => item.value == value).firstOrNull;
    final onChanged = this.onChanged;
    final enabled = onChanged != null && items.isNotEmpty;
    return BearingsPopupMenu(
      menuChildren: [
        for (final item in items)
          BearingsMenuItem(
            selected: identical(selected, item),
            onPressed: onChanged == null ? null : () => onChanged(item.value),
            child: item.child,
          ),
      ],
      triggerBuilder: (context, controller, focusNode) => InkWell(
        focusNode: focusNode,
        borderRadius: BorderRadius.circular(8),
        onTap: enabled
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
        child: InputDecorator(
          decoration: decoration.copyWith(enabled: enabled),
          isEmpty: selected == null && hint == null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24),
            child: Row(
              children: [
                Expanded(
                  child: selected?.child ?? hint ?? const SizedBox.shrink(),
                ),
                const SizedBox(width: 8),
                const Icon(LucideIcons.chevronDown, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
