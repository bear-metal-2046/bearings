import 'dart:async';
import 'dart:math' as math;

import 'package:beariscope/widgets/editor_draggable.dart';
import 'package:core/core.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/services.dart' show HapticFeedback, LogicalKeyboardKey;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';
import 'package:ui/widgets/forms/gamepack_form_view.dart';

import 'design.dart';
import 'editor_action_bar.dart';
import 'form_grid.dart';
import 'question_editor.dart';

part 'form_list_drag.dart';

typedef _ControlSlot = ({String? section, int item, int index});

class GamePackFormsEditor extends StatefulWidget {
  const GamePackFormsEditor({
    super.key,
    required this.design,
    required this.onChanged,
    required this.compact,
    required this.formSelection,
  });

  final GamePackDesign design;
  final ValueChanged<GamePackDesign> onChanged;
  final bool compact;
  final ValueNotifier<String?> formSelection;

  @override
  State<GamePackFormsEditor> createState() => _GamePackFormsEditorState();
}

class _GamePackFormsEditorState extends State<GamePackFormsEditor>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  String? _pageId;
  String? _selectedControl;
  final _selectionAnchor = GlobalKey();
  final _listViewport = GlobalKey();
  final _listScroll = ScrollController();
  final _listGaps = <_ListPosition, GlobalKey>{};
  final _listItems = <Object, GlobalKey>{};
  final _listFeedback = GlobalKey();
  final _listHover = ValueNotifier<_ListPosition?>(null);
  late final _listMotion =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 250),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {
            _listLanding = null;
            _listOrigins = const {};
          });
        }
      });
  _ListLanding? _listLanding;
  Map<Object, Offset> _listOrigins = const {};
  _ListDrag? _listDrag;
  Offset? _dragPointer;
  Timer? _listScrollTimer;
  double _listScrollStep = 0;

  void _revealSelection({bool center = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _selectionAnchor.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: .5,
        alignmentPolicy: center
            ? ScrollPositionAlignmentPolicy.explicit
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: MediaQuery.disableAnimationsOf(target)
            ? Duration.zero
            : const Duration(milliseconds: 200),
      );
    });
  }

  GamePackForm get _form =>
      widget.design.forms
          .where((form) => form.id == widget.formSelection.value)
          .firstOrNull ??
      widget.design.forms.first;

  GamePackFormPage get _page =>
      _form.pages.where((page) => page.id == _pageId).firstOrNull ??
      _form.pages.first;

  Map<String, GamePackField> get _fields => widget.design.fieldById;

  @override
  void initState() {
    super.initState();
    widget.formSelection.addListener(_formChanged);
  }

  @override
  void didUpdateWidget(GamePackFormsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.design != widget.design) {
      _pruneListItems();
    }
    if (oldWidget.formSelection != widget.formSelection) {
      oldWidget.formSelection.removeListener(_formChanged);
      widget.formSelection.addListener(_formChanged);
      _formChanged();
    }
  }

  @override
  void dispose() {
    widget.formSelection.removeListener(_formChanged);
    _listScrollTimer?.cancel();
    _listScroll.dispose();
    _listHover.dispose();
    _listMotion.dispose();
    super.dispose();
  }

  void _formChanged() {
    setState(() {
      _pageId = null;
      _selectedControl = null;
    });
    _pruneListItems();
  }

  void _pruneListItems() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _listItems.removeWhere((_, key) => key.currentContext == null);
      }
    });
  }

  void _replaceForm(
    GamePackForm form, {
    GamePackField? question,
    String? removing,
  }) {
    final forms = widget.design.forms;
    final index = forms.indexWhere((item) => item.id == form.id);
    _commit(
      replaceAt(forms, index, form),
      question: question,
      removing: removing,
    );
  }

  Future<void> _commit(
    List<GamePackForm> forms, {
    GamePackField? question,
    String? removing,
  }) async {
    final design = widget.design;
    final fields = [...design.fields];
    if (removing != null) {
      final uses = design.formRemovalDependencies(forms);
      final confirmed = await BearingsModal.show<bool>(
        context,
        builder: (context) => BearingsModal(
          title: uses.isEmpty ? 'Remove $removing?' : '$removing is in use',
          actions: const [],
          primaryAction: uses.isEmpty
              ? BearingsModalPrimaryAction(
                  label: 'Remove',
                  icon: LucideIcons.trash2,
                  onPressed: () => BearingsModal.complete(context, true),
                )
              : null,
          content: uses.isEmpty
              ? const Text(
                  'Its questions and layout will be removed from this draft.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    const Text('Update these references before removing it.'),
                    for (final use in uses) Text(use),
                  ],
                ),
        ),
      );
      if (!mounted || confirmed != true || widget.design != design) return;
      final placed = forms
          .expand((form) => form.controls)
          .map((control) => control.field)
          .toSet();
      final previouslyPlaced = design.questions
          .map((item) => item.field.id)
          .toSet();
      fields.removeWhere(
        (field) =>
            previouslyPlaced.contains(field.id) && !placed.contains(field.id),
      );
      if (!placed.contains(_selectedControl)) {
        setState(() => _selectedControl = null);
      }
    }
    if (question != null) {
      final index = fields.indexWhere((field) => field.id == question.id);
      if (index == -1) {
        fields.add(question);
      } else {
        fields[index] = question;
      }
    }
    widget.onChanged(design.copyWith(forms: forms, fields: fields));
  }

  void _setPages(
    List<GamePackFormPage> pages, {
    GamePackField? question,
    String? removing,
  }) {
    final form = _form;
    _replaceForm(
      GamePackForm(
        id: form.id,
        label: form.label,
        kind: form.kind,
        pages: pages,
      ),
      question: question,
      removing: removing,
    );
  }

  void _setPage(
    GamePackFormPage page, {
    GamePackField? question,
    String? removing,
  }) {
    final pages = _form.pages;
    final index = pages.indexWhere((entry) => entry.id == page.id);
    _setPages(
      index < 0 ? [...pages, page] : replaceAt(pages, index, page),
      question: question,
      removing: removing,
    );
    setState(() => _pageId = page.id);
  }

  void _setSections(
    List<GamePackSection> sections, {
    GamePackField? question,
    String? removing,
  }) {
    final page = _page;
    _setPage(
      GamePackFormPage.scrolling(
        id: page.id,
        label: page.label,
        sections: sections,
      ),
      question: question,
      removing: removing,
    );
  }

  void _setSection(
    GamePackSection section, {
    GamePackField? question,
    String? removing,
  }) {
    final sections = _page.sections;
    final index = sections.indexWhere((entry) => entry.id == section.id);
    _setSections(
      index < 0 ? [...sections, section] : replaceAt(sections, index, section),
      question: question,
      removing: removing,
    );
  }

  void _setItems(
    GamePackSection section,
    List<GamePackListItem> items, {
    GamePackField? question,
    String? removing,
  }) => _setSection(
    GamePackSection(id: section.id, label: section.label, items: items),
    question: question,
    removing: removing,
  );

  Future<String?> _name(String label, [String initial = '']) =>
      BearingsModal.show<String>(
        context,
        builder: (_) => _NameModal(label: label, initial: initial),
      );

  Future<void> _editPage([GamePackFormPage? page]) async {
    final form = _form;
    final result = await BearingsModal.show<GamePackFormPage>(
      context,
      builder: (_) => _PageModal(
        page: page,
        ids: form.pages.map((entry) => entry.id),
        nextNumber: form.pages.length + 1,
        initialLayout: form.kind == GamePackFormKind.match
            ? GamePackPageLayout.grid
            : GamePackPageLayout.scrolling,
      ),
    );
    if (!mounted || result == null) return;
    _setPage(result);
    setState(() => _selectedControl = null);
  }

  Future<void> _editSection([GamePackSection? section]) async {
    final label = await _name('Section name', section?.label ?? '');
    if (!mounted || label == null) return;
    _setSection(
      GamePackSection(
        id:
            section?.id ??
            gamePackIdForName(
              label,
              _page.sections.map((entry) => entry.id),
              'section',
            ),
        label: label,
        items: section?.items ?? const [],
      ),
    );
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  GamePackControl? _controlAt(_ControlSlot slot) {
    final page = _page;
    if (page.usesGrid) return page.gridControls.elementAtOrNull(slot.index);
    return page.sections
        .firstWhere((section) => section.id == slot.section)
        .items
        .elementAtOrNull(slot.item)
        ?.controls
        .elementAtOrNull(slot.index);
  }

  void _updateControl(
    _ControlSlot slot,
    GamePackControl? control, {
    GamePackField? question,
  }) {
    final removing = control == null
        ? _fields[_controlAt(slot)?.field]?.label
        : null;
    final page = _page;
    if (page.usesGrid) {
      final controls = [...page.gridControls];
      if (control == null) {
        controls.removeAt(slot.index);
      } else if (slot.index == controls.length) {
        controls.add(control);
      } else {
        controls[slot.index] = control;
      }
      _setPage(
        GamePackFormPage.grid(
          id: page.id,
          label: page.label,
          columns: page.columns!,
          rows: page.rows!,
          controls: controls,
        ),
        question: question,
        removing: removing,
      );
      return;
    }
    final section = page.sections.firstWhere(
      (section) => section.id == slot.section,
    );
    final items = [...section.items];
    if (slot.item == items.length) {
      items.add(GamePackListItem.control(control!));
    } else {
      final item = items[slot.item];
      final controls = [...item.controls];
      if (control == null) {
        controls.removeAt(slot.index);
      } else if (slot.index == controls.length) {
        controls.add(control);
      } else {
        controls[slot.index] = control;
      }
      if (controls.isEmpty) {
        items.removeAt(slot.item);
      } else if (item.isRow) {
        items[slot.item] = GamePackListItem.row(controls);
      } else {
        items[slot.item] = GamePackListItem.control(controls.single);
      }
    }
    _setItems(section, items, question: question, removing: removing);
  }

  Future<void> _editControl(
    _ControlSlot slot, {
    GamePackSection? newSection,
  }) async {
    final form = _form;
    final page = _page;
    final current = newSection == null ? _controlAt(slot) : null;
    final placement =
        current?.placement ??
        (page.usesGrid
            ? findGridPlacement(page.columns!, page.rows!, page.gridControls)
            : null);
    if (page.usesGrid && placement == null) {
      _message('The grid is full. Increase its size or move a question.');
      return;
    }
    final controls = {
      for (final control in form.controls) control.field: control,
    };
    bool canDependOn(String id) {
      final seen = {if (current != null) current.field};
      String? next = id;
      while (next != null) {
        if (!seen.add(next)) return false;
        next = controls[next]?.visibleWhen?.field;
      }
      return true;
    }

    final choice = await editGamePackQuestion(
      context,
      ids: _fields.keys.toSet(),
      field: _fields[current?.field],
      control: current,
      page: page,
      placement: placement,
      conditionFields: [
        for (final id in controls.keys)
          if (_fields[id] case final field?
              when field.type.kind != GamePackTypeKind.list && canDependOn(id))
            field,
      ],
    );
    if (!mounted ||
        choice == null ||
        _form.id != form.id ||
        _page.id != page.id) {
      return;
    }
    for (final question in widget.design.questions) {
      if (!identical(question.control, current) &&
          question.field.id == choice.field.id &&
          !question.control.type.accepts(choice.field)) {
        _message(
          'This answer type is used in ${question.form.label} › ${question.page.label}.',
        );
        return;
      }
    }
    if (newSection == null) {
      _updateControl(slot, choice.control, question: choice.field);
    } else {
      _setSection(
        GamePackSection(
          id: newSection.id,
          label: newSection.label,
          items: [GamePackListItem.control(choice.control)],
        ),
        question: choice.field,
      );
    }
    setState(() => _selectedControl = choice.field.id);
    _revealSelection(center: current == null && !page.usesGrid);
  }

  void _moveRowControl(
    GamePackSection section,
    int itemIndex,
    int from,
    int to,
  ) {
    final row = section.items[itemIndex];
    _setItems(
      section,
      replaceAt(
        section.items,
        itemIndex,
        GamePackListItem.row(_reordered(row.controls, from, to)),
      ),
    );
  }

  Future<GamePackSection?> _pickSection(
    String title,
    Iterable<GamePackSection> sections,
  ) => BearingsModal.show<GamePackSection>(
    context,
    builder: (context) => BearingsModal(
      title: title,
      actions: const [],
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final section in sections)
            ListTile(
              title: Text(section.label),
              onTap: () => BearingsModal.complete(context, section),
            ),
        ],
      ),
    ),
  );

  Future<void> _moveItemToSection(GamePackSection source, int index) async {
    final page = _page;
    final target = await _pickSection(
      'Move to section',
      page.sections.where((section) => section != source),
    );
    if (!mounted || target == null || !identical(page, _page)) return;
    _setSections([
      for (final section in page.sections)
        if (section == source)
          GamePackSection(
            id: section.id,
            label: section.label,
            items: [...section.items]..removeAt(index),
          )
        else if (section == target)
          GamePackSection(
            id: section.id,
            label: section.label,
            items: [...section.items, source.items[index]],
          )
        else
          section,
    ]);
  }

  Future<void> _addListQuestion([GamePackSection? section]) {
    final target =
        section ??
        GamePackSection(id: 'questions', label: 'Questions', items: []);
    return _editControl((
      section: target.id,
      item: target.items.length,
      index: 0,
    ), newSection: section == null ? target : null);
  }

  Widget _addQuestionButton(VoidCallback onPressed) => FilledButton.icon(
    onPressed: onPressed,
    icon: const Icon(LucideIcons.plus),
    label: const Text('Add question'),
  );

  void _preview(GamePackForm form, GamePackFormPage page) {
    try {
      form.validate(_fields);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => InheritedTheme.captureAll(
            context,
            _ScoutFormPreview(fields: _fields, form: form, page: page),
          ),
        ),
      );
    } on FormatException catch (error) {
      _message(error.message);
    }
  }

  Widget _questionActions(
    _ControlSlot slot,
    GamePackField field,
    List<Widget> options,
  ) => _QuestionActions(
    label: field.label,
    onEdit: () => _editControl(slot),
    onRemove: () => _updateControl(slot, null),
    options: options,
  );

  Widget _grid(GamePackFormPage page) {
    final index = page.gridControls.indexWhere(
      (control) => control.field == _selectedControl,
    );
    _ControlSlot slot(int index) => (section: null, item: 0, index: index);
    final grid = GamePackGridEditor(
      page: page,
      fields: _fields,
      selected: _selectedControl,
      selectedAnchor: _selectionAnchor,
      selectionActions: index < 0
          ? null
          : _questionActions(
              slot(index),
              _fields[page.gridControls[index].field]!,
              const [],
            ),
      onSelect: (id) => setState(() => _selectedControl = id),
      onEdit: (control) =>
          _editControl(slot(page.gridControls.indexOf(control))),
      onPlace: (control, placement) => _updateControl(
        slot(page.gridControls.indexOf(control)),
        controlWithPlacement(control, placement),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: widget.compact ? 0 : 16),
      child: widget.compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: grid),
                const SizedBox(height: 8),
                Center(
                  child: _addQuestionButton(
                    () => _editControl((
                      section: null,
                      item: 0,
                      index: page.gridControls.length,
                    )),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            )
          : grid,
    );
  }

  List<Widget> _sectionActions(GamePackFormPage page, int index) {
    final section = page.sections[index];
    return [
      BearingsMenuItem(
        onPressed: () => _editSection(section),
        child: const Text('Rename section'),
      ),
      BearingsMenuItem(
        onPressed: index > 0
            ? () => _setSections(_reordered(page.sections, index, index - 1))
            : null,
        child: const Text('Move section up'),
      ),
      BearingsMenuItem(
        onPressed: index < page.sections.length - 1
            ? () => _setSections(_reordered(page.sections, index, index + 1))
            : null,
        child: const Text('Move section down'),
      ),
      BearingsMenuItem(
        onPressed: () => _setSections(
          [...page.sections]..removeAt(index),
          removing: section.label,
        ),
        destructive: true,
        child: const Text('Remove section'),
      ),
    ];
  }

  void _startListDrag(_ListDrag drag) {
    HapticFeedback.selectionClick();
    setState(() => _listDrag = drag);
  }

  void _finishListDrag() {
    if (!mounted || _listDrag == null) return;
    _leaveListDropArea();
    _listGaps.clear();
    setState(() => _listDrag = null);
  }

  void _stopListScroll() {
    _listScrollTimer?.cancel();
    _listScrollTimer = null;
    _listScrollStep = 0;
  }

  void _leaveListDropArea() {
    _stopListScroll();
    _dragPointer = null;
    _listHover.value = null;
  }

  RenderBox? get _listViewportBox {
    final object = _listViewport.currentContext?.findRenderObject();
    return object is RenderBox && object.attached && object.hasSize
        ? object
        : null;
  }

  Rect? _listBounds(GlobalKey? key, {RenderBox? relativeTo}) {
    final box = key?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(relativeTo),
      Offset.zero & box.size,
    );
  }

  _ListPosition? _listDropAt(Offset pointer) {
    final viewport = _listBounds(_listViewport);
    final drag = _listDrag;
    if (drag == null ||
        !identical(drag.page, _page) ||
        viewport == null ||
        !viewport.contains(pointer)) {
      return null;
    }
    _ListPosition? allowed(_ListPosition position) =>
        drag.canDropAt(position) ? position : null;

    for (final MapEntry(key: position, value: key) in _listGaps.entries) {
      final bounds = _listBounds(key);
      final emptySection = position.section.items.isEmpty;
      if (bounds != null &&
          (emptySection ? bounds.inflate(16) : bounds).contains(pointer)) {
        return allowed(position);
      }
    }
    for (final section in _page.sections) {
      for (final (index, item) in section.items.indexed) {
        final heading = _listBounds(
          _listItems[item.isRow ? item : item.controls.single],
        );
        if (heading == null) continue;
        var wholeItem = heading;
        if (item.isRow) {
          for (final (control, question) in item.controls.indexed) {
            final bounds = _listBounds(_listItems[question]);
            if (bounds == null) continue;
            wholeItem = wholeItem.expandToInclude(bounds);
            if (drag.question != null && bounds.contains(pointer)) {
              return allowed((
                section: section,
                item: index,
                control: control + (pointer.dy < bounds.center.dy ? 0 : 1),
              ));
            }
          }
          if (item.controls.isEmpty &&
              drag.question != null &&
              heading.contains(pointer) &&
              pointer.dx >= heading.left + 25) {
            return allowed((section: section, item: index, control: 0));
          }
        }
        if (wholeItem.contains(pointer)) {
          return allowed((
            section: section,
            item: index + (pointer.dy < wholeItem.center.dy ? 0 : 1),
            control: null,
          ));
        }
      }
    }
    return null;
  }

  void _updateListHover() {
    final pointer = _dragPointer;
    if (pointer == null) return;
    final next = _listDropAt(pointer);
    if (next == _listHover.value) return;
    _listHover.value = next;
    if (next != null) HapticFeedback.selectionClick();
  }

  void _trackListDrag(Offset pointer) {
    if (_listDrag == null) return;
    _dragPointer = pointer;
    _updateListHover();
    final viewport = _listViewportBox;
    final local = viewport?.globalToLocal(pointer);
    _listScrollStep = 0;
    if (viewport != null &&
        local != null &&
        (Offset.zero & viewport.size).contains(local)) {
      final edge = math.min(64.0, viewport.size.height / 3);
      if (local.dy < edge) _listScrollStep = -8;
      if (local.dy > viewport.size.height - edge) _listScrollStep = 8;
    }
    if (_listScrollStep == 0) {
      _stopListScroll();
      return;
    }
    _listScrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_listScroll.hasClients || !identical(_listDrag?.page, _page)) return;
      final scroll = _listScroll.position;
      final next = (scroll.pixels + _listScrollStep).clamp(
        scroll.minScrollExtent,
        scroll.maxScrollExtent,
      );
      if (next == scroll.pixels) return;
      _listScroll.jumpTo(next);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateListHover();
      });
    });
  }

  void _landListDrag(_ListDrag drag, {_ListPosition? target}) {
    if (!mounted || drag != _listDrag || !identical(drag.page, _page)) return;
    _stopListScroll();
    final viewport = _listViewportBox;
    final start = viewport == null || MediaQuery.disableAnimationsOf(context)
        ? null
        : _listBounds(_listFeedback, relativeTo: viewport);
    if (start != null) {
      _listMotion.reset();
      setState(() {
        _listLanding = _ListLanding(drag, start);
        if (target != null) {
          _listOrigins = {
            for (final entry in _listItems.entries)
              if (entry.key != drag.identity)
                if (_listBounds(entry.value) case final bounds?)
                  entry.key: bounds.topLeft,
          };
        }
      });
      _listMotion.forward();
    }
    if (target == null) return;
    _setSections(drag.moveTo(target));
    if (drag.question case final question?) {
      setState(() => _selectedControl = question.field);
    }
  }

  double get _listProgress => Curves.easeOutCubic.transform(_listMotion.value);

  Widget _listMotionItem(Object identity, Widget child) {
    final key = _listItems.putIfAbsent(identity, GlobalKey.new);
    return KeyedSubtree(
      key: key,
      child: _listLanding == null
          ? child
          : AnimatedBuilder(
              animation: _listMotion,
              child: child,
              builder: (context, child) {
                final progress = _listProgress;
                if (_listLanding?.drag.identity == identity) {
                  return Opacity(
                    opacity: ((progress - .85) / .15).clamp(0.0, 1.0),
                    child: child,
                  );
                }
                return _ListReflow(
                  from: _listOrigins[identity],
                  progress: progress,
                  child: child!,
                );
              },
            ),
    );
  }

  Widget _listFlight(_ListLanding landing) => AnimatedBuilder(
    animation: _listMotion,
    builder: (context, child) {
      final progress = _listProgress;
      final viewport = _listViewportBox;
      final destination = viewport == null
          ? null
          : _listBounds(
              _listItems[landing.drag.identity],
              relativeTo: viewport,
            );
      final visible =
          viewport != null &&
          destination != null &&
          (Offset.zero & viewport.size).overlaps(destination);
      final rect = visible
          ? Rect.lerp(landing.start, destination, progress)!
          : landing.start;
      return Positioned.fromRect(
        key: const ValueKey('form-list-landing-card'),
        rect: rect,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: Opacity(
              opacity: visible
                  ? 1 - ((progress - .85) / .15).clamp(0.0, 1.0)
                  : 1 - progress,
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox.fromSize(
                  size: landing.start.size,
                  child: _listDragCard(
                    landing.drag,
                    elevation: 12 * (1 - progress),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _listGap(GamePackSection section, int item, {int? control}) {
    final position = (section: section, item: item, control: control);
    return SizedBox(
      key: _listDrag == null
          ? null
          : _listGaps.putIfAbsent(position, GlobalKey.new),
      height: 4,
      child: ValueListenableBuilder(
        key: ValueKey(('form-list-gap', section.id, item, control)),
        valueListenable: _listHover,
        builder: (context, hover, _) => Center(
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 120),
            height: 2,
            decoration: BoxDecoration(
              color: hover == position
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }

  Widget _listGrip(String label) => Tooltip(
    message: 'Drag $label',
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Icon(
        LucideIcons.gripVertical,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _listDragCard(_ListDrag drag, {Key? key, required double elevation}) =>
      Material(
        key: key,
        animationDuration: Duration.zero,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        elevation: elevation,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          dense: true,
          leading: const Icon(LucideIcons.gripVertical),
          title: Text(drag.label, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: drag.subtitle == null ? null : Text(drag.subtitle!),
        ),
      );

  Widget _draggableListItem(
    _ListDrag drag, {
    required double width,
    required Widget child,
  }) => _listMotionItem(
    drag.identity,
    MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: EditorDraggable<_ListDrag>(
        data: drag,
        dragAnchorStrategy: (draggable, context, pointer) =>
            drag.anchor = childDragAnchorStrategy(draggable, context, pointer),
        canStart: () => _listDrag == null && _listLanding == null,
        onDragStarted: () => _startListDrag(drag),
        onDragCompleted: _finishListDrag,
        onDraggableCanceled: (_, _) {
          if (_listDrag case final active?) _landListDrag(active);
          _finishListDrag();
        },
        childWhenDragging: child,
        feedback: SizedBox(
          width: width,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            builder: (context, lift, _) => Transform.scale(
              scale: 1 + .025 * lift,
              child: _listDragCard(
                drag,
                key: _listFeedback,
                elevation: 12 * lift,
              ),
            ),
          ),
        ),
        child: child,
      ),
    ),
  );

  Widget _list(GamePackFormPage page) => LayoutBuilder(
    builder: (context, bounds) => DragTarget<_ListDrag>(
      key: _listViewport,
      onWillAcceptWithDetails: (details) => identical(details.data.page, page),
      onMove: (details) => _trackListDrag(details.offset + details.data.anchor),
      onLeave: (_) => _leaveListDropArea(),
      onAcceptWithDetails: (details) => _landListDrag(
        details.data,
        target: _listDropAt(details.offset + details.data.anchor),
      ),
      builder: (context, _, _) => Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            ignoring: _listLanding != null,
            child: SingleChildScrollView(
              controller: _listScroll,
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, section) in page.sections.indexed) ...[
                    _listMotionItem(
                      (section.id, 'title'),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              section.label,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          BearingsPopupMenu.overflow(
                            tooltip: 'Section options for ${section.label}',
                            menuChildren: _sectionActions(page, index),
                          ),
                        ],
                      ),
                    ),
                    for (var i = 0; i < section.items.length; i++) ...[
                      _listGap(section, i),
                      _listItem(page, section, i, bounds.maxWidth),
                    ],
                    _listGap(section, section.items.length),
                    _listMotionItem(
                      (section.id, 'footer'),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              _addQuestionButton(
                                () => _addListQuestion(section),
                              ),
                              TextButton.icon(
                                onPressed: () => _setItems(section, [
                                  ...section.items,
                                  GamePackListItem.row([]),
                                ]),
                                icon: const Icon(LucideIcons.columns2),
                                label: const Text('Add row'),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                        ],
                      ),
                    ),
                  ],
                  if (page.sections.isEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No questions on this page'),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _addQuestionButton(_addListQuestion),
                    ),
                    const Divider(height: 24),
                  ],
                  Align(
                    alignment: Alignment.center,
                    child: TextButton.icon(
                      onPressed: _editSection,
                      icon: const Icon(LucideIcons.plus),
                      label: const Text('Add section'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_listLanding case final landing?) _listFlight(landing),
        ],
      ),
    ),
  );

  List<Widget> _itemActions(
    GamePackFormPage page,
    GamePackSection section,
    int index,
  ) => [
    if (index > 0)
      BearingsMenuItem(
        onPressed: () =>
            _setItems(section, _reordered(section.items, index, index - 1)),
        child: const Text('Move up'),
      ),
    if (index < section.items.length - 1)
      BearingsMenuItem(
        onPressed: () =>
            _setItems(section, _reordered(section.items, index, index + 1)),
        child: const Text('Move down'),
      ),
    if (page.sections.length > 1)
      BearingsMenuItem(
        onPressed: () => _moveItemToSection(section, index),
        child: const Text('Move to section'),
      ),
  ];

  Widget _listItem(
    GamePackFormPage page,
    GamePackSection section,
    int index,
    double width,
  ) {
    final item = section.items[index];
    final colors = Theme.of(context).colorScheme;
    _ControlSlot slot(int i) => (section: section.id, item: index, index: i);
    final itemActions = _itemActions(page, section, index);
    Widget question(int i, {bool inRow = false}) {
      final field = _fields[item.controls[i].field]!;
      final position = (section: section, item: index, control: i);
      return _draggableListItem(
        _ListDrag(
          page,
          position,
          label: field.label,
          subtitle: GamePackAnswerKind.forQuestion(field).label,
        ),
        width: inRow ? math.max(0, width - 25) : width,
        child: _questionRow(
          field,
          slot(i),
          leading: _listGrip(field.label),
          dragging:
              _listDrag?.from == position ||
              _listDrag?.from == (section: section, item: index, control: null),
          options: inRow
              ? [
                  if (i > 0)
                    BearingsMenuItem(
                      onPressed: () =>
                          _moveRowControl(section, index, i, i - 1),
                      child: const Text('Move earlier in row'),
                    ),
                  if (i < item.controls.length - 1)
                    BearingsMenuItem(
                      onPressed: () =>
                          _moveRowControl(section, index, i, i + 1),
                      child: const Text('Move later in row'),
                    ),
                ]
              : itemActions,
        ),
      );
    }

    return Column(
      key: ObjectKey(item),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!item.isRow)
          question(0)
        else ...[
          _draggableListItem(
            _ListDrag(
              page,
              (section: section, item: index, control: null),
              label: 'Shared row',
              subtitle: item.controls
                  .map((control) => _fields[control.field]!.label)
                  .join(' · '),
            ),
            width: width,
            child: Row(
              children: [
                _listGrip('Shared row'),
                Expanded(
                  child: Text(
                    'Shared row',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
                if (item.controls.length < GamePackListItem.maxRowControls)
                  Tooltip(
                    message: 'Add question to row',
                    child: IconButton(
                      onPressed: () => _editControl(slot(item.controls.length)),
                      icon: const Icon(LucideIcons.plus),
                    ),
                  ),
                BearingsPopupMenu.overflow(
                  tooltip: 'Row options',
                  menuChildren: [
                    ...itemActions,
                    BearingsMenuItem(
                      onPressed: () => _setItems(
                        section,
                        [...section.items]..removeAt(index),
                        removing: 'row',
                      ),
                      destructive: true,
                      child: const Text('Remove row'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 15),
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: colors.outlineVariant, width: 2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < item.controls.length; i++) ...[
                  _listGap(section, index, control: i),
                  question(i, inRow: true),
                ],
                _listGap(section, index, control: item.controls.length),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _questionRow(
    GamePackField field,
    _ControlSlot slot, {
    Widget? leading,
    required bool dragging,
    List<Widget> options = const [],
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = _selectedControl == field.id;
    final kind = GamePackAnswerKind.forQuestion(field);
    const radius = BorderRadius.all(Radius.circular(10));
    return AnimatedOpacity(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 140),
      opacity: dragging ? .4 : 1,
      child: Material(
        key: selected ? _selectionAnchor : null,
        color: selected ? colors.primaryContainer : Colors.transparent,
        borderRadius: radius,
        child: Row(
          children: [
            ?leading,
            Expanded(
              child: Semantics(
                selected: selected,
                child: InkWell(
                  borderRadius: radius,
                  onTap: () => setState(() => _selectedControl = field.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 9,
                    ),
                    child: Row(
                      spacing: 10,
                      children: [
                        Icon(kind.icon, color: colors.onSurfaceVariant),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                field.label,
                                style: theme.textTheme.bodyMedium,
                              ),
                              Text(
                                kind.label,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (selected) _questionActions(slot, field, options),
          ],
        ),
      ),
    );
  }

  Future<void> _findQuestion() async {
    final match =
        await BearingsModal.show<({String form, String page, String field})>(
          context,
          builder: (_) => _FindQuestion(design: widget.design),
        );
    if (!mounted || match == null) return;
    widget.formSelection.value = match.form;
    setState(() {
      _pageId = match.page;
      _selectedControl = match.field;
    });
    _revealSelection(center: true);
    final page = _page;
    if (page.usesGrid) return;
    for (final section in page.sections) {
      for (final (item, row) in section.items.indexed) {
        final index = row.controls.indexWhere(
          (control) => control.field == match.field,
        );
        if (index >= 0) {
          await _editControl((section: section.id, item: item, index: index));
          return;
        }
      }
    }
  }

  Widget _pagePicker(GamePackForm form, GamePackFormPage page) =>
      BearingsPopupMenu.button(
        label: page.label,
        tooltip: 'Switch page',
        icon: widget.compact ? null : LucideIcons.layers,
        menuChildren: [
          BearingsMenuItem(
            onPressed: _editPage,
            leadingIcon: Icon(LucideIcons.plus),
            child: const Text('Add page'),
          ),
          const Divider(height: 8),
          for (final item in form.pages)
            BearingsMenuItem(
              selected: item.id == page.id,
              leadingIcon: Icon(null),
              onPressed: () => setState(() {
                _pageId = item.id;
                _selectedControl = null;
              }),
              child: Text(item.label),
            ),
          if (widget.compact) const Divider(height: 8),
          if (widget.compact) ..._pageActions(form, page),
        ],
      );

  Widget _pageOptions(GamePackForm form, GamePackFormPage page) {
    const icon = Icon(LucideIcons.settings2);
    if (form.pages.length == 1) {
      return IconButton(
        icon: icon,
        tooltip: 'Page settings',
        onPressed: () => _editPage(page),
      );
    }
    return BearingsPopupMenu.icon(
      icon: icon,
      tooltip: 'Page options',
      menuChildren: _pageActions(form, page),
    );
  }

  List<Widget> _pageActions(GamePackForm form, GamePackFormPage page) {
    final index = form.pages.indexOf(page);
    return [
      BearingsMenuItem(
        onPressed: () => _editPage(page),
        leadingIcon: const Icon(LucideIcons.settings2),
        child: const Text('Page settings'),
      ),
      if (form.pages.length > 1) ...[
        BearingsMenuItem(
          onPressed: index > 0
              ? () => _setPages(_reordered(form.pages, index, index - 1))
              : null,
          leadingIcon: const Icon(LucideIcons.chevronUp),
          child: const Text('Move page earlier'),
        ),
        BearingsMenuItem(
          onPressed: index < form.pages.length - 1
              ? () => _setPages(_reordered(form.pages, index, index + 1))
              : null,
          leadingIcon: const Icon(LucideIcons.chevronDown),
          child: const Text('Move page later'),
        ),
        BearingsMenuItem(
          onPressed: () =>
              _setPages([...form.pages]..removeAt(index), removing: page.label),
          leadingIcon: const Icon(LucideIcons.trash2),
          destructive: true,
          child: const Text('Remove page'),
        ),
      ],
    ];
  }

  Widget _header(GamePackForm form, GamePackFormPage page) {
    final title = Text(
      form.label,
      maxLines: widget.compact ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleLarge,
    );
    final picker = _pagePicker(form, page);
    final canSearch = widget.design.questions.isNotEmpty;
    final search = IconButton(
      onPressed: canSearch ? _findQuestion : null,
      icon: const Icon(LucideIcons.search),
      tooltip: 'Find a question',
    );
    final preview = form.controls.isEmpty ? null : () => _preview(form, page);
    if (widget.compact) {
      const titleSpacing = 12.0;
      const minPagePickerWidth = 80.0;
      return Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, bounds) => Row(
                spacing: titleSpacing,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth:
                          (bounds.maxWidth - titleSpacing - minPagePickerWidth)
                              .clamp(0.0, bounds.maxWidth),
                    ),
                    child: title,
                  ),
                  Flexible(child: picker),
                ],
              ),
            ),
          ),
          search,
          Tooltip(
            message: 'Preview',
            child: IconButton(
              onPressed: preview,
              icon: const Icon(LucideIcons.eye),
            ),
          ),
        ],
      );
    }

    return Row(
      spacing: 8,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, bounds) => Row(
              children: [
                title,
                const SizedBox(width: 12),
                Flexible(child: picker),
                const SizedBox(width: 4),
                _pageOptions(form, page),
                search,
              ],
            ),
          ),
        ),
        if (page.usesGrid)
          _addQuestionButton(
            () => _editControl((
              section: null,
              item: 0,
              index: page.gridControls.length,
            )),
          ),
        OutlinedButton.icon(
          onPressed: preview,
          icon: const Icon(LucideIcons.eye),
          label: const Text('Preview'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final form = _form;
    final page = _page;
    final gutter = widget.compact ? 16.0 : 24.0;
    return CallbackShortcuts(
      bindings: {
        if (_selectedControl != null)
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              setState(() => _selectedControl = null),
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(form, page),
            const SizedBox(height: 8),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey((form.id, page.id)),
                child: page.usesGrid
                    ? _grid(page)
                    : Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 760 - 2 * gutter,
                          ),
                          child: SizedBox.expand(child: _list(page)),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionActions extends StatelessWidget {
  const _QuestionActions({
    required this.label,
    required this.onEdit,
    required this.onRemove,
    required this.options,
  });

  final String label;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final List<Widget> options;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GamePackEditorActionBar(
      children: [
        IconButton(
          tooltip: 'Edit question',
          onPressed: onEdit,
          icon: const Icon(LucideIcons.pencil),
        ),
        IconButton(
          tooltip: 'Remove question',
          onPressed: onRemove,
          color: colors.error,
          icon: const Icon(LucideIcons.trash2),
        ),
        if (options.isNotEmpty)
          BearingsPopupMenu.overflow(
            tooltip: 'Options for $label',
            menuChildren: options,
          ),
      ],
    );
  }
}

class _FindQuestion extends StatefulWidget {
  const _FindQuestion({required this.design});

  final GamePackDesign design;

  @override
  State<_FindQuestion> createState() => _FindQuestionState();
}

class _FindQuestionState extends State<_FindQuestion> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final matches = widget.design.questions
        .where(
          (question) => matchesGamePackSearch(
            '${question.form.label} ${question.page.label} ${question.field.label} ${question.field.id}',
            _query,
          ),
        )
        .toList();
    return BearingsModal(
      title: 'Find a question',
      actions: const [],
      size: BearingsModalSize.tall,
      scrolling: BearingsModalScrolling.content,
      content: SizedBox(
        height: 350,
        child: Column(
          spacing: 8,
          children: [
            TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                labelText: 'Search by question, page or form',
                prefixIcon: Icon(LucideIcons.search),
              ),
            ),
            Expanded(
              child: matches.isEmpty
                  ? const Center(child: Text('No matching questions.'))
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final item = matches[index];
                        final kind = GamePackAnswerKind.forQuestion(item.field);
                        return ListTile(
                          leading: Icon(kind.icon),
                          title: Text(
                            '${item.page.label} › ${item.field.label}',
                          ),
                          subtitle: Text('${item.form.label} · ${kind.label}'),
                          onTap: () => BearingsModal.complete(context, (
                            form: item.form.id,
                            page: item.page.id,
                            field: item.field.id,
                          )),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoutFormPreview extends StatefulWidget {
  const _ScoutFormPreview({
    required this.fields,
    required this.form,
    required this.page,
  });

  final Map<String, GamePackField> fields;
  final GamePackForm form;
  final GamePackFormPage page;

  @override
  State<_ScoutFormPreview> createState() => _ScoutFormPreviewState();
}

class _ScoutFormPreviewState extends State<_ScoutFormPreview> {
  late var _answers = widget.form.defaults(
    widget.fields,
    roster: const ['frc2046', 'frc254', 'frc1678'],
  );
  @override
  Widget build(BuildContext context) {
    final tablet = widget.form.pages.any((page) => page.usesGrid);
    final theme = Theme.of(context);
    final form = GamePackFormView(
      fields: widget.fields,
      form: widget.form,
      initialPage: widget.form.pages.indexOf(widget.page),
      answers: _answers,
      onChanged: (answers) => setState(() => _answers = answers),
    );
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to editing',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(LucideIcons.arrowLeft),
        ),
        title: Text(
          widget.form.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: tablet
              ? Card.filled(
                  color: theme.colorScheme.surface,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: form,
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Material(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: form,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

List<T> _reordered<T>(List<T> list, int from, int to) {
  final result = [...list];
  result.insert(to, result.removeAt(from));
  return result;
}

class _NameModal extends StatefulWidget {
  const _NameModal({required this.label, required this.initial});

  final String label;
  final String initial;

  @override
  State<_NameModal> createState() => _NameModalState();
}

class _NameModalState extends State<_NameModal> {
  late String _name = widget.initial;
  String? _error;

  void _save() {
    try {
      validateGamePackLabel(_name);
      BearingsModal.complete(context, _name.trim());
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => BearingsModal(
    title: widget.label,
    actions: const [],
    primaryAction: BearingsModalPrimaryAction(
      label: 'Save name',
      icon: LucideIcons.check,
      onPressed: _save,
    ),
    content: TextFormField(
      autofocus: true,
      initialValue: _name,
      onChanged: (value) => _name = value,
      onFieldSubmitted: (_) => _save(),
      decoration: InputDecoration(labelText: widget.label, errorText: _error),
    ),
  );
}

class _PageModal extends StatefulWidget {
  const _PageModal({
    required this.page,
    required this.ids,
    required this.nextNumber,
    required this.initialLayout,
  });

  final GamePackFormPage? page;
  final Iterable<String> ids;
  final int nextNumber;
  final GamePackPageLayout initialLayout;

  @override
  State<_PageModal> createState() => _PageModalState();
}

class _PageModalState extends State<_PageModal> {
  late String _label = widget.page?.label ?? 'Page ${widget.nextNumber}';
  late GamePackPageLayout _layout = widget.page?.layout ?? widget.initialLayout;
  late int? _columns = widget.page?.columns ?? 6;
  late int? _rows =
      widget.page?.rows ??
      math.max(6, ((widget.page?.controls.length ?? 0) / 2).ceil() * 2);
  String? _error;

  void _save() {
    try {
      validateGamePackLabel(_label);
      final previous = widget.page;
      final label = _label.trim();
      final id = previous?.id ?? gamePackIdForName(label, widget.ids, 'page');
      if (_layout == GamePackPageLayout.scrolling) {
        final controls = [...?previous?.gridControls]
          ..sort((left, right) {
            final a = left.placement!;
            final b = right.placement!;
            final order = a.y.compareTo(b.y);
            return order == 0 ? a.x.compareTo(b.x) : order;
          });
        final page = GamePackFormPage.scrolling(
          id: id,
          label: label,
          sections: previous?.usesGrid == false
              ? previous!.sections
              : [
                  GamePackSection.controls(
                    id: 'controls',
                    label: 'Controls',
                    controls: controls
                        .map((control) => controlWithPlacement(control, null))
                        .toList(),
                  ),
                ],
        );
        BearingsModal.complete(context, page);
        return;
      }

      final columns = _columns;
      final rows = _rows;
      if (columns == null ||
          rows == null ||
          !GamePackFormPage.isGridSize(columns) ||
          !GamePackFormPage.isGridSize(rows)) {
        throw const FormatException(
          'Rows and columns must be whole numbers from 1 to 128.',
        );
      }
      final controls = <GamePackControl>[...?previous?.gridControls];
      if (previous?.usesGrid == false) {
        for (final control in previous!.controls) {
          final space = findGridPlacement(columns, rows, controls);
          if (space == null) {
            throw const FormatException(
              'Increase the grid size to fit all controls.',
            );
          }
          controls.add(controlWithPlacement(control, space));
        }
      }
      if (controls.any((control) => !control.placement!.fits(columns, rows))) {
        throw const FormatException(
          'Move the controls inside the new bounds before shrinking the grid.',
        );
      }
      BearingsModal.complete(
        context,
        GamePackFormPage.grid(
          id: id,
          label: label,
          columns: columns,
          rows: rows,
          controls: controls,
        ),
      );
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => BearingsModal(
    title: widget.page == null ? 'Add page' : 'Page settings',
    actions: const [],
    primaryAction: BearingsModalPrimaryAction(
      label: 'Save page',
      icon: LucideIcons.check,
      onPressed: _save,
    ),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        TextFormField(
          initialValue: _label,
          decoration: const InputDecoration(labelText: 'Page name'),
          onChanged: (value) => _label = value,
        ),
        SizedBox(),
        for (final layout in GamePackPageLayout.values)
          Card.outlined(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(
                layout == GamePackPageLayout.grid
                    ? LucideIcons.grid3x3
                    : LucideIcons.list,
              ),
              title: Text(layout.label),
              selected: _layout == layout,
              trailing: _layout == layout
                  ? const Icon(LucideIcons.check)
                  : null,
              onTap: () => setState(() {
                _layout = layout;
                _error = null;
              }),
            ),
          ),
        if (_layout == GamePackPageLayout.grid)
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: _columns?.toString(),
                  decoration: const InputDecoration(labelText: 'Columns'),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => _columns = int.tryParse(value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: _rows?.toString(),
                  decoration: const InputDecoration(labelText: 'Rows'),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => _rows = int.tryParse(value),
                ),
              ),
            ],
          ),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}
