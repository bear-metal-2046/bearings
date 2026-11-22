import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:motor/motor.dart';

import 'capsule_selector.dart';

enum GamePackDockTab {
  forms('Forms', LucideIcons.clipboardList, true),
  metrics('Metrics', LucideIcons.calculator, false),
  outputs('Outputs', LucideIcons.layoutDashboard, true),
  review('Review', LucideIcons.clipboardCheck, false);

  const GamePackDockTab(this.label, this.icon, this.hasChoices);

  final String label;
  final IconData icon;
  final bool hasChoices;
}

typedef GamePackDockChoice = ({String id, String label, IconData icon});

class GamePackWorkspaceSidebar extends StatelessWidget {
  const GamePackWorkspaceSidebar({
    super.key,
    required this.selected,
    required this.expanded,
    required this.choices,
    required this.selectedChoice,
    required this.onTab,
    required this.onChoice,
    required this.enabled,
  });

  final GamePackDockTab selected;
  final GamePackDockTab? expanded;
  final List<GamePackDockChoice> choices;
  final String? selectedChoice;
  final ValueChanged<GamePackDockTab> onTab;
  final ValueChanged<String> onChoice;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);

    Widget destination({
      required String label,
      required IconData icon,
      required bool active,
      required VoidCallback onTap,
      bool? open,
    }) => Material(
      color: active ? colors.primaryContainer : Colors.transparent,
      shape: active
          ? StadiumBorder(
              side: BorderSide(color: colors.primary.withValues(alpha: .28)),
            )
          : null,
      child: GamePackCapsuleTarget(
        selected: active,
        expanded: open,
        shape: const StadiumBorder(),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 26),
            child: Row(
              spacing: 9,
              children: [
                Icon(icon, size: 17),
                Expanded(child: Text(label)),
                if (open != null)
                  AnimatedRotation(
                    duration: duration,
                    turns: open ? .5 : 0,
                    child: const Icon(LucideIcons.chevronDown, size: 14),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Column(
              spacing: 4,
              children: [
                for (final tab in GamePackDockTab.values) ...[
                  destination(
                    label: tab.label,
                    icon: tab.icon,
                    active: tab == (expanded ?? selected),
                    open: tab.hasChoices ? tab == expanded : null,
                    onTap: () => onTab(tab),
                  ),
                  if (tab.hasChoices)
                    AnimatedSize(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: tab == expanded
                          ? Padding(
                              padding: const EdgeInsets.only(
                                left: 8,
                                bottom: 4,
                              ),
                              child: Column(
                                spacing: 2,
                                children: [
                                  for (final choice in choices)
                                    destination(
                                      label: choice.label,
                                      icon: choice.icon,
                                      active: choice.id == selectedChoice,
                                      onTap: () => onChoice(choice.id),
                                    ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Lays out the editor above the compact dock, with choices overlaying it.
class GamePackWorkspaceDock extends StatefulWidget {
  const GamePackWorkspaceDock({
    super.key,
    required this.child,
    required this.visible,
    required this.selected,
    required this.expanded,
    required this.choices,
    required this.selectedChoice,
    required this.onTab,
    required this.onChoice,
    required this.onDismiss,
    required this.enabled,
  });

  final Widget child;
  final bool visible;
  final GamePackDockTab selected;
  final GamePackDockTab? expanded;
  final List<GamePackDockChoice> choices;
  final String? selectedChoice;
  final ValueChanged<GamePackDockTab> onTab;
  final ValueChanged<String> onChoice;
  final VoidCallback onDismiss;
  final bool enabled;

  GamePackDockTab get highlighted => expanded ?? selected;

  @override
  State<GamePackWorkspaceDock> createState() => _GamePackWorkspaceDockState();
}

class _GamePackWorkspaceDockState extends State<GamePackWorkspaceDock>
    with SingleTickerProviderStateMixin {
  late final _reveal = SingleMotionController(
    vsync: this,
    motion: gamePackNavigationSpring,
    initialValue: widget.expanded == null ? 0 : 1,
  );
  late GamePackDockTab? _shown = widget.expanded;
  late List<GamePackDockChoice> _shownChoices = widget.choices;
  late String? _shownSelection = widget.selectedChoice;

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GamePackWorkspaceDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != null) {
      _shown = widget.expanded;
      _shownChoices = widget.choices;
      _shownSelection = widget.selectedChoice;
    }
    if (widget.expanded != oldWidget.expanded) {
      if (widget.expanded != null && oldWidget.expanded != null) {
        _reveal.value = .78;
      }
      final closing = widget.expanded == null;
      final target = closing ? 0.0 : 1.0;
      if (!widget.visible || MediaQuery.disableAnimationsOf(context)) {
        _reveal.value = target;
        if (closing) _shown = null;
        return;
      }
      final motion = _reveal.animateTo(target);
      if (closing) {
        motion.whenCompleteOrCancel(() {
          if (mounted && widget.expanded == null && _reveal.value == 0) {
            setState(() => _shown = null);
          }
        });
      }
    }
  }

  Widget _bar() => GamePackCapsuleSelector(
    selected: widget.highlighted.index,
    enabled: widget.enabled,
    height: 54,
    inset: 5,
    elevated: true,
    capsuleKey: const ValueKey('gamepack-dock-capsule'),
    indicatorKey: const ValueKey('gamepack-dock-selector'),
    onSelected: (index) => widget.onTab(GamePackDockTab.values[index]),
    segments: [
      for (final tab in GamePackDockTab.values)
        GamePackCapsuleSegment(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 3,
                children: [
                  Icon(tab.icon, size: 19),
                  if (tab.hasChoices)
                    Icon(
                      tab == widget.expanded
                          ? LucideIcons.chevronDown
                          : LucideIcons.chevronUp,
                      size: 11,
                    ),
                ],
              ),
              Text(tab.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
          expanded: tab.hasChoices ? tab == widget.expanded : null,
        ),
    ],
  );

  Widget _tray(GamePackDockTab shown, bool isOpen) => AnimatedBuilder(
    animation: _reveal,
    builder: (_, child) {
      final value = _reveal.value;
      return IgnorePointer(
        ignoring: !isOpen || value <= .05,
        child: ExcludeSemantics(
          excluding: !isOpen,
          child: ExcludeFocus(
            excluding: !isOpen,
            child: Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - value) * 20),
                child: Transform.scale(
                  alignment: Alignment((shown.index + .5) / 2 - 1, 1),
                  scale: .94 + .06 * value.clamp(0.0, 1.2),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );
    },
    child: FocusScope(
      key: ValueKey(shown),
      autofocus: true,
      child: _ChoiceTray(
        tab: shown,
        choices: _shownChoices,
        selectedChoice: _shownSelection,
        onChoice: (id) {
          HapticFeedback.selectionClick();
          widget.onChoice(id);
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final isOpen = widget.visible && widget.expanded != null;
    return CallbackShortcuts(
      bindings: {
        if (isOpen)
          const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
      },
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  ExcludeFocus(excluding: isOpen, child: widget.child),
                  if (widget.visible && shown != null)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 0,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 530),
                          child: _tray(shown, isOpen),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.visible)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 5, 12, 7),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 530),
                    child: _bar(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceTray extends StatefulWidget {
  const _ChoiceTray({
    required this.tab,
    required this.choices,
    required this.selectedChoice,
    required this.onChoice,
  });

  final GamePackDockTab tab;
  final List<GamePackDockChoice> choices;
  final String? selectedChoice;
  final ValueChanged<String> onChoice;

  @override
  State<_ChoiceTray> createState() => _ChoiceTrayState();
}

class _ChoiceTrayState extends State<_ChoiceTray> {
  static const _tileWidth = 124.0;
  static const _gap = 8.0;
  static const _choiceInset = 12.0;
  static const _trayRadius = BorderRadius.all(Radius.circular(32));
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final index = widget.choices.indexWhere(
        (choice) => choice.id == widget.selectedChoice,
      );
      if (index < 0) return;
      final position = _scroll.position;
      final center =
          _choiceInset + index * (_tileWidth + _gap) + _tileWidth / 2;
      _scroll.jumpTo(
        (center - position.viewportDimension / 2).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, limits) => Stack(
        children: [
          Positioned(
            left: limits.maxWidth * (widget.tab.index + .5) / 4 - 6,
            bottom: 2,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: SizedBox.square(
                dimension: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh,
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Container(
              key: const ValueKey('gamepack-dock-tray'),
              clipBehavior: Clip.antiAlias,
              padding: const EdgeInsets.only(
                top: _choiceInset,
                bottom: _choiceInset,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: _trayRadius,
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: .17),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              foregroundDecoration: BoxDecoration(
                border: Border.all(color: colors.outlineVariant),
                borderRadius: _trayRadius,
              ),
              child: SizedBox(
                height: 72,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.stylus,
                      PointerDeviceKind.trackpad,
                    },
                    scrollbars: false,
                  ),
                  child: ListView.separated(
                    key: const ValueKey('gamepack-dock-choices'),
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(
                      _choiceInset,
                      0,
                      _choiceInset,
                      0,
                    ),
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.choices.length,
                    separatorBuilder: (_, _) => const SizedBox(width: _gap),
                    itemBuilder: (_, index) {
                      final choice = widget.choices[index];
                      final selected = choice.id == widget.selectedChoice;
                      return SizedBox(
                        width: _tileWidth,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: selected
                                ? colors.primaryContainer
                                : colors.surfaceContainerLow,
                            border: Border.all(
                              color: selected
                                  ? colors.primary.withValues(alpha: .28)
                                  : colors.outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: GamePackCapsuleTarget(
                            selected: selected,
                            onTap: () => widget.onChoice(choice.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 4,
                                children: [
                                  Icon(choice.icon, size: 16),
                                  Text(
                                    choice.label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
