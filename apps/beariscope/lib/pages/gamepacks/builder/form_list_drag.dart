part of 'form_editor.dart';

/// A gap between items when [control] is null, or inside a shared row.
typedef _ListPosition = ({GamePackSection section, int item, int? control});

class _ListDrag {
  _ListDrag(this.page, this.from, {required this.label, this.subtitle});

  final GamePackFormPage page;
  final _ListPosition from;
  final String label;
  final String? subtitle;
  Offset anchor = Offset.zero;

  GamePackListItem get item => from.section.items[from.item];
  GamePackControl? get question =>
      from.control == null ? null : item.controls[from.control!];

  Object get identity => question ?? item;

  bool _sameRow(_ListPosition to) =>
      to.section == from.section && to.item == from.item;

  bool canDropAt(_ListPosition to) {
    if (to.section != from.section &&
        to.section.controls.length +
                (question == null ? item.controls.length : 1) >
            128) {
      return false;
    }

    final index = to.control;
    if (index != null) {
      final source = from.control;
      if (source == null) return false;
      if (_sameRow(to)) return index != source && index != source + 1;
      return to.section.items[to.item].controls.length <
          GamePackListItem.maxRowControls;
    }

    final sameSection = to.section == from.section;
    final keepsItem = question == null || !item.isRow;
    return !sameSection ||
        !keepsItem ||
        (to.item != from.item && to.item != from.item + 1);
  }

  List<GamePackSection> moveTo(_ListPosition to) {
    final sameSection = to.section == from.section;
    final source = [...from.section.items];
    final control = question;
    if (control == null || item.controls.length == 1) {
      source.removeAt(from.item);
    } else {
      source[from.item] = GamePackListItem.row(
        [...item.controls]..removeAt(from.control!),
      );
    }

    final target = sameSection ? source : [...to.section.items];
    final itemWasRemoved = source.length < from.section.items.length;
    final index = sameSection && itemWasRemoved && from.item < to.item
        ? to.item - 1
        : to.item;
    if (to.control case final insertion?) {
      final row = [...target[index].controls];
      final at = _sameRow(to) && from.control! < insertion
          ? insertion - 1
          : insertion;
      row.insert(at, control!);
      target[index] = GamePackListItem.row(row);
    } else {
      target.insert(
        index,
        control == null ? item : GamePackListItem.control(control),
      );
    }

    return [
      for (final section in page.sections)
        if (section == to.section || section == from.section)
          GamePackSection(
            id: section.id,
            label: section.label,
            items: section == to.section ? target : source,
          )
        else
          section,
    ];
  }
}

class _ListLanding {
  const _ListLanding(this.drag, this.start);

  final _ListDrag drag;
  final Rect start;
}

/// Paints the new layout from its previous position until the drop settles.
class _ListReflow extends SingleChildRenderObjectWidget {
  const _ListReflow({
    required this.from,
    required this.progress,
    required super.child,
  });

  final Offset? from;
  final double progress;

  @override
  _RenderListReflow createRenderObject(BuildContext context) =>
      _RenderListReflow(from, progress);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderListReflow renderObject,
  ) => renderObject.update(from, progress);
}

class _RenderListReflow extends RenderProxyBox {
  _RenderListReflow(this._from, this._progress);

  Offset? _from;
  double _progress;

  void update(Offset? from, double progress) {
    if (from == _from && progress == _progress) return;
    _from = from;
    _progress = progress;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final from = _from;
    if (from != null && _progress < 1) {
      offset += (from - localToGlobal(Offset.zero)) * (1 - _progress);
    }
    super.paint(context, offset);
  }
}
