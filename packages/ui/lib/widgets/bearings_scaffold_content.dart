import 'package:material_ui/material_ui.dart';

/// Content that can be presented by a BearingsScaffold.
sealed class BearingsContent {
  const BearingsContent();
}

/// Current insets for the body's scrollable content. Clearance is derived from
/// measured control layouts and follows the same transition progress.
class BearingsBodyLayout {
  const BearingsBodyLayout({required this.scrollPadding});

  final EdgeInsets scrollPadding;
}

/// Search configuration. Controllers and focus nodes belong to the caller.
class BearingsSearch {
  const BearingsSearch({
    required this.controller,
    required this.hintText,
    this.id,
    this.focusNode,
    this.elevation = 8,
  });

  /// Matching IDs share one mounted field across tabs. Shared searches must
  /// use the same controller and focus node. Without an ID, each page has
  /// its own field, even if its text controller is shared with another page.
  final Object? id;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final double elevation;
}

/// A primary action rendered as a mobile FAB or desktop toolbar button.
class BearingsAction {
  const BearingsAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.id,
  });

  /// Matching IDs keep one action mounted across tabs. Otherwise, each page's
  /// action fades independently during tab changes.
  final Object? id;
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
}

/// A page that can be displayed alone or inside BearingsTabs.
class BearingsPage extends BearingsContent {
  const BearingsPage({
    required this.bodyBuilder,
    this.search,
    this.primaryAction,
    this.actions = const [],
    this.header,
    this.footer,
  });

  final BearingsSearch? search;
  final BearingsAction? primaryAction;

  /// Toolbar actions that transition with this page.
  final List<Widget> actions;

  /// Pinned content above and below the body. Scrolling headers and footers
  /// can instead be included in the body's scroll view.
  final Widget? header;
  final Widget? footer;

  /// Apply layout.scrollPadding to the scroll view so all content can clear
  /// the floating controls. The scaffold leaves scrolling to the body.
  final Widget Function(BuildContext context, BearingsBodyLayout layout)
  bodyBuilder;
}

/// A tab's identity, navigation behavior, and reusable page content.
class BearingsTab {
  const BearingsTab({
    required this.id,
    required this.label,
    required this.page,
    this.swipeEnabled = true,
  });

  final Object id;
  final Widget label;
  final BearingsPage page;

  /// Disable page swiping when this tab handles horizontal gestures itself.
  final bool swipeEnabled;
}

/// Managed tabs. IDs must be unique and the list must contain at least one tab.
class BearingsTabs extends BearingsContent {
  const BearingsTabs({
    required this.tabs,
    this.controller,
    this.initialTabId,
    this.onChanged,
  }) : assert(controller == null || initialTabId == null);

  final List<BearingsTab> tabs;

  /// Optional caller-owned controller. Its length must match the tabs. The
  /// caller owns its selection, including when the tab order changes.
  final TabController? controller;

  /// Initial selection for managed tabs. Later rebuilds preserve selection
  /// by tab ID. Removing the selected tab selects the nearest remaining index.
  final Object? initialTabId;

  /// Reports the selected tab's ID for taps, swipes, and controller changes.
  final ValueChanged<Object>? onChanged;
}
