import 'dart:ui' show SemanticsRole;

import 'package:flutter/rendering.dart'
    show BoxParentData, RenderCustomSingleChildLayoutBox, RenderTransform;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

part 'bearings_popup_menu_anchor.dart';

/// An animated menu anchored to a custom trigger or a three-dot button.
class BearingsPopupMenu extends StatefulWidget {
  const BearingsPopupMenu({
    super.key,
    required Widget Function(BuildContext, MenuController, FocusNode)
    this._triggerBuilder,
    required this.menuChildren,
    this.controller,
    this.alignmentOffset = Offset.zero,
    this.animationStyle,
  }) : _icon = null,
       _tooltip = null;

  const BearingsPopupMenu.icon({
    super.key,
    required Widget this._icon,
    required this.menuChildren,
    this.controller,
    this.alignmentOffset = Offset.zero,
    this.animationStyle,
    this._tooltip,
  }) : _triggerBuilder = null;

  const BearingsPopupMenu.overflow({
    Key? key,
    required List<Widget> menuChildren,
    MenuController? controller,
    Offset alignmentOffset = Offset.zero,
    String? tooltip,
    AnimationStyle? animationStyle,
  }) : this.icon(
         key: key,
         icon: const Icon(LucideIcons.ellipsisVertical),
         menuChildren: menuChildren,
         controller: controller,
         alignmentOffset: alignmentOffset,
         tooltip: tooltip,
         animationStyle: animationStyle,
       );

  /// The custom trigger should attach the supplied focus node to its button.
  final Widget Function(BuildContext, MenuController, FocusNode)?
  _triggerBuilder;
  final Widget? _icon;
  final String? _tooltip;
  final List<Widget> menuChildren;
  final MenuController? controller;
  final Offset alignmentOffset;

  /// Overrides the shared animation timing and curves for this menu tree.
  final AnimationStyle? animationStyle;

  @override
  State<BearingsPopupMenu> createState() => _BearingsPopupMenuState();
}

class _BearingsPopupMenuState extends State<BearingsPopupMenu> {
  final _triggerFocus = FocusNode();

  @override
  void dispose() {
    _triggerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final triggerBuilder = widget._triggerBuilder;

    return _BearingsMenuAnchor(
      background: colors.surfaceContainerHigh,
      animationStyle: widget.animationStyle,
      controller: widget.controller,
      childFocusNode: _triggerFocus,
      alignmentOffset: widget.alignmentOffset,
      menuChildren: widget.menuChildren,
      builder: (context, controller, _) {
        if (triggerBuilder != null) {
          return triggerBuilder(context, controller, _triggerFocus);
        }
        return IconButton(
          focusNode: _triggerFocus,
          tooltip:
              widget._tooltip ??
              MaterialLocalizations.of(context).showMenuTooltip,
          icon: widget._icon!,
          onPressed: widget.menuChildren.isEmpty
              ? null
              : () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
        );
      },
    );
  }
}

/// An action row. A null [onPressed] displays a disabled row.
class BearingsMenuItem extends StatelessWidget {
  const BearingsMenuItem({
    super.key,
    required this.child,
    this.onPressed,
    this.leadingIcon,
    this.selected,
    this.destructive = false,
    this.closeOnActivate = true,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final Widget? leadingIcon;

  /// True shows a checkmark. False reserves the same space for other choices.
  final bool? selected;
  final bool destructive;
  final bool closeOnActivate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final menu = _BearingsMenuScope.maybeOf(context);
    final onPressed = this.onPressed;
    final destructiveColor = WidgetStateProperty.resolveWith<Color?>(
      (states) => states.contains(WidgetState.disabled) ? null : colors.error,
    );

    return Semantics(
      selected: selected,
      role: SemanticsRole.menuItem,
      child: MenuItemButton(
        style: destructive
            ? _rowStyle.copyWith(
                foregroundColor: destructiveColor,
                iconColor: destructiveColor,
              )
            : _rowStyle,
        onPressed: onPressed == null
            ? null
            : () {
                if (closeOnActivate) menu?.root.close();
                onPressed();
              },
        closeOnActivate: menu == null && closeOnActivate,
        onHover: menu == null
            ? null
            : (hovered) {
                if (hovered) menu.controller.closeChildren();
              },
        leadingIcon: leadingIcon,
        trailingIcon: switch (selected) {
          true => Icon(LucideIcons.check, size: 20, color: colors.primary),
          false => const SizedBox(width: 20),
          null => null,
        },
        child: child,
      ),
    );
  }
}

/// A row that opens a nested menu with the same animation and spacing.
class BearingsSubmenu extends StatefulWidget {
  const BearingsSubmenu({
    super.key,
    required this.child,
    required this.menuChildren,
    this.leadingIcon,
  });

  final Widget child;
  final List<Widget> menuChildren;
  final Widget? leadingIcon;

  @override
  State<BearingsSubmenu> createState() => _BearingsSubmenuState();
}

class _BearingsSubmenuState extends State<BearingsSubmenu> {
  final _focus = FocusNode();
  bool _hovered = false;

  void _handleHover(bool hovered, MenuController controller) {
    _hovered = hovered;
    if (!hovered || controller.isOpen || widget.menuChildren.isEmpty) return;
    // Move focus off the previous row before opening. MenuItemButton closes
    // sibling menus when its focus is lost.
    _focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _hovered && _focus.hasPrimaryFocus && !controller.isOpen) {
        controller.open();
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return _BearingsMenuAnchor(
      background: Theme.of(context).colorScheme.surfaceContainerHighest,
      childFocusNode: _focus,
      menuChildren: widget.menuChildren,
      builder: (context, controller, _) {
        final isOpen = MenuController.maybeIsOpenOf(context) ?? false;
        final enabled = widget.menuChildren.isNotEmpty;
        return CallbackShortcuts(
          bindings: {
            if (enabled)
              SingleActivator(
                rtl
                    ? LogicalKeyboardKey.arrowLeft
                    : LogicalKeyboardKey.arrowRight,
              ): controller.open,
          },
          child: Semantics(
            role: SemanticsRole.menuItem,
            expanded: isOpen,
            child: MenuItemButton(
              style: _rowStyle,
              focusNode: _focus,
              closeOnActivate: false,
              requestFocusOnHover: false,
              onHover: (hovered) => _handleHover(hovered, controller),
              onPressed: enabled
                  ? () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        // Let the previous row close its children before opening.
                        _focus.requestFocus();
                        FocusManager.instance.applyFocusChangesIfNeeded();
                        controller.open();
                      }
                    }
                  : null,
              leadingIcon: widget.leadingIcon,
              trailingIcon: Icon(
                rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight,
                size: 16,
              ),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

const _rowStyle = ButtonStyle(
  padding: WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 20, vertical: 14),
  ),
  iconSize: WidgetStatePropertyAll(20),
);
