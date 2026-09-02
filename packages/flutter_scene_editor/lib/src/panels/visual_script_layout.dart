/// Where a visual script's nodes, pins, and wires land on the canvas, and how
/// they are drawn.
///
/// Kept apart from the panel because it is arithmetic: given a graph and a
/// registry it says where everything is, which is what hit testing needs and
/// what the painter needs, and neither needs a widget to say it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/visual_script.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import '../shell/editor_theme.dart';

/// A pin on a node, as the canvas refers to it.
typedef VisualScriptPortRef = ({int node, String pin, bool isInput});

/// Whether something on the canvas could take the wire being dragged.
enum _Reach {
  /// Nothing is being dragged, so everything draws normally.
  idle,

  /// The wire could land here.
  yes,

  /// It could not.
  no,
}

/// The colours a comment box can be given, in the order the editor cycles
/// through them. Muted on purpose: a comment sits behind the graph and must
/// not compete with the wires crossing it.
const List<Color> visualScriptCommentColors = [
  Color(0xFF3A5163),
  Color(0xFF4A4363),
  Color(0xFF3F5B4C),
  Color(0xFF63513A),
  Color(0xFF633A48),
];

/// How tall a comment's title bar is, and the band that drags the whole box.
const double visualScriptCommentHeaderHeight = 20;

/// The corner square that resizes a comment.
const double visualScriptCommentGrip = 14;

/// The node types drawn as a knot on the wire rather than as a box.
///
/// A reroute exists to bend a wire; drawing it as a node with a header and a
/// label would put a bigger obstacle in the way than the one it was added to
/// route around.
const Set<String> visualScriptRerouteTypes = {
  'flow.reroute',
  'flow.rerouteExec',
};

/// Node body metrics, in canvas units.
const double visualScriptNodeWidth = 168;
const double visualScriptHeaderHeight = 22;
const double visualScriptRowHeight = 18;
const double visualScriptPortRadius = 4.5;
const double visualScriptGrabRadius = 9;

/// The colour a wire and its pins take, by what travels along them.
///
/// Exec is the pale one because it is the spine of a graph and should read
/// first; the data types are hued so a wire's kind is legible without
/// following it to either end.
Color visualScriptTypeColor(VisualScriptType type) => switch (type) {
  VisualScriptType.exec => const Color(0xFFE8ECF0),
  VisualScriptType.boolean => const Color(0xFFC0504E),
  VisualScriptType.number => const Color(0xFF6FC96F),
  VisualScriptType.integer => const Color(0xFF4EC9B0),
  VisualScriptType.string => const Color(0xFFD98FD9),
  VisualScriptType.vector2 => const Color(0xFFE0C24E),
  VisualScriptType.vector3 => const Color(0xFFE0A84E),
  VisualScriptType.vector4 => const Color(0xFFE08A4E),
  VisualScriptType.quaternion => const Color(0xFF8E7BE0),
  VisualScriptType.color => const Color(0xFFE05C8A),
  VisualScriptType.list => const Color(0xFF5FB0A8),
  VisualScriptType.dictionary => const Color(0xFF4E9E86),
  VisualScriptType.nodeRef => const Color(0xFF4E86DE),
  VisualScriptType.assetRef => const Color(0xFF7FA8DE),
  VisualScriptType.any => const Color(0xFF9099A2),
};

/// Where everything in [graph] sits.
class VisualScriptLayout {
  VisualScriptLayout(this.graph, this.registry, {this.graphs});

  final VisualScriptGraph graph;
  final VisualScriptRegistry registry;

  /// How a node that names another graph finds it, for the node types whose
  /// pins come from one. Null when nothing on this canvas nests.
  final VisualScriptGraphLookup? graphs;

  /// What a node on this canvas takes its shape from: the graph it is in, and
  /// how to find one it names.
  VisualScriptShapeContext get shape =>
      VisualScriptShapeContext(graph: graph, graphs: graphs);

  /// The pins [node] has — which is a question about the node, not its type:
  /// a Switch has an output per case, a Sequence as many as it was given, and
  /// a Call Function whatever the graph it names declares.
  List<VisualScriptPin> pinsOf(VisualScriptNodeSpec node) =>
      registry[node.type]?.pinsOf(node, shape) ?? const [];

  Iterable<VisualScriptPin> inputsOf(VisualScriptNodeSpec node) =>
      pinsOf(node).where((pin) => pin.isInput);

  Iterable<VisualScriptPin> outputsOf(VisualScriptNodeSpec node) =>
      pinsOf(node).where((pin) => !pin.isInput);

  /// How many rows a node's body has: the taller of its input and output
  /// columns, since the two run side by side.
  int rowsOf(VisualScriptNodeSpec node) =>
      math.max(inputsOf(node).length, outputsOf(node).length);

  double heightOf(VisualScriptNodeSpec node) =>
      visualScriptHeaderHeight + rowsOf(node) * visualScriptRowHeight + 6;

  /// Whether [node] is drawn as a knot on a wire rather than as a box.
  bool isReroute(VisualScriptNodeSpec node) =>
      visualScriptRerouteTypes.contains(node.type);

  Rect boundsOf(VisualScriptNodeSpec node) {
    if (isReroute(node)) {
      // A small square centred on its position, so both of its pins sit at
      // the same point and the wire reads as continuous.
      const half = visualScriptPortRadius + 3;
      return Rect.fromLTWH(
        node.position.x - half,
        node.position.y - half,
        half * 2,
        half * 2,
      );
    }
    final type = registry[node.type];
    final height = type == null ? visualScriptHeaderHeight + 6 : heightOf(node);
    return Rect.fromLTWH(
      node.position.x,
      node.position.y,
      visualScriptNodeWidth,
      height,
    );
  }

  /// The box of the comment under [at], newest first, or null.
  ///
  /// Only the title bar counts: the body has to stay clickable so the nodes
  /// inside a comment can still be picked up.
  int? commentHeaderAt(Offset at) {
    for (final comment in graph.comments.reversed) {
      final header = Rect.fromLTWH(
        comment.position.x,
        comment.position.y,
        comment.size.x,
        visualScriptCommentHeaderHeight,
      );
      if (header.contains(at)) return comment.id;
    }
    return null;
  }

  /// The comment whose resize grip is under [at], or null.
  int? commentGripAt(Offset at) {
    for (final comment in graph.comments.reversed) {
      final grip = Rect.fromLTWH(
        comment.position.x + comment.size.x - visualScriptCommentGrip,
        comment.position.y + comment.size.y - visualScriptCommentGrip,
        visualScriptCommentGrip,
        visualScriptCommentGrip,
      );
      if (grip.contains(at)) return comment.id;
    }
    return null;
  }

  /// The nodes wholly inside [comment], which move with it.
  List<VisualScriptNodeSpec> nodesInside(VisualScriptComment comment) {
    final box = Rect.fromLTWH(
      comment.position.x,
      comment.position.y,
      comment.size.x,
      comment.size.y,
    );
    return [
      for (final node in graph.nodes)
        if (box.contains(boundsOf(node).topLeft) &&
            box.contains(boundsOf(node).bottomRight))
          node,
    ];
  }

  /// The centre of a pin, in canvas space.
  ///
  /// Inputs run down the left edge and outputs down the right, each in
  /// declaration order, which is what makes a graph read left to right.
  Offset? portCentre(int nodeId, String pinId) {
    final node = graph.node(nodeId);
    if (node == null) return null;
    final type = registry[node.type];
    if (type == null) return null;
    // Both of a reroute's pins are the same point, which is what makes the
    // wire through it read as one wire.
    if (isReroute(node)) return Offset(node.position.x, node.position.y);
    final pin = type.pinOf(node, pinId, shape);
    if (pin == null) return null;
    final column = pin.isInput ? inputsOf(node) : outputsOf(node);
    final index = column.toList().indexWhere((p) => p.id == pinId);
    if (index < 0) return null;
    final y =
        node.position.y +
        visualScriptHeaderHeight +
        index * visualScriptRowHeight +
        visualScriptRowHeight / 2;
    return Offset(
      node.position.x + (pin.isInput ? 0 : visualScriptNodeWidth),
      y,
    );
  }

  /// The pin under [at], within a grab radius, or null.
  ///
  /// Searched newest node first, matching the paint order, so a pin on a node
  /// drawn over another is the one that gets grabbed.
  VisualScriptPortRef? portAt(Offset at) {
    for (final node in graph.nodes.reversed) {
      if (registry[node.type] == null) continue;
      for (final pin in pinsOf(node)) {
        final centre = portCentre(node.id, pin.id);
        if (centre == null) continue;
        if ((centre - at).distance <= visualScriptGrabRadius) {
          return (node: node.id, pin: pin.id, isInput: pin.isInput);
        }
      }
    }
    return null;
  }

  /// The node under [at], or null.
  int? nodeAt(Offset at) {
    for (final node in graph.nodes.reversed) {
      if (boundsOf(node).contains(at)) return node.id;
    }
    return null;
  }

  /// Why a wire from [from] cannot land on [to], or null when it can.
  ///
  /// The message is the point. A drop that silently does nothing teaches
  /// nobody anything, and "you cannot put a Number into a Boolean" is a
  /// sentence someone can act on.
  String? refuseWire(
    VisualScriptPortRef from,
    VisualScriptType fromType,
    VisualScriptPortRef to,
    VisualScriptType toType,
  ) {
    if (from.node == to.node) return 'A node cannot wire into itself.';
    if (from.isInput == to.isInput) {
      return from.isInput
          ? 'Both of those are inputs. A wire runs from an output to an input.'
          : 'Both of those are outputs. A wire runs from an output to an '
                'input.';
    }
    final output = from.isInput ? to : from;
    final input = from.isInput ? from : to;
    final outType = from.isInput ? toType : fromType;
    final inType = from.isInput ? fromType : toType;

    final isExec = outType == VisualScriptType.exec;
    if (isExec != (inType == VisualScriptType.exec)) {
      return isExec
          ? 'That is a control wire, and it can only go to another control '
                'pin.'
          : 'A control pin only takes a control wire.';
    }
    if (!outType.connectsTo(inType)) {
      // Say which way round it failed, since the reverse is often allowed:
      // an Integer flows into a Number and a Number does not flow back.
      return inType.connectsTo(outType)
          ? 'A ${outType.label} does not fit a ${inType.label} pin — though '
                'it would fit the other way round.'
          : 'A ${outType.label} does not fit a ${inType.label} pin.';
    }
    if (!isExec && feedsInto(input.node, output.node)) {
      return 'That would make a loop: ${_nameOf(input.node)} already feeds '
          '${_nameOf(output.node)}.';
    }
    return null;
  }

  /// Whether [source] already reaches [target] through data wires.
  ///
  /// Only data wires: a loop in the exec wires is a loop, which is a thing
  /// graphs are allowed to have. A loop in the data wires is a value defined
  /// in terms of itself, which the runtime can only report as an error after
  /// the fact — so it is worth refusing while the wire is still in the hand.
  bool feedsInto(int source, int target) {
    if (source == target) return true;
    final seen = <int>{source};
    final pending = <int>[source];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      for (final link in graph.links) {
        if (link.fromNode != current) continue;
        if (_isExecLink(link)) continue;
        if (link.toNode == target) return true;
        if (seen.add(link.toNode)) pending.add(link.toNode);
      }
    }
    return false;
  }

  bool _isExecLink(VisualScriptLink link) {
    final node = graph.node(link.fromNode);
    if (node == null) return false;
    return registry[node.type]?.pinOf(node, link.fromPin, shape)?.type ==
        VisualScriptType.exec;
  }

  String _nameOf(int nodeId) {
    final node = graph.node(nodeId);
    if (node == null) return 'that node';
    return registry[node.type]?.label ?? node.type;
  }

  /// The type of the pin [port] names, or null when there is no such pin.
  VisualScriptType? typeOf(VisualScriptPortRef port) {
    final node = graph.node(port.node);
    if (node == null) return null;
    return registry[node.type]?.pinOf(node, port.pin, shape)?.type;
  }

  /// The pin nearest [at] that a wire from [from] could actually land on.
  ///
  /// Searched within [radius] rather than the grab radius, so letting go
  /// *near* the right pin lands on it. A pin that would be refused is not a
  /// candidate at all, which is what stops a drop snapping to a neighbour it
  /// cannot connect to.
  VisualScriptPortRef? nearestAcceptingPort(
    Offset at,
    VisualScriptPortRef from, {
    double radius = 28,
  }) {
    final fromType = typeOf(from);
    if (fromType == null) return null;
    VisualScriptPortRef? best;
    var bestDistance = double.infinity;
    for (final node in graph.nodes) {
      if (node.id == from.node) continue;
      for (final pin in pinsOf(node)) {
        if (pin.isInput == from.isInput) continue;
        final centre = portCentre(node.id, pin.id);
        if (centre == null) continue;
        final distance = (centre - at).distance;
        if (distance > radius || distance >= bestDistance) continue;
        final candidate = (node: node.id, pin: pin.id, isInput: pin.isInput);
        if (refuseWire(from, fromType, candidate, pin.type) != null) continue;
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// Whether [node] has any pin a wire from [from] could land on.
  bool acceptsWire(VisualScriptNodeSpec node, VisualScriptPortRef from) {
    final fromType = typeOf(from);
    if (fromType == null) return false;
    for (final pin in pinsOf(node)) {
      if (pin.isInput == from.isInput) continue;
      final candidate = (node: node.id, pin: pin.id, isInput: pin.isInput);
      if (refuseWire(from, fromType, candidate, pin.type) == null) return true;
    }
    return false;
  }
}

/// Draws the canvas: grid, wires, nodes, and the wire being dragged.
class VisualScriptCanvasPainter extends CustomPainter {
  VisualScriptCanvasPainter({
    required this.graph,
    required this.registry,
    required this.pan,
    required this.zoom,
    required this.selected,
    required this.wireFrom,
    required this.wirePointer,
    this.trace,
    this.graphs,
  }) : layout = VisualScriptLayout(graph, registry, graphs: graphs);

  final VisualScriptGraph graph;
  final VisualScriptRegistry registry;
  final Offset pan;
  final double zoom;
  final int? selected;
  final VisualScriptPortRef? wireFrom;
  final Offset? wirePointer;

  /// How a nesting node finds the graph it names, passed on to the layout.
  final VisualScriptGraphLookup? graphs;

  /// What the last tick did, or null when nothing is being watched.
  ///
  /// The canvas draws the same graph either way; this is what turns it from a
  /// diagram of what could happen into a picture of what did.
  final VisualScriptTrace? trace;
  final VisualScriptLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = editorSurfaceColor);
    _paintGrid(canvas, size);

    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(zoom);

    // Behind everything: a comment is a background, and a wire crossing one
    // has to stay readable.
    for (final comment in graph.comments) {
      _paintComment(canvas, comment);
    }
    for (final link in graph.links) {
      _paintWire(canvas, link);
    }
    final dragging = wireFrom;
    final pointer = wirePointer;
    if (dragging != null && pointer != null) {
      final start = layout.portCentre(dragging.node, dragging.pin);
      if (start != null) {
        _paintCurve(
          canvas,
          dragging.isInput ? pointer : start,
          dragging.isInput ? start : pointer,
          _typeColorOf(dragging).withValues(alpha: 0.8),
        );
      }
    }
    for (final node in graph.nodes) {
      _paintNode(canvas, node);
    }
    canvas.restore();
  }

  /// A grid that scrolls and scales with the canvas, so panning has something
  /// to read the motion against.
  void _paintGrid(Canvas canvas, Size size) {
    const spacing = 24.0;
    final step = spacing * zoom;
    if (step < 6) return;
    final paint = Paint()
      ..color = editorLineColor.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final firstX = pan.dx % step;
    final firstY = pan.dy % step;
    for (var x = firstX; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = firstY; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  VisualScriptType _typeColorType(int nodeId, String pinId) {
    final node = graph.node(nodeId);
    if (node == null) return VisualScriptType.any;
    return registry[node.type]?.pinOf(node, pinId, layout.shape)?.type ??
        VisualScriptType.any;
  }

  Color _typeColorOf(VisualScriptPortRef port) =>
      visualScriptTypeColor(_typeColorType(port.node, port.pin));

  void _paintWire(Canvas canvas, VisualScriptLink link) {
    final from = layout.portCentre(link.fromNode, link.fromPin);
    final to = layout.portCentre(link.toNode, link.toPin);
    if (from == null || to == null) return;
    final type = _typeColorType(link.fromNode, link.fromPin);
    final colour = visualScriptTypeColor(type);
    final run = trace;
    if (run == null) {
      _paintCurve(canvas, from, to, colour);
      return;
    }

    // With a trace, a wire is one of three things, and telling them apart is
    // the whole point: it carried the run, it exists but the run went the
    // other way, or it is a data wire with a value on it.
    final isExec = type == VisualScriptType.exec;
    final live = isExec
        ? run.didFire(link.fromNode, link.fromPin)
        : run.visitedNodes.contains(link.fromNode);
    _paintCurve(
      canvas,
      from,
      to,
      live ? colour : colour.withValues(alpha: 0.18),
      width: live && isExec ? 3.4 : 2.0,
    );
    if (isExec || !live) return;

    final value = run.valueOf(link.fromNode, link.fromPin);
    _paintWireLabel(canvas, (from + to) / 2, _short(value), colour);
  }

  /// The value a data wire is carrying, drawn on it.
  ///
  /// On the wire rather than in a side panel because the question is always
  /// "what went down *that* one", and a list of values keyed by node id is a
  /// second lookup the reader has to do by hand.
  void _paintWireLabel(Canvas canvas, Offset at, String text, Color colour) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 9, color: colour, height: 1.1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = Rect.fromCenter(
      center: at,
      width: painter.width + 8,
      height: painter.height + 4,
    );
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(3)),
        Paint()..color = editorSurfaceColor.withValues(alpha: 0.92),
      )
      ..drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(3)),
        Paint()
          ..color = colour.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    painter.paint(canvas, box.topLeft + const Offset(4, 2));
  }

  /// A value in the space a wire label has. Long text is cut rather than
  /// wrapped: a label that grows covers the graph it is describing.
  static String _short(Object? value) {
    if (value == null) return 'null';
    if (value is double) {
      return value == value.roundToDouble() && value.abs() < 1e6
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(3);
    }
    if (value is Vector3) {
      return '${_short(value.x)}, ${_short(value.y)}, ${_short(value.z)}';
    }
    final text = '$value';
    return text.length <= 18 ? text : '${text.substring(0, 17)}…';
  }

  /// A wire, as a horizontal-tangent bezier.
  ///
  /// The tangent grows with the horizontal gap so a short hop stays tight and
  /// a long one bows out of the way of what is between; a straight line
  /// between two pins on stacked nodes would run through both.
  void _paintCurve(
    Canvas canvas,
    Offset from,
    Offset to,
    Color color, {
    double width = 1.8,
  }) {
    final reach = math.max(40.0, (to.dx - from.dx).abs() * 0.5);
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(from.dx + reach, from.dy, to.dx - reach, to.dy, to.dx, to.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  void _paintComment(Canvas canvas, VisualScriptComment comment) {
    final bounds = Rect.fromLTWH(
      comment.position.x,
      comment.position.y,
      comment.size.x,
      comment.size.y,
    );
    // Wraps rather than fails: a document written by a later build that knows
    // more colours should still open.
    final colour =
        visualScriptCommentColors[comment.color.abs() %
            visualScriptCommentColors.length];
    final body = RRect.fromRectAndRadius(bounds, const Radius.circular(6));
    canvas
      ..drawRRect(body, Paint()..color = colour.withValues(alpha: 0.16))
      ..drawRRect(
        body,
        Paint()
          ..color = colour.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      )
      ..save()
      ..clipRRect(body)
      ..drawRect(
        Rect.fromLTWH(
          bounds.left,
          bounds.top,
          bounds.width,
          visualScriptCommentHeaderHeight,
        ),
        Paint()..color = colour.withValues(alpha: 0.55),
      )
      ..restore();

    TextPainter(
        text: TextSpan(
          text: comment.text,
          style: editorDetailText.copyWith(color: editorTextColor),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )
      ..layout(maxWidth: bounds.width - 12)
      ..paint(canvas, Offset(bounds.left + 7, bounds.top + 4));

    // The resize grip, as two short strokes in the corner.
    final corner = bounds.bottomRight;
    final grip = Paint()
      ..color = colour.withValues(alpha: 0.9)
      ..strokeWidth = 1.4;
    for (final inset in [4.0, 8.0]) {
      canvas.drawLine(
        Offset(corner.dx - inset, corner.dy - 3),
        Offset(corner.dx - 3, corner.dy - inset),
        grip,
      );
    }
  }

  /// A reroute, drawn as a knot on the wire rather than as a box.
  void _paintReroute(Canvas canvas, VisualScriptNodeSpec node) {
    final centre = Offset(node.position.x, node.position.y);
    final pin = layout.pinsOf(node).firstOrNull;
    final colour = visualScriptTypeColor(pin?.type ?? VisualScriptType.any);
    canvas
      ..drawCircle(
        centre,
        visualScriptPortRadius + 1.5,
        Paint()..color = colour,
      )
      ..drawCircle(
        centre,
        visualScriptPortRadius + 1.5,
        Paint()
          ..color = node.id == selected ? editorAccentColor : editorSurfaceColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = node.id == selected ? 1.8 : 1,
      );
  }

  void _paintNode(Canvas canvas, VisualScriptNodeSpec node) {
    if (layout.isReroute(node)) {
      _paintReroute(canvas, node);
      return;
    }
    final type = registry[node.type];
    final bounds = layout.boundsOf(node);
    final isSelected = node.id == selected;
    // While a wire is in hand, a node that cannot take it steps back. The
    // ones left at full strength are the answer to "where can this go".
    final reachable = _canReach(node);

    final body = RRect.fromRectAndRadius(bounds, const Radius.circular(5));
    canvas
      ..drawRRect(body, Paint()..color = _fade(editorPanelColor, reachable))
      ..drawRRect(
        body,
        Paint()
          ..color = _fade(
            isSelected ? editorAccentColor : editorLineColor,
            reachable,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 1.8 : 1,
      );

    // An event's header is tinted, because where a graph starts is the first
    // thing anyone looks for on a canvas full of boxes.
    final headerRect = Rect.fromLTWH(
      bounds.left,
      bounds.top,
      bounds.width,
      visualScriptHeaderHeight,
    );
    canvas
      ..save()
      ..clipRRect(body)
      ..drawRect(
        headerRect,
        Paint()
          ..color = _fade(
            (type?.isEvent ?? false)
                ? const Color(0xFF7A3A46)
                : editorRaisedColor,
            reachable,
          ),
      )
      ..restore();

    _text(
      canvas,
      type?.label ?? node.type,
      Offset(bounds.left + 8, bounds.top + 5),
      editorBodyText.copyWith(color: _fade(editorTextColor, reachable)),
    );

    if (type == null) {
      _text(
        canvas,
        'unknown type',
        Offset(bounds.left + 8, bounds.top + visualScriptHeaderHeight + 3),
        editorMicroText.copyWith(color: editorErrorColor),
      );
      return;
    }

    var row = 0;
    for (final pin in layout.inputsOf(node)) {
      _paintPin(canvas, node, pin, row++, isInput: true);
    }
    row = 0;
    for (final pin in layout.outputsOf(node)) {
      _paintPin(canvas, node, pin, row++, isInput: false);
    }
  }

  void _paintPin(
    Canvas canvas,
    VisualScriptNodeSpec node,
    VisualScriptPin pin,
    int row, {
    required bool isInput,
  }) {
    final centre = layout.portCentre(node.id, pin.id);
    if (centre == null) return;
    final accepts = _accepts(node, pin);
    final color = _fade(visualScriptTypeColor(pin.type), accepts);

    // A halo behind the pins that would take the wire, so the eye lands on
    // them rather than reading every label.
    if (accepts == _Reach.yes) {
      canvas.drawCircle(
        centre,
        visualScriptPortRadius + 4.5,
        Paint()..color = editorAccentColor.withValues(alpha: 0.35),
      );
    }

    if (pin.type == VisualScriptType.exec) {
      // Exec pins are triangles, so the spine of a graph is distinguishable
      // from its values at a glance rather than by colour alone.
      final path = Path()
        ..moveTo(centre.dx - 4, centre.dy - 5)
        ..lineTo(centre.dx + 5, centre.dy)
        ..lineTo(centre.dx - 4, centre.dy + 5)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    } else {
      canvas
        ..drawCircle(centre, visualScriptPortRadius, Paint()..color = color)
        ..drawCircle(
          centre,
          visualScriptPortRadius,
          Paint()
            ..color = editorSurfaceColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
    }

    if (pin.label.isEmpty) return;
    final style = editorMicroText.copyWith(
      color: _fade(editorMutedTextColor, accepts),
    );
    final painter = TextPainter(
      text: TextSpan(text: pin.label, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: visualScriptNodeWidth / 2 - 10);
    painter.paint(
      canvas,
      Offset(
        isInput ? centre.dx + 9 : centre.dx - 9 - painter.width,
        centre.dy - painter.height / 2,
      ),
    );
  }

  /// How a node or pin relates to the wire currently in hand.
  _Reach _canReach(VisualScriptNodeSpec node) {
    final dragging = wireFrom;
    if (dragging == null) return _Reach.idle;
    if (dragging.node == node.id) return _Reach.idle;
    return layout.acceptsWire(node, dragging) ? _Reach.yes : _Reach.no;
  }

  _Reach _accepts(VisualScriptNodeSpec node, VisualScriptPin pin) {
    final dragging = wireFrom;
    if (dragging == null) return _Reach.idle;
    // The pin the wire is coming from stays lit: it is the one end that is
    // definitely part of this connection.
    if (dragging.node == node.id) {
      return dragging.pin == pin.id ? _Reach.yes : _Reach.idle;
    }
    if (pin.isInput == dragging.isInput) return _Reach.no;
    final fromType = layout.typeOf(dragging);
    if (fromType == null) return _Reach.no;
    final candidate = (node: node.id, pin: pin.id, isInput: pin.isInput);
    return layout.refuseWire(dragging, fromType, candidate, pin.type) == null
        ? _Reach.yes
        : _Reach.no;
  }

  /// [color] as it should be drawn given [reach]: untouched unless a wire is
  /// in hand and this is somewhere it cannot go.
  Color _fade(Color color, _Reach reach) =>
      reach == _Reach.no ? color.withValues(alpha: color.a * 0.25) : color;

  void _text(Canvas canvas, String text, Offset at, TextStyle style) {
    TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )
      ..layout(maxWidth: visualScriptNodeWidth - 16)
      ..paint(canvas, at);
  }

  @override
  bool shouldRepaint(VisualScriptCanvasPainter old) => true;
}
