part of 'bearings_scaffold.dart';

enum _Role {
  title,
  search,
  primaryAction,
  actions,
  persistentActions,
  header,
  footer,
}

enum _Anchor { top, bottom, end, bottomEnd }

enum _RegionChild { body }

class _ControlId {
  const _ControlId(this.role, this.identity);
  final _Role role;
  final Object identity;

  @override
  bool operator ==(Object other) =>
      other is _ControlId && role == other.role && identity == other.identity;
  @override
  int get hashCode => Object.hash(role, identity);
}

class _ControlRegistry {
  _ControlRegistry(int count)
    : pages = List.generate(count, (_) => <_Role, _ControlId>{});
  final List<Map<_Role, _ControlId>> pages;
  final variants = <_ControlId, Map<int, Widget>>{};

  void add(int page, _Role role, Object identity, Widget widget) {
    final id = _ControlId(role, identity);
    pages[page][role] = id;
    variants.putIfAbsent(id, () => {})[page] = widget;
  }

  List<Widget> children(_PageMotion motion, _RegionGeometry geometry) => [
    for (final entry in variants.entries)
      LayoutId(
        key: ValueKey(entry.key),
        id: entry.key,
        child: _AnimatedControl(
          id: entry.key,
          variants: entry.value,
          controls: this,
          motion: motion,
          geometry: geometry,
        ),
      ),
  ];
}

/// All regions sample the same weights. Retargeting an in-progress tap keeps
/// its current blend as the starting layout, including nonadjacent tabs.
class _PageMotion extends ChangeNotifier {
  _PageMotion(this.controller) {
    final controller = this.controller;
    if (controller == null) return;
    _target = controller.index;
    _startPosition = controller.previousIndex.toDouble();
    _startWeights = List.generate(
      controller.length,
      (index) => index == controller.previousIndex ? 1.0 : 0.0,
    );
    _programmatic = controller.indexIsChanging;
    controller.addListener(_handleController);
    controller.animation!.addListener(notifyListeners);
  }

  static final stationary = _PageMotion(null);
  final TabController? controller;
  bool _programmatic = false;
  int _target = 0;
  double _startPosition = 0;
  List<double> _startWeights = const [1];

  List<double> get weights {
    final controller = this.controller;
    if (controller == null) return const [1];
    final position = controller.animation!.value;
    if (_programmatic) {
      final distance = _target - _startPosition;
      final progress = distance.abs() < precisionErrorTolerance
          ? 1.0
          : ((position - _startPosition) / distance).clamp(0.0, 1.0);
      return [
        for (var index = 0; index < controller.length; index++)
          _startWeights[index] * (1 - progress) +
              (index == _target ? progress : 0),
      ];
    }
    return List.generate(
      controller.length,
      (index) => (1 - (position - index).abs()).clamp(0.0, 1.0),
    );
  }

  void _handleController() {
    final controller = this.controller!;
    if (controller.indexIsChanging) {
      if (!_programmatic || _target != controller.index) {
        _startWeights = weights;
        _startPosition = controller.animation!.value;
        _target = controller.index;
        _programmatic = true;
      }
    } else {
      _programmatic = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    controller?.removeListener(_handleController);
    controller?.animation?.removeListener(notifyListeners);
    super.dispose();
  }
}

class _AnimatedControl extends StatelessWidget {
  const _AnimatedControl({
    required this.id,
    required this.variants,
    required this.controls,
    required this.motion,
    required this.geometry,
  });
  final _ControlId id;
  final Map<int, Widget> variants;
  final _ControlRegistry controls;
  final _PageMotion motion;
  final _RegionGeometry geometry;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: motion,
    builder: (context, _) {
      final weights = motion.weights;
      var presence = 0.0;
      var rolePresence = 0.0;
      var representative = variants.keys.first;
      for (var index = 0; index < weights.length; index++) {
        if (controls.pages[index].containsKey(id.role)) {
          rolePresence += weights[index];
        }
        if (variants.containsKey(index)) {
          presence += weights[index];
          if (weights[index] > weights[representative]) representative = index;
        }
      }
      final selected = motion.controller?.index ?? 0;
      final child = variants[selected] ?? variants[representative]!;
      final interactive = presence >= 1 - precisionErrorTolerance;
      // A role entering or leaving moves through its anchor. Replacements
      // share that role's position and crossfade without changing height.
      final opacity = rolePresence > precisionErrorTolerance
          ? (presence / rolePresence).clamp(0.0, 1.0)
          : 0.0;
      return ExcludeFocus(
        excluding: !interactive,
        child: ExcludeSemantics(
          excluding: !interactive,
          child: IgnorePointer(
            ignoring: !interactive,
            child: Opacity(
              opacity: opacity,
              child: ClipRect(
                clipper: _ControlClipper(geometry, id),
                child: child,
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Geometry is published during layout. Only render clippers listen to it,
/// so clipping follows measured bounds without scheduling widget rebuilds.
class _RegionGeometry extends ChangeNotifier {
  Map<_ControlId, Rect> bounds = {};
  Map<_ControlId, Rect> clips = {};
  void publish(Map<_ControlId, Rect> bounds, Map<_ControlId, Rect> clips) {
    this.bounds = bounds;
    this.clips = clips;
    notifyListeners();
  }
}

class _ControlClipper extends CustomClipper<Rect> {
  _ControlClipper(this.geometry, this.id) : super(reclip: geometry);
  final _RegionGeometry geometry;
  final _ControlId id;
  @override
  Rect getClip(Size size) {
    final bounds = geometry.bounds[id];
    final clip = geometry.clips[id];
    return bounds == null || clip == null
        ? Offset.zero & size
        : clip.shift(-bounds.topLeft);
  }

  @override
  bool shouldReclip(_ControlClipper oldClipper) =>
      geometry != oldClipper.geometry || id != oldClipper.id;
}

class _LayoutRegion extends StatefulWidget {
  const _LayoutRegion({required this.builder});
  final Widget Function(_RegionGeometry geometry) builder;
  @override
  State<_LayoutRegion> createState() => _LayoutRegionState();
}

class _LayoutRegionState extends State<_LayoutRegion> {
  final geometry = _RegionGeometry();
  @override
  void dispose() {
    geometry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ClipRect(child: widget.builder(geometry));
}

typedef _Placement = ({_ControlId id, Rect rect});

class _PageLayout {
  final placements = <_Role, _Placement>{};
  Rect body = Rect.zero;
  EdgeInsets scrollPadding = const EdgeInsets.all(16);
  void place(_ControlRegistry controls, int page, _Role role, Rect rect) {
    if (controls.pages[page][role] case final id?) {
      placements[role] = (id: id, rect: rect);
    }
  }
}

Rect _blendRects(List<Rect> rects, List<double> weights) {
  var left = 0.0;
  var top = 0.0;
  var right = 0.0;
  var bottom = 0.0;
  for (var index = 0; index < rects.length; index++) {
    left += rects[index].left * weights[index];
    top += rects[index].top * weights[index];
    right += rects[index].right * weights[index];
    bottom += rects[index].bottom * weights[index];
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

/// Region-specific resolvers produce endpoint layouts. Matching, replacement,
/// entry, and exit positioning all use this same interpolation path.
abstract class _ResolvedLayoutDelegate extends MultiChildLayoutDelegate {
  _ResolvedLayoutDelegate({
    required this.controls,
    required this.motion,
    required this.geometry,
    required this.direction,
  }) : super(relayout: motion);
  final _ControlRegistry controls;
  final _PageMotion motion;
  final _RegionGeometry geometry;
  final TextDirection direction;

  _Anchor anchor(_Role role);

  Size controlSize(int page, _Role role, Map<_ControlId, Size> sizes) =>
      sizes[controls.pages[page][role]] ?? Size.zero;

  Rect _exit(Rect rect, Size viewport, _Anchor anchor) => switch (anchor) {
    _Anchor.top => Rect.fromLTWH(
      rect.left,
      -rect.height - 16,
      rect.width,
      rect.height,
    ),
    _Anchor.bottom => Rect.fromLTWH(
      rect.left,
      viewport.height + 16,
      rect.width,
      rect.height,
    ),
    _Anchor.end => Rect.fromLTWH(
      direction == TextDirection.ltr ? viewport.width + 16 : -rect.width - 16,
      rect.top,
      rect.width,
      rect.height,
    ),
    _Anchor.bottomEnd => Rect.fromLTWH(
      direction == TextDirection.ltr ? viewport.width + 16 : -rect.width - 16,
      rect.top,
      rect.width,
      rect.height,
    ),
  };

  Alignment alignment(_Anchor anchor) => switch (anchor) {
    _Anchor.top => Alignment.topCenter,
    _Anchor.bottom => Alignment.bottomCenter,
    _Anchor.end =>
      direction == TextDirection.ltr
          ? Alignment.centerRight
          : Alignment.centerLeft,
    _Anchor.bottomEnd =>
      direction == TextDirection.ltr
          ? Alignment.bottomRight
          : Alignment.bottomLeft,
  };

  void positionControls(
    Size size,
    Map<_ControlId, Size> sizes,
    List<_PageLayout> layouts, {
    Rect? body,
  }) {
    final weights = motion.weights;
    final bounds = <_ControlId, Rect>{};
    final clips = <_ControlId, Rect>{};
    for (final id in controls.variants.keys) {
      final ownPlacements = [
        for (final layout in layouts)
          if (layout.placements[id.role] case final placement?
              when placement.id == id)
            placement.rect,
      ];
      final reference = ownPlacements.first;
      final targets = [
        for (final layout in layouts)
          if (layout.placements[id.role] case final placement?)
            placement.id == id
                ? placement.rect
                : alignment(anchor(id.role))
                      .inscribe(sizes[id]!, placement.rect)
          else
            _exit(reference, size, anchor(id.role)),
      ];
      final rect = _blendRects(targets, weights);
      positionChild(id, rect.topLeft);
      bounds[id] = rect.topLeft & sizes[id]!;
      clips[id] = switch (id.role) {
        _Role.header when body != null => Rect.fromLTRB(
          0,
          0,
          size.width,
          body.top,
        ),
        _Role.footer when body != null => Rect.fromLTRB(
          0,
          body.bottom,
          size.width,
          size.height,
        ),
        _ => Offset.zero & size,
      };
    }
    geometry.publish(bounds, clips);
  }

  @override
  bool shouldRelayout(covariant _ResolvedLayoutDelegate oldDelegate) => true;
}

class _PinnedLayout extends _ResolvedLayoutDelegate {
  _PinnedLayout({
    required super.controls,
    required super.motion,
    required super.geometry,
    required super.direction,
    required this.safeBottom,
  });
  final double safeBottom;
  @override
  _Anchor anchor(_Role role) =>
      role == _Role.header ? _Anchor.top : _Anchor.bottom;

  @override
  void performLayout(Size size) {
    final sizes = {
      for (final id in controls.variants.keys)
        id: layoutChild(
          id,
          BoxConstraints(
            maxWidth: size.width,
            maxHeight: size.height,
            minWidth: size.width,
          ),
        ),
    };
    final layouts = <_PageLayout>[];
    for (var page = 0; page < controls.pages.length; page++) {
      final header = controlSize(page, _Role.header, sizes);
      final footer = controlSize(page, _Role.footer, sizes);
      final hasFooter = controls.pages[page].containsKey(_Role.footer);
      final bottom = math.max(
        header.height,
        size.height - footer.height - (hasFooter ? safeBottom : 0),
      );
      final layout = _PageLayout()
        ..body = Rect.fromLTRB(0, header.height, size.width, bottom);
      layout.place(controls, page, _Role.header, Offset.zero & header);
      layout.place(
        controls,
        page,
        _Role.footer,
        Offset(0, size.height - safeBottom - footer.height) & footer,
      );
      layouts.add(layout);
    }
    final body = _blendRects([
      for (final layout in layouts) layout.body,
    ], motion.weights);
    layoutChild(_RegionChild.body, BoxConstraints.tight(body.size));
    positionChild(_RegionChild.body, body.topLeft);
    positionControls(size, sizes, layouts, body: body);
  }
}

/// Padding is a layout input alongside viewport size. Including it in equality
/// lets LayoutBuilder update scroll clearance alongside the control positions.
class _BodyConstraints extends BoxConstraints {
  _BodyConstraints(super.size, this.layout) : super.tight();
  final BearingsBodyLayout layout;
  @override
  bool operator ==(Object other) =>
      other is _BodyConstraints &&
      super == other &&
      layout.scrollPadding == other.layout.scrollPadding;
  @override
  int get hashCode => Object.hash(super.hashCode, layout.scrollPadding);
}

/// TabBarView retains its child list during a page animation. An inherited
/// layout keeps those mounted bodies informed as their clearance changes.
class _BodyLayoutScope extends InheritedWidget {
  const _BodyLayoutScope({required this.layout, required super.child});
  final BearingsBodyLayout layout;

  static BearingsBodyLayout of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BodyLayoutScope>()!.layout;

  @override
  bool updateShouldNotify(_BodyLayoutScope oldWidget) =>
      layout.scrollPadding != oldWidget.layout.scrollPadding;
}

class _FloatingLayout extends _ResolvedLayoutDelegate {
  _FloatingLayout({
    required super.controls,
    required super.motion,
    required super.geometry,
    required super.direction,
    required this.isMobile,
    required this.safeArea,
    required this.hasFooter,
  });
  final bool isMobile;
  final EdgeInsets safeArea;
  final List<bool> hasFooter;
  @override
  _Anchor anchor(_Role role) => role == _Role.search
      ? (isMobile ? _Anchor.bottom : _Anchor.top)
      : _Anchor.bottomEnd;

  @override
  void performLayout(Size size) {
    final width = math.min(
      720.0,
      math.max(0.0, size.width - safeArea.horizontal - 16),
    );
    final left = safeArea.left + (size.width - safeArea.horizontal - width) / 2;
    final sizes = <_ControlId, Size>{};
    for (final id in controls.variants.keys) {
      sizes[id] = layoutChild(
        id,
        BoxConstraints(
          minWidth: id.role == _Role.search ? width : 0,
          maxWidth: width,
        ),
      );
    }
    final layouts = <_PageLayout>[];
    for (var page = 0; page < controls.pages.length; page++) {
      final search = controlSize(page, _Role.search, sizes);
      final action = controlSize(page, _Role.primaryAction, sizes);
      final hasSearch = controls.pages[page].containsKey(_Role.search);
      final hasAction = controls.pages[page].containsKey(_Role.primaryAction);
      final bottomInset = hasFooter[page] ? 0.0 : safeArea.bottom;
      final bottom = size.height - bottomInset - 8;
      final searchTop = isMobile ? bottom - search.height : 8.0;
      final actionBottom = bottom - (hasSearch ? search.height + 8 : 0);
      final actionLeft = direction == TextDirection.ltr
          ? left + width - action.width
          : left;
      final layout = _PageLayout();
      layout.place(
        controls,
        page,
        _Role.search,
        Offset(left, searchTop) & search,
      );
      layout.place(
        controls,
        page,
        _Role.primaryAction,
        Offset(actionLeft, actionBottom - action.height) & action,
      );
      final obstructionTop = hasAction
          ? actionBottom - action.height
          : searchTop;
      layout.scrollPadding = EdgeInsets.fromLTRB(
        16,
        !isMobile && hasSearch ? searchTop + search.height + 8 : 16,
        16,
        isMobile && (hasSearch || hasAction)
            ? size.height - obstructionTop + 16
            : 16 + bottomInset,
      );
      layouts.add(layout);
    }
    var scrollPadding = EdgeInsets.zero;
    final weights = motion.weights;
    for (var page = 0; page < layouts.length; page++) {
      scrollPadding += layouts[page].scrollPadding * weights[page];
    }
    layoutChild(
      _RegionChild.body,
      _BodyConstraints(size, BearingsBodyLayout(scrollPadding: scrollPadding)),
    );
    positionChild(_RegionChild.body, Offset.zero);
    positionControls(size, sizes, layouts);
  }
}

class _ToolbarLayout extends _ResolvedLayoutDelegate {
  _ToolbarLayout({
    required super.controls,
    required super.motion,
    required super.geometry,
    required super.direction,
    required this.toolbarWidth,
    required this.titleSpacing,
    required this.centerTitle,
    required this.actionsPadding,
  });
  final double toolbarWidth;
  final double titleSpacing;
  final bool centerTitle;
  final EdgeInsets actionsPadding;
  @override
  _Anchor anchor(_Role role) =>
      role == _Role.search ? _Anchor.top : _Anchor.end;

  @override
  void performLayout(Size size) {
    final leadingWidth = math.max(0.0, toolbarWidth - size.width);
    final center = (size.width - leadingWidth) / 2;
    final hasSearch = controls.variants.keys.any(
      (id) => id.role == _Role.search,
    );
    final endPadding = direction == TextDirection.ltr
        ? actionsPadding.right
        : actionsPadding.left;
    final budget = math.max(
      0.0,
      hasSearch
          ? size.width - center - 136 - endPadding
          : size.width - titleSpacing - 56 - endPadding,
    );
    final sizes = <_ControlId, Size>{};
    var remaining = budget;
    for (final role in [
      _Role.persistentActions,
      _Role.actions,
      _Role.primaryAction,
    ]) {
      var widest = 0.0;
      for (final id in controls.variants.keys.where((id) => id.role == role)) {
        final measured = layoutChild(
          id,
          BoxConstraints(maxWidth: remaining, maxHeight: size.height),
        );
        sizes[id] = measured;
        widest = math.max(
          widest,
          measured.width + (role == _Role.primaryAction ? 8 : 0),
        );
      }
      remaining = math.max(0, remaining - widest);
    }
    final titleId = controls.pages.first[_Role.title]!;
    final maxActionsWidth = budget - remaining;
    final title = layoutChild(
      titleId,
      BoxConstraints(
        maxWidth: math.max(
          0,
          hasSearch
              ? center - titleSpacing - 136
              : size.width - maxActionsWidth - titleSpacing - endPadding,
        ),
        maxHeight: size.height,
      ),
    );
    sizes[titleId] = title;
    final searchWidths = <double>[];
    for (var page = 0; page < controls.pages.length; page++) {
      final actionWidth =
          controlSize(page, _Role.persistentActions, sizes).width +
          controlSize(page, _Role.actions, sizes).width +
          controlSize(page, _Role.primaryAction, sizes).width +
          (controls.pages[page].containsKey(_Role.primaryAction) ? 8 : 0);
      searchWidths.add(
        math.max(
          0.0,
          math.min(
            720.0,
            2 *
                math.min(
                  center - titleSpacing - title.width - 16,
                  size.width - endPadding - actionWidth - 16 - center,
                ),
          ),
        ),
      );
    }
    for (final id in controls.variants.keys.where(
      (id) => id.role == _Role.search,
    )) {
      final fallback = searchWidths[controls.variants[id]!.keys.first];
      var width = 0.0;
      final weights = motion.weights;
      for (var page = 0; page < controls.pages.length; page++) {
        width +=
            weights[page] *
            (controls.pages[page].containsKey(_Role.search)
                ? searchWidths[page]
                : fallback);
      }
      sizes[id] = layoutChild(
        id,
        BoxConstraints(
          minWidth: width,
          maxWidth: width,
          maxHeight: size.height,
        ),
      );
    }
    Rect logicalRect(double start, Size child) => Rect.fromLTWH(
      direction == TextDirection.ltr ? start : size.width - start - child.width,
      (size.height - child.height) / 2,
      child.width,
      child.height,
    );
    final layouts = <_PageLayout>[];
    for (var page = 0; page < controls.pages.length; page++) {
      final layout = _PageLayout();
      var end = size.width - endPadding;
      for (final role in [
        _Role.persistentActions,
        _Role.actions,
        _Role.primaryAction,
      ]) {
        final child = controlSize(page, role, sizes);
        end -= child.width;
        layout.place(controls, page, role, logicalRect(end, child));
        if (controls.pages[page].containsKey(role) &&
            role == _Role.primaryAction) {
          end -= 8;
        }
      }
      final titleStart = centerTitle && !hasSearch
          ? math.max(
              titleSpacing,
              math.min(center - title.width / 2, end - title.width),
            )
          : titleSpacing;
      layout.place(controls, page, _Role.title, logicalRect(titleStart, title));
      final search = controlSize(page, _Role.search, sizes);
      layout.place(
        controls,
        page,
        _Role.search,
        logicalRect(
          center - searchWidths[page] / 2,
          Size(searchWidths[page], search.height),
        ),
      );
      layouts.add(layout);
    }
    positionControls(size, sizes, layouts);
  }
}
