/// Moving a selection into a graph of its own, and leaving a call behind.
///
/// The interesting part is that nobody has to describe the new graph's
/// signature: the selection already says where its edges are. A wire that
/// crossed into the selection becomes a parameter, one that crossed out
/// becomes a result, and the control wires at either end become the call
/// itself.
///
/// Kept out of the panel so it can be exercised without a canvas, a
/// controller or a GPU — it is the most intricate edit the scripter makes.
library;

import 'package:flutter_scene/visual_script.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

/// What type a pin is, asked of whatever knows — the canvas layout, in the
/// editor; a stub, in a test.
typedef VisualScriptPinTypeLookup =
    VisualScriptType? Function(int node, String pin, bool isInput);

/// Moves [selection] out of [source] into a new graph of [kind] on
/// [blueprint], and returns the call node left in its place.
///
/// Returns null when there is nothing selected.
/// Moves the selected nodes into a new graph, and leaves a call node where
/// they were.
///
/// The signature is worked out from the wires that crossed the boundary: a
/// wire coming in becomes a parameter, one going out becomes a result. That
/// is the whole trick — the selection already says where the edges are, so
/// the function's shape is not a question anyone has to answer.
VisualScriptNodeSpec? collapseIntoGraph({
  required Blueprint blueprint,
  required VisualScriptGraph source,
  required Set<int> selection,
  required VisualScriptGraphKind kind,
  required VisualScriptPinTypeLookup typeOf,
}) {
  if (selection.isEmpty) return null;

  final inside = Set<int>.of(selection);
  final crossingIn = <VisualScriptLink>[];
  final crossingOut = <VisualScriptLink>[];
  for (final link in source.links) {
    final fromIn = inside.contains(link.fromNode);
    final toIn = inside.contains(link.toNode);
    if (fromIn == toIn) continue;
    (fromIn ? crossingOut : crossingIn).add(link);
  }

  final target = blueprint.addGraph(VisualScriptGraph(), kind: kind);
  final entry = target.add('function.entry', position: Vector2(-220, 0));
  final result = target.add('function.result', position: Vector2(420, 0));

  // Move the nodes over, keeping their ids so the wires between them can be
  // copied across unchanged.
  final moved = <VisualScriptNodeSpec>[];
  for (final id in inside) {
    final node = source.node(id);
    if (node != null) moved.add(node);
  }
  for (final node in moved) {
    target.nodes.add(node);
    if (node.id >= target.nextNodeId) target.nextNodeId = node.id + 1;
  }
  for (final link in source.links) {
    if (inside.contains(link.fromNode) && inside.contains(link.toNode)) {
      target.links.add(link);
    }
  }

  final call = source.add('function.call')
    ..literals[calledGraphKey] = target.name;
  // Placed where the selection was, so the graph does not rearrange itself
  // under the author.
  if (moved.isNotEmpty) {
    call.position.setValues(moved.first.position.x, moved.first.position.y);
  }

  // A wire that came in becomes a parameter: named after the pin it fed,
  // and rewired from the entry node inside to the same pin.
  var index = 0;
  for (final link in crossingIn) {
    final pin = typeOf(link.toNode, link.toPin, true);
    if (pin == VisualScriptType.exec) {
      // Control coming in is the call itself, not a parameter.
      source.links.add(
        VisualScriptLink(
          fromNode: link.fromNode,
          fromPin: link.fromPin,
          toNode: call.id,
          toPin: 'exec',
        ),
      );
      target.links.add(
        VisualScriptLink(
          fromNode: entry.id,
          fromPin: 'then',
          toNode: link.toNode,
          toPin: link.toPin,
        ),
      );
      continue;
    }
    final id = 'p${++index}';
    target.parameters.add(
      VisualScriptParameter(
        id: id,
        name: 'In $index',
        type: pin ?? VisualScriptType.any,
      ),
    );
    source.links.add(
      VisualScriptLink(
        fromNode: link.fromNode,
        fromPin: link.fromPin,
        toNode: call.id,
        toPin: id,
      ),
    );
    target.links.add(
      VisualScriptLink(
        fromNode: entry.id,
        fromPin: id,
        toNode: link.toNode,
        toPin: link.toPin,
      ),
    );
  }

  var outIndex = 0;
  for (final link in crossingOut) {
    final pin = typeOf(link.fromNode, link.fromPin, false);
    if (pin == VisualScriptType.exec) {
      target.links.add(
        VisualScriptLink(
          fromNode: link.fromNode,
          fromPin: link.fromPin,
          toNode: result.id,
          toPin: 'exec',
        ),
      );
      source.links.add(
        VisualScriptLink(
          fromNode: call.id,
          fromPin: 'then',
          toNode: link.toNode,
          toPin: link.toPin,
        ),
      );
      continue;
    }
    final id = 'r${++outIndex}';
    target.results.add(
      VisualScriptParameter(
        id: id,
        name: 'Out $outIndex',
        type: pin ?? VisualScriptType.any,
      ),
    );
    target.links.add(
      VisualScriptLink(
        fromNode: link.fromNode,
        fromPin: link.fromPin,
        toNode: result.id,
        toPin: id,
      ),
    );
    source.links.add(
      VisualScriptLink(
        fromNode: call.id,
        fromPin: id,
        toNode: link.toNode,
        toPin: link.toPin,
      ),
    );
  }

  // Only now: removeNode drops every wire touching the node, and the ones
  // crossing the boundary had to be read before that happened.
  for (final id in inside) {
    source.removeNode(id);
  }

  return call;
}
