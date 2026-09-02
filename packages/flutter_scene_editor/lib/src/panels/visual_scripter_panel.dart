/// The Visual Scripter dock panel: the canvas a visual script is drawn on.
///
/// Nodes are dragged around, pins are dragged between to wire them, and the
/// palette adds more. The graph being edited belongs to the selected node's
/// visual script component, and every edit is committed back through the
/// command layer so it is undoable like any other.
///
/// The canvas is one [CustomPaint] over a transformed coordinate space rather
/// than a widget per node. A graph is a hundred small boxes and several
/// hundred wires; as widgets that is a layout pass per pan, and panning is the
/// thing the canvas does most.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/visual_script.dart';
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

import '../blueprints/blueprint_file.dart';
import '../controller/editor_controller.dart';
import '../shell/editor_theme.dart';
import 'my_blueprint_panel.dart';
import 'visual_script_collapse.dart';
import 'visual_script_details.dart';
import 'visual_script_inspector.dart';
import 'visual_script_layout.dart';
import 'visual_script_palette.dart';

/// The Visual Scripter panel.
class VisualScripterPanel extends StatefulWidget {
  const VisualScripterPanel({super.key, required this.controller, this.file});

  final EditorController controller;

  /// The blueprint asset being edited, or null to edit the selected node's
  /// script.
  ///
  /// The same editor, two sources. A graph on a node belongs to that node; a
  /// blueprint in the project is a class, edited on its own and instanced
  /// many times. Which one is open changes where a commit goes and nothing
  /// else, so there is one canvas rather than two that drift apart.
  final BlueprintFile? file;

  @override
  State<VisualScripterPanel> createState() => _VisualScripterPanelState();
}

class _VisualScripterPanelState extends State<VisualScripterPanel> {
  EditorController get _ctrl => widget.controller;

  final VisualScriptRegistry _registry = sceneVisualScriptRegistry();

  /// The blueprint being edited. Held here rather than read from the document
  /// on every frame, because a drag mutates it many times per second and only
  /// the release is worth an undo step.
  Blueprint? _blueprint;
  LocalId? _graphOwner;

  /// Which of the blueprint's graphs the canvas is showing.
  ///
  /// By name rather than by reference, so a reload from the document lands on
  /// the graph that was open rather than on one that no longer exists.
  String? _openGraphName;

  /// The graph on the canvas, which every gesture below edits.
  VisualScriptGraph? get _graph {
    final blueprint = _blueprint;
    if (blueprint == null) return null;
    final open = _openGraphName;
    if (open != null) {
      final named = blueprint.graph(open);
      if (named != null) return named;
    }
    return blueprint.graphs.isEmpty ? null : blueprint.graphs.first;
  }

  /// The history position the loaded graph came from.
  ///
  /// An undo reverts the document but has no way to reach into the canvas's
  /// own copy, so the copy is dropped whenever the cursor moves somewhere it
  /// did not put it. Without this, undoing a wire leaves it on screen.
  int _graphCursor = -1;

  /// Set across a commit, so the reload check does not throw away the graph
  /// the panel just wrote.
  bool _committing = false;

  Offset _pan = const Offset(40, 40);
  double _zoom = 1;

  /// Every node picked, and the one whose details show.
  ///
  /// A set rather than a single id: a graph is edited in groups — moved,
  /// deleted, collapsed into a function — much more often than one node at a
  /// time, and the collapse depends entirely on this.
  final Set<int> _selection = {};

  /// The last node clicked, which is the one the details panel describes.
  int? _primary;

  int? get _selected => _primary;

  /// The variable whose details are showing, by name, or null.
  ///
  /// Selecting a node clears it and vice versa: the details panel shows one
  /// thing, and two selections would leave it showing the older one.
  String? _selectedVariable;

  /// Whether the canvas shows what the live graph is doing.
  ///
  /// Off by default: tracing rebuilds the run's context, which restarts the
  /// script, and it is not something to do to a scene nobody asked to debug.
  bool _tracing = false;
  int? _dragging;
  Offset _dragOffset = Offset.zero;

  /// The comment being moved, and the nodes moving with it.
  int? _movingComment;
  List<VisualScriptNodeSpec> _movingWith = const [];

  /// The comment being resized.
  int? _resizingComment;

  /// The comment whose details are showing, or null.
  int? _selectedComment;

  /// The declared event whose details are showing, by name, or null.
  String? _selectedEvent;

  /// The box being dragged out to select with, in canvas space.
  Offset? _marqueeFrom;
  Offset? _marqueeTo;

  /// Whether the current drag is panning the view rather than editing.
  bool _panning = false;

  /// Where each moving node started, so a group drag moves them together
  /// rather than snapping them all onto the pointer.
  final Map<int, Offset> _dragStart = {};

  /// Replaces the selection with [id], or clears it. Call inside setState.
  void _select(int? id) {
    _selection
      ..clear()
      ..addAll(id == null ? const <int>[] : [id]);
    _primary = id;
  }

  /// Adds or removes [id], the way a modifier-click does. Call inside
  /// setState.
  void _toggle(int id) {
    if (_selection.add(id)) {
      _primary = id;
      return;
    }
    _selection.remove(id);
    _primary = _primary == id
        ? (_selection.isEmpty ? null : _selection.last)
        : _primary;
  }

  /// The box the marquee currently covers, or null.
  Rect? get _marquee {
    final from = _marqueeFrom;
    final to = _marqueeTo;
    if (from == null || to == null) return null;
    return Rect.fromPoints(from, to);
  }

  /// The wire being drawn, if any: where it started and where the pointer is.
  VisualScriptPortRef? _wireFrom;
  Offset? _wirePointer;

  /// Set while a drag is pulling an existing wire off an input.
  ///
  /// The graph is already mutated by then, so a drag that ends nowhere still
  /// has to be committed — otherwise the wire vanishes from the canvas and
  /// comes back the next time the panel reloads.
  bool _wireDetached = false;

  bool _paletteOpen = false;

  /// Why the last wire was refused, shown until it is stale or replaced.
  String? _refusal;
  Timer? _refusalTimer;

  /// Where the palette should appear, in this panel's coordinates, or null to
  /// put it in its usual corner.
  Offset? _paletteAt;

  /// Where a node picked from the palette should land, in canvas space.
  Offset? _dropAt;

  /// The pin a palette was opened from, so whatever is picked is wired to it.
  ///
  /// This is what makes dragging a wire into empty space useful rather than a
  /// no-op: the question "what can go here" already has an answer, and the
  /// palette should be showing it.
  VisualScriptPortRef? _wireInto;
  VisualScriptType? _wireIntoType;

  @override
  void initState() {
    super.initState();
    _ctrl.selection.addListener(_onSelectionChanged);
    _ctrl.history.addListener(_onSelectionChanged);
    _ctrl.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _refusalTimer?.cancel();
    _ctrl.selection.removeListener(_onSelectionChanged);
    _ctrl.history.removeListener(_onSelectionChanged);
    _ctrl.removeListener(_onSelectionChanged);
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    // A file-backed blueprint is not the selection's, so moving the selection
    // must not throw away what is open.
    if (widget.file != null) {
      setState(() {});
      return;
    }
    final id = _ctrl.selection.primary;
    final cursor = _ctrl.history.cursor;
    final movedElsewhere =
        !_committing && _blueprint != null && cursor != _graphCursor;
    if (id != _graphOwner || movedElsewhere) {
      setState(() {
        _blueprint = null;
        // The open graph is remembered across a reload of the same node, and
        // dropped when the selection moves to a different one.
        if (id != _graphOwner) {
          _openGraphName = null;
          _select(null);
        }
        _graphOwner = id;
        _graphCursor = cursor;
      });
      return;
    }
    setState(() {});
  }

  /// The selected node's visual script component spec, or null.
  ComponentSpecView? get _componentView {
    final id = _ctrl.selection.primary;
    if (id == null) return null;
    final node = _ctrl.document.node(id);
    if (node == null) return null;
    for (final component in node.components) {
      if (component.type == visualScriptComponentType) {
        return (nodeId: id, spec: component);
      }
    }
    return null;
  }

  /// The live component the selected node realized, or null when the scene
  /// has not been realized or the selection carries no graph.
  ///
  /// The document holds the script; this is the thing actually running it,
  /// and the only place a trace can come from.
  VisualScriptComponent? get _liveComponent {
    final view = _componentView;
    if (view == null) return null;
    return _ctrl.liveNode(view.nodeId)?.getComponent<VisualScriptComponent>();
  }

  void _toggleTracing() {
    setState(() => _tracing = !_tracing);
    // Turning it on restarts the script, because the trace is fixed to a run
    // at construction -- which is what keeps the runtime's hot path a null
    // check rather than a flag test per node.
    _liveComponent?.tracing = _tracing;
  }

  /// Loads the blueprint from the document, once per selection.
  Blueprint? _ensureBlueprint() {
    final existing = _blueprint;
    if (existing != null) return existing;
    final file = widget.file;
    if (file != null) {
      final loaded = file.read();
      // A file that failed to parse shows nothing rather than a blank canvas:
      // a blank canvas is how you save over your own work.
      if (loaded == null) return null;
      if (loaded.graphs.isEmpty) {
        loaded.addGraph(
          VisualScriptGraph(),
          kind: VisualScriptGraphKind.eventGraph,
          name: defaultEventGraphName,
        );
      }
      return _blueprint = loaded;
    }
    final view = _componentView;
    if (view == null) return null;
    final source = view.spec.properties['graph'];
    final loaded = source is StringValue && source.value.isNotEmpty
        ? _tryRead(source.value)
        : Blueprint.of(VisualScriptGraph());
    // A blueprint with nothing in it still needs somewhere to draw.
    if (loaded.graphs.isEmpty) {
      loaded.addGraph(
        VisualScriptGraph(),
        kind: VisualScriptGraphKind.eventGraph,
        name: defaultEventGraphName,
      );
    }
    _blueprint = loaded;
    _graphCursor = _ctrl.history.cursor;
    return loaded;
  }

  Blueprint _tryRead(String source) {
    try {
      return readBlueprint(source);
    } on FormatException {
      return Blueprint.of(VisualScriptGraph());
    }
  }

  /// Writes the graph back to the document as one undoable edit.
  Future<void> _commit() async {
    final blueprint = _blueprint;
    if (blueprint == null) return;
    final file = widget.file;
    if (file != null) {
      // Straight to disk. A blueprint asset is not part of the scene
      // document, so the scene's undo stack is the wrong place for it -- an
      // undo in the level should not silently rewrite a class.
      await file.write(blueprint);
      return;
    }
    final view = _componentView;
    if (view == null) return;
    _committing = true;
    try {
      await _ctrl.run('setComponentProperties', {
        'nodeId': view.nodeId.toToken(),
        'componentType': visualScriptComponentType,
        'properties': {'graph': StringValue(writeBlueprint(blueprint))},
      });
    } finally {
      _committing = false;
      _graphCursor = _ctrl.history.cursor;
    }
  }

  Future<void> _addFlowComponent() async {
    final id = _ctrl.selection.primary;
    if (id == null) return;
    await _ctrl.run('addComponent', {
      'nodeId': id.toToken(),
      'componentType': visualScriptComponentType,
    });
    setState(() => _blueprint = null);
  }

  // --- canvas geometry -----------------------------------------------------

  Offset _toCanvas(Offset screen) => (screen - _pan) / _zoom;

  VisualScriptLayout _layout(VisualScriptGraph graph) =>
      VisualScriptLayout(graph, _registry, graphs: _blueprint?.graph);

  // --- interaction ---------------------------------------------------------

  void _onPointerDown(PointerDownEvent event, VisualScriptGraph graph) {
    final at = _toCanvas(event.localPosition);
    final layout = _layout(graph);

    // Right-drag pans and right-click adds, which is the arrangement every
    // graph editor of this shape uses. Which of the two it was is only known
    // on release, so the decision waits there.
    if (event.buttons == kSecondaryButton) {
      setState(() {
        _panning = true;
        _marqueeFrom = event.localPosition;
        _marqueeTo = null;
      });
      return;
    }

    final port = layout.portAt(at);
    if (port != null) {
      // Grabbing a connected input pulls the wire off it, which is how one is
      // rerouted rather than deleted and drawn again.
      final existing = port.isInput ? graph.inputTo(port.node, port.pin) : null;
      if (existing != null) {
        graph.disconnect(existing);
        setState(() {
          _wireDetached = true;
          _wireFrom = (
            node: existing.fromNode,
            pin: existing.fromPin,
            isInput: false,
          );
          _wirePointer = at;
        });
        return;
      }
      setState(() {
        _refusal = null;
        _wireFrom = port;
        _wirePointer = at;
      });
      return;
    }

    final grip = layout.commentGripAt(at);
    if (grip != null) {
      setState(() {
        _resizingComment = grip;
        _dragOffset = at;
      });
      return;
    }
    final header = layout.commentHeaderAt(at);
    if (header != null) {
      final comment = graph.comment(header)!;
      setState(() {
        _select(null);
        _selectedVariable = null;
        _selectedEvent = null;
        _selectedComment = header;
        _movingComment = header;
        // Captured on grab rather than recomputed as it moves: a node that
        // leaves the box mid-drag should keep moving with it, not be dropped
        // the moment it crosses the edge.
        _movingWith = layout.nodesInside(comment);
        _dragOffset = at - Offset(comment.position.x, comment.position.y);
      });
      return;
    }

    final node = layout.nodeAt(at);
    if (node != null) {
      final spec = graph.node(node)!;
      final extending =
          HardwareKeyboard.instance.isShiftPressed ||
          HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed;
      setState(() {
        if (extending) {
          _toggle(node);
        } else if (!_selection.contains(node)) {
          // Clicking inside an existing selection keeps it, so a group can be
          // dragged by any of its members.
          _select(node);
        } else {
          _primary = node;
        }
        _dragStart
          ..clear()
          ..addEntries([
            for (final id in _selection)
              if (graph.node(id) case final moving?)
                MapEntry(id, Offset(moving.position.x, moving.position.y)),
          ]);
        _selectedVariable = null;
        _selectedEvent = null;
        _selectedComment = null;
        _dragging = node;
        _dragOffset = at - Offset(spec.position.x, spec.position.y);
      });
      return;
    }
    // Empty canvas: start a marquee. Extending keeps what was already picked.
    setState(() {
      _marqueeFrom = at;
      _marqueeTo = at;
      if (!HardwareKeyboard.instance.isShiftPressed) _select(null);
      _selectedVariable = null;
      _selectedEvent = null;
      _selectedComment = null;
    });
  }

  void _onPointerMove(PointerMoveEvent event, VisualScriptGraph graph) {
    final at = _toCanvas(event.localPosition);
    if (_panning) {
      setState(() {
        _pan += event.delta;
        _marqueeTo = event.localPosition;
      });
      return;
    }
    if (_marqueeFrom != null) {
      setState(() => _marqueeTo = at);
      return;
    }
    if (_wireFrom != null) {
      setState(() => _wirePointer = at);
      return;
    }
    final moving = _movingComment;
    if (moving != null) {
      final comment = graph.comment(moving);
      if (comment == null) return;
      final to = at - _dragOffset;
      final by = to - Offset(comment.position.x, comment.position.y);
      setState(() {
        comment.position.setValues(to.dx, to.dy);
        for (final node in _movingWith) {
          node.position.setValues(
            node.position.x + by.dx,
            node.position.y + by.dy,
          );
        }
      });
      return;
    }
    final resizing = _resizingComment;
    if (resizing != null) {
      final comment = graph.comment(resizing);
      if (comment == null) return;
      setState(() {
        // A floor, so a comment cannot be shrunk to something with no header
        // left to grab.
        comment.size.setValues(
          math.max(80, at.dx - comment.position.x),
          math.max(
            visualScriptCommentHeaderHeight + 20,
            at.dy - comment.position.y,
          ),
        );
      });
      return;
    }
    final dragging = _dragging;
    if (dragging != null) {
      final anchor = _dragStart[dragging];
      if (anchor == null) return;
      final moved = at - _dragOffset;
      final by = moved - anchor;
      // Every selected node moves by the same offset from where it started,
      // rather than each chasing the pointer.
      setState(() {
        for (final entry in _dragStart.entries) {
          graph
              .node(entry.key)
              ?.position
              .setValues(entry.value.dx + by.dx, entry.value.dy + by.dy);
        }
      });
      return;
    }
  }

  Future<void> _onPointerUp(
    PointerUpEvent event,
    VisualScriptGraph graph,
  ) async {
    if (_panning) {
      final from = _marqueeFrom;
      final travelled = from == null
          ? 0.0
          : (event.localPosition - from).distance;
      setState(() {
        _panning = false;
        _marqueeFrom = null;
        _marqueeTo = null;
        // A right-click that did not travel is a click, and a click on empty
        // canvas is "add something here".
        if (travelled < 4) {
          final at = _toCanvas(event.localPosition);
          if (_layout(graph).nodeAt(at) == null) {
            _openPalette(at: event.localPosition, drop: at);
          }
        }
      });
      return;
    }
    if (_marqueeFrom != null && _dragging == null && _wireFrom == null) {
      final box = _marquee;
      setState(() {
        if (box != null) {
          for (final id in _layout(graph).nodesTouching(box)) {
            _selection.add(id);
            _primary = id;
          }
        }
        _marqueeFrom = null;
        _marqueeTo = null;
      });
      return;
    }
    final from = _wireFrom;
    if (from != null) {
      final at = _toCanvas(event.localPosition);
      final layout = _layout(graph);
      // The nearest pin that would actually take this wire, rather than
      // whatever happens to be under the pointer. Letting go near the right
      // pin lands on it, and letting go on a pin that would be refused does
      // not quietly snap to a neighbour instead.
      final target = layout.nearestAcceptingPort(at, from);
      final detached = _wireDetached;
      setState(() {
        _wireFrom = null;
        _wirePointer = null;
        _wireDetached = false;
      });
      if (target == null) {
        // Nothing took it. If the pointer is over a node, say why rather than
        // doing nothing: a refusal that looks like a missed click teaches the
        // wrong lesson.
        final under = layout.portAt(at);
        final fromType = layout.typeOf(from);
        if (under != null && fromType != null) {
          final underType = layout.typeOf(under);
          if (underType != null) {
            _refuse(
              layout.refuseWire(from, fromType, under, underType) ??
                  'That wire cannot go there.',
            );
            if (detached) await _commit();
            return;
          }
        }
        if (layout.nodeAt(at) != null) {
          _refuse('Nothing on that node takes a ${fromType?.label ?? 'wire'}.');
          if (detached) await _commit();
          return;
        }
      }
      if (target == null) {
        // Dropped on empty canvas. Offer what could go there, filtered to
        // what this pin can actually reach.
        setState(() {
          _openPalette(
            at: event.localPosition,
            drop: at,
            into: from,
            intoType: _typeOf(graph, from),
          );
        });
        // A wire pulled off an input and dropped nowhere is a disconnection,
        // and the graph already has it.
        if (detached) await _commit();
        return;
      }
      final output = from.isInput ? target : from;
      final input = from.isInput ? from : target;
      graph.connect(
        VisualScriptLink(
          fromNode: output.node,
          fromPin: output.pin,
          toNode: input.node,
          toPin: input.pin,
        ),
        // Only exec outputs are singular; a value feeds as many inputs as
        // want it.
        execOutputIsSingular: layout.typeOf(output) == VisualScriptType.exec,
      );
      await _commit();
      return;
    }
    if (_movingComment != null || _resizingComment != null) {
      setState(() {
        _movingComment = null;
        _resizingComment = null;
        _movingWith = const [];
      });
      await _commit();
      return;
    }
    if (_dragging != null) {
      setState(() {
        _dragging = null;
        _dragStart.clear();
      });
      await _commit();
    }
  }

  /// Opens the palette, optionally filtered to what [into] can connect to.
  ///
  /// Call inside a setState: it only assigns.
  void _openPalette({
    Offset? at,
    Offset? drop,
    VisualScriptPortRef? into,
    VisualScriptType? intoType,
  }) {
    _paletteOpen = true;
    _paletteAt = at;
    _dropAt = drop;
    _wireInto = into;
    _wireIntoType = intoType;
  }

  void _closePalette() {
    _paletteOpen = false;
    _paletteAt = null;
    _dropAt = null;
    _wireInto = null;
    _wireIntoType = null;
  }

  VisualScriptType? _typeOf(
    VisualScriptGraph graph,
    VisualScriptPortRef port,
  ) => _layout(graph).typeOf(port);

  /// Says why a wire was refused, for a few seconds.
  void _refuse(String reason) {
    _refusalTimer?.cancel();
    setState(() => _refusal = reason);
    _refusalTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _refusal = null);
    });
  }

  /// Writes a value into the selected node and commits it.
  ///
  /// A null clears the key rather than storing null, so the pin goes back to
  /// its own default — which is a different thing from being set to nothing.
  Future<void> _setLiteral(
    VisualScriptGraph graph,
    String key,
    Object? value,
  ) async {
    final selected = _selected;
    if (selected == null) return;
    final node = graph.node(selected);
    if (node == null) return;
    setState(() {
      if (value == null) {
        node.literals.remove(key);
      } else {
        node.literals[key] = value;
      }
    });
    await _commit();
  }

  /// Puts [next] in place of the variable of the same name.
  ///
  /// The name is the identity here, because that is what a Get and a Set node
  /// hold; everything else about a variable is editable in place.
  Widget _buildCommentDetails(VisualScriptGraph graph) {
    final comment = graph.comment(_selectedComment!);
    if (comment == null) return const SizedBox.shrink();
    return VisualScriptCommentDetails(
      comment: comment,
      onChanged: () => unawaited(_commit()),
      onDelete: () {
        setState(() {
          graph.comments.remove(comment);
          _selectedComment = null;
        });
        unawaited(_commit());
      },
    );
  }

  Widget _buildEventDetails(Blueprint blueprint) {
    final event = blueprint.event(_selectedEvent!);
    if (event == null) return const SizedBox.shrink();
    return VisualScriptEventDetails(
      event: event,
      onChanged: () => unawaited(_commit()),
    );
  }

  /// Declares a new event, under a name nothing else here has.
  Future<void> _addEvent(Blueprint blueprint) async {
    final taken = {for (final event in blueprint.events) event.name};
    var name = 'New Event';
    for (var i = 2; taken.contains(name); i++) {
      name = 'New Event $i';
    }
    final event = VisualScriptEventSpec(name: name);
    setState(() {
      blueprint.events.add(event);
      _select(null);
      _selectedEvent = name;
    });
    await _commit();
  }

  /// Renames an event, and every node at either end of it.
  ///
  /// The nodes hold the name as a literal, so renaming only the declaration
  /// would leave a Call raising something nothing listens for — and an event
  /// nobody hears is not an error, so nothing would say so.
  Future<void> _renameEvent(
    Blueprint blueprint,
    VisualScriptEventSpec event,
    String name,
  ) async {
    final wanted = name.trim();
    if (wanted.isEmpty || wanted == event.name) return;
    if (blueprint.events.any((other) => other.name == wanted)) return;
    final index = blueprint.events.indexOf(event);
    if (index < 0) return;
    setState(() {
      blueprint.events[index] = VisualScriptEventSpec(
        name: wanted,
        parameters: event.parameters,
      );
      for (final graph in blueprint.graphs) {
        for (final node in graph.nodes) {
          if (node.literals[namedEventKey] == event.name) {
            node.literals[namedEventKey] = wanted;
          }
        }
      }
      _selectedEvent = wanted;
    });
    await _commit();
  }

  Future<void> _deleteEvent(
    Blueprint blueprint,
    VisualScriptEventSpec event,
  ) async {
    setState(() {
      blueprint.events.remove(event);
      if (_selectedEvent == event.name) _selectedEvent = null;
    });
    await _commit();
  }

  /// What was last copied, so it survives switching graphs and blueprints.
  ///
  /// Held as a graph rather than as a list of nodes, because the wires
  /// between the copied nodes are half of what was copied.
  static VisualScriptGraph? _clipboard;

  /// The selection as a standalone graph: the nodes, and the wires that run
  /// between two of them.
  ///
  /// A wire with one end outside the selection is dropped rather than kept
  /// dangling — it belonged to the graph, not to the piece being lifted out.
  VisualScriptGraph _lift(VisualScriptGraph graph) {
    final lifted = VisualScriptGraph();
    for (final id in _selection) {
      final node = graph.node(id);
      if (node == null) continue;
      lifted.nodes.add(
        VisualScriptNodeSpec(
          id: node.id,
          type: node.type,
          position: node.position.clone(),
          literals: Map.of(node.literals),
        ),
      );
    }
    for (final link in graph.links) {
      if (_selection.contains(link.fromNode) &&
          _selection.contains(link.toNode)) {
        lifted.links.add(link);
      }
    }
    return lifted;
  }

  /// Copies [source] into [graph] with fresh ids, and selects what landed.
  Future<void> _paste(
    VisualScriptGraph graph,
    VisualScriptGraph source, {
    Offset offset = const Offset(24, 24),
  }) async {
    if (source.nodes.isEmpty) return;
    final remap = <int, int>{};
    final landed = <int>[];
    for (final node in source.nodes) {
      final copy = graph.add(
        node.type,
        position: Vector2(
          node.position.x + offset.dx,
          node.position.y + offset.dy,
        ),
      );
      copy.literals.addAll(node.literals);
      remap[node.id] = copy.id;
      landed.add(copy.id);
    }
    for (final link in source.links) {
      final from = remap[link.fromNode];
      final to = remap[link.toNode];
      if (from == null || to == null) continue;
      graph.links.add(
        VisualScriptLink(
          fromNode: from,
          fromPin: link.fromPin,
          toNode: to,
          toPin: link.toPin,
        ),
      );
    }
    setState(() {
      _selection
        ..clear()
        ..addAll(landed);
      _primary = landed.last;
      _selectedComment = null;
    });
    await _commit();
  }

  void _copySelection(VisualScriptGraph graph) {
    if (_selection.isEmpty) return;
    _clipboard = _lift(graph);
  }

  Future<void> _duplicateSelection(VisualScriptGraph graph) async {
    if (_selection.isEmpty) return;
    await _paste(graph, _lift(graph));
  }

  Future<void> _pasteClipboard(VisualScriptGraph graph) async {
    final source = _clipboard;
    if (source != null) await _paste(graph, source);
  }

  /// Moves the selected nodes into a graph of their own.
  Future<void> _collapseSelection(
    VisualScriptGraph graph,
    VisualScriptGraphKind kind,
  ) async {
    final blueprint = _blueprint;
    if (blueprint == null || _selection.isEmpty) return;
    final layout = _layout(graph);
    final call = collapseIntoGraph(
      blueprint: blueprint,
      source: graph,
      selection: _selection,
      kind: kind,
      typeOf: (node, pin, isInput) =>
          layout.typeOf((node: node, pin: pin, isInput: isInput)),
    );
    if (call == null) return;
    setState(() => _select(call.id));
    await _commit();
  }

  void _selectAll(VisualScriptGraph graph) {
    setState(() {
      _selection
        ..clear()
        ..addAll(graph.nodes.map((node) => node.id));
      _primary = _selection.isEmpty ? null : _selection.last;
    });
  }

  /// Puts a comment box around whatever is on screen.
  Future<void> _addComment(VisualScriptGraph graph) async {
    final centre = _toCanvas(
      Offset(context.size?.width ?? 400, context.size?.height ?? 300) / 2,
    );
    final comment = graph.addComment(
      position: Vector2(centre.dx - 120, centre.dy - 80),
    );
    setState(() {
      _select(null);
      _selectedComment = comment.id;
    });
    await _commit();
  }

  Future<void> _replaceVariable(
    Blueprint blueprint,
    VisualScriptVariable next,
  ) async {
    final index = blueprint.variables.indexWhere((v) => v.name == next.name);
    if (index < 0) return;
    setState(() => blueprint.variables[index] = next);
    await _commit();
  }

  Future<void> _deleteSelected(VisualScriptGraph graph) async {
    if (_selection.isEmpty) return;
    // Copied first: removeNode edits the graph, and the set is what says
    // which ones to remove.
    for (final id in _selection.toList()) {
      graph.removeNode(id);
    }
    setState(() => _select(null));
    await _commit();
  }

  Future<void> _addNode(
    VisualScriptNodeType type,
    VisualScriptGraph graph,
  ) async {
    // Where the palette was opened from, if it was opened from somewhere.
    // Otherwise the middle of what is on screen, so it lands where the eye is
    // rather than at the origin.
    final where =
        _dropAt ??
        _toCanvas(
          Offset(context.size?.width ?? 400, context.size?.height ?? 300) / 2,
        );
    // A node dragged out of a pin reads better placed just past the pointer
    // than centred on it, since the wire lands on its left edge.
    final from = _wireInto;
    final position = from == null || from.isInput
        ? where
        : where - const Offset(0, visualScriptHeaderHeight / 2);
    final node = graph.add(
      type.id,
      position: Vector2(position.dx, position.dy),
    );

    if (from != null) {
      final fromType = _wireIntoType;
      final pin = fromType == null
          ? null
          : visualScriptConnectablePin(
              type,
              fromType,
              fromIsInput: from.isInput,
              graphs: _blueprint?.graph,
            );
      if (pin != null) {
        graph.connect(
          from.isInput
              ? VisualScriptLink(
                  fromNode: node.id,
                  fromPin: pin,
                  toNode: from.node,
                  toPin: from.pin,
                )
              : VisualScriptLink(
                  fromNode: from.node,
                  fromPin: from.pin,
                  toNode: node.id,
                  toPin: pin,
                ),
          execOutputIsSingular: _wireIntoType == VisualScriptType.exec,
        );
      }
    }

    setState(() {
      _select(node.id);
      _closePalette();
    });
    await _commit();
  }

  /// Whether a fresh node of [type] has any pin the dragged wire could reach,
  /// which is what the palette filters on.
  bool _typeAccepts(VisualScriptNodeType type) {
    final fromType = _wireIntoType;
    final from = _wireInto;
    if (fromType == null || from == null) return true;
    return visualScriptConnectablePin(
          type,
          fromType,
          fromIsInput: from.isInput,
          graphs: _blueprint?.graph,
        ) !=
        null;
  }

  Future<void> _addGraph(VisualScriptGraphKind kind) async {
    final blueprint = _blueprint;
    if (blueprint == null) return;
    final added = blueprint.addGraph(VisualScriptGraph(), kind: kind);
    setState(() {
      _openGraphName = added.name;
      _select(null);
    });
    await _commit();
  }

  Future<void> _renameGraph(VisualScriptGraph graph, String name) async {
    final blueprint = _blueprint;
    if (blueprint == null) return;
    // Through uniqueGraphName, because a function is called by its name and
    // two graphs sharing one is a call with two possible answers.
    final wanted = blueprint.graph(name) == null
        ? name
        : blueprint.uniqueGraphName(name);
    final wasOpen = _openGraphName == graph.name;
    graph.name = wanted;
    setState(() {
      if (wasOpen) _openGraphName = wanted;
    });
    await _commit();
  }

  Future<void> _deleteGraph(VisualScriptGraph graph) async {
    final blueprint = _blueprint;
    if (blueprint == null) return;
    blueprint.graphs.remove(graph);
    setState(() {
      if (_openGraphName == graph.name) {
        _openGraphName = blueprint.graphs.isEmpty
            ? null
            : blueprint.graphs.first.name;
        _select(null);
      }
    });
    await _commit();
  }

  Future<void> _addVariable() async {
    final blueprint = _blueprint;
    if (blueprint == null) return;
    final taken = {for (final v in blueprint.variables) v.name};
    var name = 'newVar';
    for (var i = 2; taken.contains(name); i++) {
      name = 'newVar$i';
    }
    blueprint.variables.add(
      VisualScriptVariable(
        name: name,
        type: VisualScriptType.number,
        initial: 0.0,
      ),
    );
    setState(() {});
    await _commit();
  }

  Future<void> _renameVariable(
    VisualScriptVariable variable,
    String name,
  ) async {
    final blueprint = _blueprint;
    if (blueprint == null) return;
    // Through the blueprint, which carries the rename into every Get and Set
    // that names it: renaming only the declaration leaves the graph reading a
    // variable that is not there, which reads as null rather than as an error.
    if (!blueprint.renameVariable(variable.name, name)) return;
    setState(() {});
    await _commit();
  }

  Future<void> _deleteVariable(VisualScriptVariable variable) async {
    final blueprint = _blueprint;
    if (blueprint == null) return;
    blueprint.variables.remove(variable);
    setState(() {});
    await _commit();
  }

  @override
  Widget build(BuildContext context) {
    final blueprint = _ensureBlueprint();
    final graph = _graph;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(context, graph),
        Expanded(
          child: blueprint == null || graph == null
              ? _NoGraph(
                  hasSelection: _ctrl.selection.primary != null,
                  onAdd: _addFlowComponent,
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 200,
                      child: MyBlueprintPanel(
                        blueprint: blueprint,
                        openGraph: graph,
                        onOpenGraph: (picked) => setState(() {
                          _openGraphName = picked.name;
                          _select(null);
                        }),
                        onAddGraph: (kind) => unawaited(_addGraph(kind)),
                        onRenameGraph: (target, name) =>
                            unawaited(_renameGraph(target, name)),
                        onDeleteGraph: (target) =>
                            unawaited(_deleteGraph(target)),
                        selectedVariable: _selectedVariable,
                        onSelectVariable: (variable) => setState(() {
                          _selectedVariable = variable.name;
                          _select(null);
                          _selectedEvent = null;
                          _selectedComment = null;
                        }),
                        selectedEvent: _selectedEvent,
                        onSelectEvent: (event) => setState(() {
                          _selectedEvent = event.name;
                          _select(null);
                          _selectedVariable = null;
                          _selectedComment = null;
                        }),
                        onAddEvent: () => unawaited(_addEvent(blueprint)),
                        onRenameEvent: (event, name) =>
                            unawaited(_renameEvent(blueprint, event, name)),
                        onDeleteEvent: (event) =>
                            unawaited(_deleteEvent(blueprint, event)),
                        onAddVariable: () => unawaited(_addVariable()),
                        onRenameVariable: (variable, name) =>
                            unawaited(_renameVariable(variable, name)),
                        onDeleteVariable: (variable) =>
                            unawaited(_deleteVariable(variable)),
                      ),
                    ),
                    Container(width: 1, color: editorLineColor),
                    Expanded(
                      child: Stack(
                        children: [
                          _buildCanvas(graph),
                          if (_refusal case final reason?)
                            Positioned(
                              left: 10,
                              right: 10,
                              bottom: 10,
                              child: _WireRefusal(
                                reason: reason,
                                onDismiss: () =>
                                    setState(() => _refusal = null),
                              ),
                            ),
                          if (_paletteOpen)
                            VisualScriptPalette(
                              registry: _registry,
                              anchor: _paletteAt,
                              accepts: _wireInto == null ? null : _typeAccepts,
                              fromType: _wireIntoType,
                              fromIsInput: _wireInto?.isInput ?? false,
                              onPick: (type) => _addNode(type, graph),
                              onDismiss: () => setState(_closePalette),
                            ),
                        ],
                      ),
                    ),
                    Container(width: 1, color: editorLineColor),
                    SizedBox(
                      width: 232,
                      child: _selected == null && _selectedComment != null
                          ? _buildCommentDetails(graph)
                          : _selected == null && _selectedEvent != null
                          ? _buildEventDetails(blueprint)
                          : VisualScriptInspector(
                              graph: graph,
                              registry: _registry,
                              node: _selected == null
                                  ? null
                                  : graph.node(_selected!),
                              graphs: blueprint.graph,
                              callableGraphs: [
                                for (final candidate in blueprint.graphs)
                                  if (candidate.kind ==
                                          VisualScriptGraphKind.function ||
                                      candidate.kind ==
                                          VisualScriptGraphKind.macro)
                                    candidate.name,
                              ],
                              declaredEvents: [
                                for (final event in blueprint.events)
                                  event.name,
                              ],
                              variable: _selectedVariable == null
                                  ? null
                                  : blueprint.variables
                                        .where(
                                          (v) => v.name == _selectedVariable,
                                        )
                                        .firstOrNull,
                              onVariableChanged: (next) =>
                                  unawaited(_replaceVariable(blueprint, next)),
                              onGraphChanged: () => unawaited(_commit()),
                              onChanged: (key, value) =>
                                  unawaited(_setLiteral(graph, key, value)),
                            ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context, VisualScriptGraph? graph) {
    return EditorToolbar(
      leading: [
        const Icon(Icons.account_tree_outlined, size: 14),
        const SizedBox(width: 6),
        Text('Visual Scripter', style: editorBodyText),
        const SizedBox(width: 12),
        if (graph != null) ...[
          Icon(
            MyBlueprintPanel.kindGlyph(graph.kind),
            size: 12,
            color: editorMutedTextColor,
          ),
          const SizedBox(width: 4),
          Text(graph.name, style: editorBodyText),
          const SizedBox(width: 8),
          Text(
            '${graph.nodes.length} nodes, ${graph.links.length} wires',
            style: editorDetailText,
          ),
        ],
      ],
      trailing: [
        if (graph != null) ...[
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 15),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            tooltip: _selection.length > 1
                ? 'Delete the ${_selection.length} selected nodes'
                : 'Delete the selected node',
            onPressed: _selection.isEmpty ? null : () => _deleteSelected(graph),
          ),
          IconButton(
            icon: Icon(
              _tracing ? Icons.visibility : Icons.visibility_outlined,
              size: 15,
              color: _tracing ? editorAccentColor : null,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            tooltip: _tracing
                ? 'Stop watching the run'
                : 'Watch the run: which wires fire, and what is on them '
                      '(restarts the script)',
            onPressed: _toggleTracing,
          ),
          IconButton(
            icon: const Icon(Icons.center_focus_strong, size: 15),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            tooltip: 'Reset the view',
            onPressed: () => setState(() {
              _pan = const Offset(40, 40);
              _zoom = 1;
            }),
          ),
          if (_selection.isNotEmpty)
            PopupMenuButton<VisualScriptGraphKind>(
              tooltip: 'Move the selected nodes into a graph of their own',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.compress, size: 15),
              iconSize: 15,
              constraints: const BoxConstraints.tightFor(width: 220),
              onSelected: (kind) => unawaited(_collapseSelection(graph, kind)),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: VisualScriptGraphKind.function,
                  child: Text('Collapse to function'),
                ),
                const PopupMenuItem(
                  value: VisualScriptGraphKind.macro,
                  child: Text('Collapse to macro'),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.crop_square, size: 15),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            tooltip: 'Add a comment box',
            onPressed: () => unawaited(_addComment(graph)),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            onPressed: () => setState(() {
              // Always the unfiltered list from here, wherever the palette
              // was last opened from.
              if (_paletteOpen) {
                _closePalette();
              } else {
                _openPalette();
              }
            }),
            icon: const Icon(Icons.add, size: 15),
            label: const Text('Add node'),
          ),
        ],
      ],
    );
  }

  Widget _buildCanvas(VisualScriptGraph graph) {
    // The scripter opens as a full-screen route, on its own Navigator, so it
    // inherits none of the shell's shortcuts. Without this the canvas has no
    // keyboard at all — not even Delete.
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.delete):
            const _DeleteNodesIntent(),
        const SingleActivator(LogicalKeyboardKey.backspace):
            const _DeleteNodesIntent(),
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
            const _CopyNodesIntent(),
        const SingleActivator(LogicalKeyboardKey.keyC, control: true):
            const _CopyNodesIntent(),
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            const _PasteNodesIntent(),
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            const _PasteNodesIntent(),
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
            const _DuplicateNodesIntent(),
        const SingleActivator(LogicalKeyboardKey.keyD, control: true):
            const _DuplicateNodesIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            const _SelectAllNodesIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            const _SelectAllNodesIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _DeleteNodesIntent: CallbackAction<_DeleteNodesIntent>(
            onInvoke: (_) => unawaited(_deleteSelected(graph)),
          ),
          _CopyNodesIntent: CallbackAction<_CopyNodesIntent>(
            onInvoke: (_) => _copySelection(graph),
          ),
          _PasteNodesIntent: CallbackAction<_PasteNodesIntent>(
            onInvoke: (_) => unawaited(_pasteClipboard(graph)),
          ),
          _DuplicateNodesIntent: CallbackAction<_DuplicateNodesIntent>(
            onInvoke: (_) => unawaited(_duplicateSelection(graph)),
          ),
          _SelectAllNodesIntent: CallbackAction<_SelectAllNodesIntent>(
            onInvoke: (_) => _selectAll(graph),
          ),
        },
        child: Focus(autofocus: true, child: _buildCanvasSurface(graph)),
      ),
    );
  }

  Widget _buildCanvasSurface(VisualScriptGraph graph) {
    return Listener(
      onPointerDown: (event) => _onPointerDown(event, graph),
      onPointerMove: (event) => _onPointerMove(event, graph),
      onPointerUp: (event) => _onPointerUp(event, graph),
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        final zooming =
            HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed;
        setState(() {
          if (zooming) {
            final factor = event.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1;
            final next = (_zoom * factor).clamp(0.25, 2.5);
            // Zoom about the pointer, so the thing under the cursor stays
            // under it.
            final anchor = _toCanvas(event.localPosition);
            _zoom = next;
            _pan = event.localPosition - anchor * _zoom;
          } else {
            _pan -= event.scrollDelta;
          }
        });
      },
      child: ClipRect(
        child: CustomPaint(
          size: Size.infinite,
          painter: VisualScriptCanvasPainter(
            graph: graph,
            registry: _registry,
            pan: _pan,
            zoom: _zoom,
            selected: _selection,
            marquee: _marquee,
            wireFrom: _wireFrom,
            wirePointer: _wirePointer,
            trace: _tracing ? _liveComponent?.trace : null,
            graphs: _blueprint?.graph,
          ),
        ),
      ),
    );
  }
}

class _DeleteNodesIntent extends Intent {
  const _DeleteNodesIntent();
}

class _CopyNodesIntent extends Intent {
  const _CopyNodesIntent();
}

class _PasteNodesIntent extends Intent {
  const _PasteNodesIntent();
}

class _DuplicateNodesIntent extends Intent {
  const _DuplicateNodesIntent();
}

class _SelectAllNodesIntent extends Intent {
  const _SelectAllNodesIntent();
}

/// A node's visual script component, and which node it is on.
typedef ComponentSpecView = ({LocalId nodeId, ComponentSpec spec});

/// Why a wire would not connect, sitting under the canvas until it is stale.
///
/// A refusal that looks like a missed click is worse than no refusal at all:
/// the second time, somebody concludes the editor is unreliable rather than
/// that the wire was wrong.
class _WireRefusal extends StatelessWidget {
  const _WireRefusal({required this.reason, required this.onDismiss});

  final String reason;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: editorRaisedColor,
        borderRadius: BorderRadius.circular(editorControlRadius),
        border: Border.all(color: editorWarningColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, size: 13, color: editorWarningColor),
          const SizedBox(width: 6),
          Flexible(child: Text(reason, style: editorDetailText)),
          const SizedBox(width: 4),
          InkWell(
            onTap: onDismiss,
            child: const Icon(
              Icons.close,
              size: 13,
              color: editorMutedTextColor,
            ),
          ),
        ],
      ),
    ),
  );
}

class _NoGraph extends StatelessWidget {
  const _NoGraph({required this.hasSelection, required this.onAdd});

  final bool hasSelection;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.account_tree_outlined,
            size: 32,
            color: editorMutedTextColor,
          ),
          const SizedBox(height: 12),
          Text(
            hasSelection
                ? 'This node has no script'
                : 'Select a node to script it',
            style: editorDialogTitleText,
          ),
          const SizedBox(height: 8),
          Text(
            'A visual script holds a graph: events on the left, wired '
            'forward through what should happen.',
            textAlign: TextAlign.center,
            style: editorDetailText,
          ),
          if (hasSelection) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add a visual script'),
            ),
          ],
        ],
      ),
    ),
  );
}
