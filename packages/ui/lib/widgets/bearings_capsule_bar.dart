import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'bearings_capsule_selector.dart';

enum BearingsCapsuleBarVariant { compact, dock }

class BearingsCapsuleDestination<T extends Object> {
  const BearingsCapsuleDestination({
    required this.value,
    required this.label,
    this.icon,
    this.expanded,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// Whether an associated tray is open. A null value omits the chevron.
  final bool? expanded;
}

/// A capsule navigation bar with selection controlled by its caller.
class BearingsCapsuleBar<T extends Object> extends StatelessWidget {
  const BearingsCapsuleBar({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onActivated,
    this.variant = BearingsCapsuleBarVariant.compact,
  });

  final List<BearingsCapsuleDestination<T>> destinations;
  final T selected;

  /// Also called when the selected destination is pressed again.
  /// Pass null to disable activation.
  final ValueChanged<T>? onActivated;
  final BearingsCapsuleBarVariant variant;

  @override
  Widget build(BuildContext context) {
    final index = destinations.indexWhere(
      (destination) => destination.value == selected,
    );
    assert(index >= 0, 'The selected value must be a destination.');
    final dock = variant == BearingsCapsuleBarVariant.dock;
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    return BearingsCapsuleSelector(
      selected: index,
      enabled: onActivated != null,
      height: (dock ? 54 : 40) + (scale - 1).clamp(0.0, 2.0) * 14,
      inset: dock ? 5 : 4,
      elevated: dock,
      minimumSegmentWidth: (dock ? 64 : 56) * scale.clamp(1.0, 2.0),
      onSelected: (index) => onActivated?.call(destinations[index].value),
      segments: [
        for (final destination in destinations)
          BearingsCapsuleSegment(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: _DestinationLabel(destination: destination),
              
            ),
            expanded: destination.expanded,
          ),
      ],
    );
  }
}

class _DestinationLabel extends StatelessWidget {
  const _DestinationLabel({required this.destination});

  final BearingsCapsuleDestination<Object> destination;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      destination.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final expanded = destination.expanded;
    final chevron = expanded == null
        ? null
        : Icon(
            expanded ? LucideIcons.chevronDown : LucideIcons.chevronUp,
            size: 11,
          );
    final icon = destination.icon;
    return Center(
      child: icon != null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 3,
                  children: [Icon(icon, size: 19), ?chevron],
                ),
                label,
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 3,
              children: [
                Flexible(child: label),
                ?chevron,
              ],
            ),
    );
  }
}
