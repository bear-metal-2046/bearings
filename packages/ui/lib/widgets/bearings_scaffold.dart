import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, listEquals, precisionErrorTolerance;
import 'package:material_ui/material_ui.dart';

import 'bearings_scaffold_content.dart';
import 'bearings_search_bar.dart';

export 'bearings_scaffold_content.dart';

part 'bearings_scaffold_layout.dart';

/// An adaptive frame for a page or managed tabs. Each page resolves a complete
/// layout, and controls move between those layouts using their stable IDs.
class BearingsScaffold extends StatelessWidget {
  const BearingsScaffold({
    super.key,
    required this.title,
    required this.content,
    this.leading,
    this.actions = const [],
    this.titleSpacing,
  });

  final Widget title;
  final BearingsContent content;
  final Widget? leading;

  /// Persistent toolbar actions, shared by every page in this scaffold.
  final List<Widget> actions;
  final double? titleSpacing;

  // Mobile preview is enabled for the current Beariscope trial.
  bool get _mobilePreviewEnabled => true;

  @override
  Widget build(BuildContext context) => switch (content) {
    BearingsPage page => _buildLayout(
      context,
      pages: [page],
      pageIds: const [_SinglePage.id],
      motion: _PageMotion.stationary,
    ),
    BearingsTabs tabs => _ManagedTabs(scaffold: this, content: tabs),
  };

  Widget _buildLayout(
    BuildContext context, {
    required List<BearingsPage> pages,
    required List<Object> pageIds,
    required _PageMotion motion,
    BearingsTabs? tabs,
    TabController? controller,
    Map<Object, GlobalKey>? bodyKeys,
  }) {
    assert(() {
      final sharedSearches = <Object, BearingsSearch>{};
      for (final page in pages) {
        final search = page.search;
        if (search?.id == null) continue;
        final previous = sharedSearches[search!.id];
        assert(
          previous == null ||
              (identical(previous.controller, search.controller) &&
                  identical(previous.focusNode, search.focusNode)),
          'Searches with the same ID must share their controller and focus node.',
        );
        sharedSearches[search.id!] = search;
      }
      return true;
    }());
    final isMobile =
        _mobilePreviewEnabled ||
        (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS));
    final direction = Directionality.of(context);
    final safeArea = MediaQuery.paddingOf(context);
    final appBarTheme = AppBarTheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final searchInToolbar = !isMobile && constraints.maxWidth > 900;
        final toolbar = _ControlRegistry(pages.length);
        final floating = _ControlRegistry(pages.length);
        final pinned = _ControlRegistry(pages.length);
        for (var index = 0; index < pages.length; index++) {
          final page = pages[index];
          toolbar.add(
            index,
            _Role.title,
            _Role.title,
            Semantics(header: true, child: title),
          );
          if (actions.isNotEmpty) {
            toolbar.add(
              index,
              _Role.persistentActions,
              _Role.persistentActions,
              IconTheme.merge(
                data: appBarTheme.actionsIconTheme ?? const IconThemeData(),
                child: Row(mainAxisSize: MainAxisSize.min, children: actions),
              ),
            );
          }
          if (page.actions.isNotEmpty) {
            toolbar.add(
              index,
              _Role.actions,
              pageIds[index],
              IconTheme.merge(
                data: appBarTheme.actionsIconTheme ?? const IconThemeData(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: page.actions,
                ),
              ),
            );
          }
          if (page.search case final search?) {
            final controls = searchInToolbar ? toolbar : floating;
            controls.add(
              index,
              _Role.search,
              (search.id != null, search.id ?? pageIds[index]),
              BearingsSearchBar(
                controller: search.controller,
                focusNode: search.focusNode,
                hintText: search.hintText,
                elevation: search.elevation,
              ),
            );
          }
          if (page.primaryAction case final action?) {
            final controls = isMobile ? floating : toolbar;
            controls.add(
              index,
              _Role.primaryAction,
              (action.id != null, action.id ?? pageIds[index]),
              isMobile
                  ? FloatingActionButton.extended(
                      heroTag: null,
                      onPressed: action.onPressed,
                      tooltip: action.label,
                      icon: action.icon,
                      label: Text(action.label),
                    )
                  : FilledButton.icon(
                      onPressed: action.onPressed,
                      icon: action.icon,
                      label: Text(
                        action.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            );
          }
          if (page.header case final header?) {
            pinned.add(
              index,
              _Role.header,
              header.key ?? pageIds[index],
              header,
            );
          }
          if (page.footer case final footer?) {
            pinned.add(
              index,
              _Role.footer,
              footer.key ?? pageIds[index],
              footer,
            );
          }
        }

        final theme = Theme.of(context);
        final platformCentersTitle =
            theme.platform == TargetPlatform.iOS ||
            theme.platform == TargetPlatform.macOS;
        return Scaffold(
          appBar: AppBar(
            leading: leading,
            titleSpacing: 0,
            centerTitle: false,
            excludeHeaderSemantics: true,
            title: SizedBox(
              height: appBarTheme.toolbarHeight ?? kToolbarHeight,
              child: _LayoutRegion(
                builder: (geometry) => CustomMultiChildLayout(
                  delegate: _ToolbarLayout(
                    controls: toolbar,
                    motion: motion,
                    geometry: geometry,
                    direction: direction,
                    toolbarWidth: constraints.maxWidth - safeArea.horizontal,
                    titleSpacing:
                        titleSpacing ??
                        appBarTheme.titleSpacing ??
                        NavigationToolbar.kMiddleSpacing,
                    centerTitle:
                        appBarTheme.centerTitle ?? platformCentersTitle,
                    actionsPadding:
                        appBarTheme.actionsPadding?.resolve(direction) ??
                        EdgeInsets.zero,
                  ),
                  children: toolbar.children(motion, geometry),
                ),
              ),
            ),
            bottom: tabs == null
                ? null
                : TabBar(
                    controller: controller,
                    tabs: [for (final tab in tabs.tabs) Tab(child: tab.label)],
                  ),
          ),
          body: _LayoutRegion(
            builder: (geometry) => CustomMultiChildLayout(
              delegate: _PinnedLayout(
                controls: pinned,
                motion: motion,
                geometry: geometry,
                direction: direction,
                safeBottom: safeArea.bottom,
              ),
              children: [
                LayoutId(
                  id: _RegionChild.body,
                  child: _LayoutRegion(
                    builder: (geometry) => CustomMultiChildLayout(
                      delegate: _FloatingLayout(
                        controls: floating,
                        motion: motion,
                        geometry: geometry,
                        direction: direction,
                        isMobile: isMobile,
                        safeArea: safeArea,
                        hasFooter: [
                          for (final page in pages) page.footer != null,
                        ],
                      ),
                      children: [
                        LayoutId(
                          id: _RegionChild.body,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final layout =
                                  (constraints as _BodyConstraints).layout;
                              final bodies = [
                                for (
                                  var index = 0;
                                  index < pages.length;
                                  index++
                                )
                                  KeyedSubtree(
                                    key: bodyKeys?[pageIds[index]],
                                    child: Builder(
                                      key: PageStorageKey(pageIds[index]),
                                      builder: (context) =>
                                          pages[index].bodyBuilder(
                                            context,
                                            _BodyLayoutScope.of(context),
                                          ),
                                    ),
                                  ),
                              ];
                              final body = tabs == null
                                  ? bodies.single
                                  : ListenableBuilder(
                                      listenable: controller!,
                                      builder: (context, _) => TabBarView(
                                        controller: controller,
                                        physics:
                                            tabs
                                                .tabs[controller.index]
                                                .swipeEnabled
                                            ? const PageScrollPhysics()
                                            : const NeverScrollableScrollPhysics(),
                                        children: bodies,
                                      ),
                                    );
                              return _BodyLayoutScope(
                                layout: layout,
                                child: body,
                              );
                            },
                          ),
                        ),
                        ...floating.children(motion, geometry),
                      ],
                    ),
                  ),
                ),
                ...pinned.children(motion, geometry),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _SinglePage { id }

class _ManagedTabs extends StatefulWidget {
  const _ManagedTabs({required this.scaffold, required this.content});

  final BearingsScaffold scaffold;
  final BearingsTabs content;

  @override
  State<_ManagedTabs> createState() => _ManagedTabsState();
}

class _ManagedTabsState extends State<_ManagedTabs>
    with TickerProviderStateMixin {
  late TabController _controller;
  late _PageMotion _motion;
  late bool _ownsController;
  late List<Object> _ids;
  late Object _selectedId;
  // TabBarView wraps bodies in index-keyed semantics. These keys let a body
  // retain its state when its tab moves between those wrappers.
  final _bodyKeys = <Object, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _validateTabs();
    _ids = [for (final tab in widget.content.tabs) tab.id];
    final initialId = widget.content.initialTabId;
    assert(
      initialId == null || _ids.contains(initialId),
      'Initial tab ID must identify a tab.',
    );
    _ownsController = widget.content.controller == null;
    _controller =
        widget.content.controller ??
        TabController(
          length: _ids.length,
          initialIndex: initialId == null ? 0 : _ids.indexOf(initialId),
          vsync: this,
        );
    _selectedId = _ids[_controller.index];
    _motion = _PageMotion(_controller);
    _controller.addListener(_handleSelection);
  }

  void _validateTabs() {
    final content = widget.content;
    assert(content.tabs.isNotEmpty, 'BearingsTabs requires at least one tab.');
    assert(
      content.tabs.map((tab) => tab.id).toSet().length == content.tabs.length,
      'Tab IDs must be unique.',
    );
    assert(
      content.controller == null ||
          content.controller!.length == content.tabs.length,
      'The tab controller length must match the tabs.',
    );
  }

  @override
  void didUpdateWidget(_ManagedTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    _validateTabs();
    final ids = [for (final tab in widget.content.tabs) tab.id];
    final external = widget.content.controller;
    final replaceController = external == null
        ? !_ownsController || !listEquals(ids, _ids)
        : !identical(external, _controller);
    final previousId = _selectedId;
    if (replaceController) {
      final previousIndex = _controller.index;
      _motion.dispose();
      _controller.removeListener(_handleSelection);
      if (_ownsController) _controller.dispose();
      final preservedIndex = ids.indexOf(previousId);
      _ownsController = external == null;
      _controller =
          external ??
          TabController(
            length: ids.length,
            initialIndex: preservedIndex >= 0
                ? preservedIndex
                : math.min(previousIndex, ids.length - 1),
            vsync: this,
          );
      _motion = _PageMotion(_controller);
      _controller.addListener(_handleSelection);
    }
    _ids = ids;
    _bodyKeys.removeWhere((id, _) => !ids.contains(id));
    _selectedId = _ids[_controller.index];
    if (previousId != _selectedId) {
      final selectedId = _selectedId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedId == selectedId) {
          widget.content.onChanged?.call(selectedId);
        }
      });
    }
  }

  void _handleSelection() {
    final id = _ids[_controller.index];
    if (id == _selectedId) return;
    _selectedId = id;
    widget.content.onChanged?.call(id);
  }

  @override
  void dispose() {
    _motion.dispose();
    _controller.removeListener(_handleSelection);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final id in _ids) {
      _bodyKeys.putIfAbsent(id, () => GlobalKey());
    }
    return widget.scaffold._buildLayout(
      context,
      pages: [for (final tab in widget.content.tabs) tab.page],
      pageIds: _ids,
      tabs: widget.content,
      controller: _controller,
      motion: _motion,
      bodyKeys: _bodyKeys,
    );
  }
}
