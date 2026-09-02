// Collapsing a selection into a function: the signature is worked out from
// the wires that crossed the boundary, so nobody has to describe it.

import 'package:flutter_scene/visual_script.dart';
import 'package:flutter_scene_editor/src/panels/visual_script_collapse.dart';
import 'package:flutter_test/flutter_test.dart';

final VisualScriptRegistry registry = sceneVisualScriptRegistry();

extension on VisualScriptGraph {
  void wire(
    VisualScriptNodeSpec from,
    String fromPin,
    VisualScriptNodeSpec to,
    String toPin,
  ) => links.add(
    VisualScriptLink(
      fromNode: from.id,
      fromPin: fromPin,
      toNode: to.id,
      toPin: toPin,
    ),
  );
}

/// Reads a pin's type out of the registry, the way the canvas does.
VisualScriptPinTypeLookup lookupFor(VisualScriptGraph graph) =>
    (nodeId, pin, isInput) {
      final node = graph.node(nodeId);
      if (node == null) return null;
      return registry[node.type]
          ?.pinOf(node, pin, VisualScriptShapeContext(graph: graph))
          ?.type;
    };

void main() {
  group('collapsing a middle slice of a graph', () {
    late Blueprint blueprint;
    late VisualScriptGraph events;
    late VisualScriptNodeSpec tick;
    late VisualScriptNodeSpec add;
    late VisualScriptNodeSpec print;
    late VisualScriptNodeSpec source;
    late VisualScriptNodeSpec after;
    late VisualScriptNodeSpec? call;

    setUp(() {
      blueprint = Blueprint();
      events = VisualScriptGraph(name: 'Events');
      tick = events.add('event.tick');
      source = events.add('math.random');
      // The slice being collapsed: a Set Position fed by a Make Vector.
      add = events.add('vector.make');
      print = events.add('scene.setPosition');
      after = events.add('debug.print');
      events
        ..wire(tick, 'then', print, 'exec')
        ..wire(source, 'value', add, 'x')
        ..wire(add, 'value', print, 'value')
        ..wire(print, 'then', after, 'exec');
      blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

      call = collapseIntoGraph(
        blueprint: blueprint,
        source: events,
        selection: {add.id, print.id},
        kind: VisualScriptGraphKind.function,
        typeOf: lookupFor(events),
      );
    });

    test('leaves a call node behind', () {
      expect(call, isNotNull);
      expect(events.node(call!.id)?.type, 'function.call');
    });

    test('and takes the collapsed nodes out of the original', () {
      expect(events.node(add.id), isNull);
      expect(events.node(print.id), isNull);
    });

    test('puts them in a new graph of the kind asked for', () {
      final made = blueprint.graphs.where(
        (g) => g.kind == VisualScriptGraphKind.function,
      );
      expect(made, hasLength(1));
      expect(
        made.single.nodes.map((n) => n.id),
        containsAll([add.id, print.id]),
      );
    });

    test('a wire that crossed in becomes a parameter', () {
      final made = blueprint.graph('${call!.literals[calledGraphKey]}')!;
      expect(made.parameters, hasLength(1));
      expect(
        made.parameters.single.type,
        VisualScriptType.number,
        reason: 'it took the type of the pin it fed',
      );
    });

    test('and the caller is wired into that parameter', () {
      final id = blueprint
          .graph('${call!.literals[calledGraphKey]}')!
          .parameters
          .single
          .id;
      expect(
        events.links.any(
          (l) =>
              l.fromNode == source.id && l.toNode == call!.id && l.toPin == id,
        ),
        isTrue,
      );
    });

    test('the control wire in becomes the call itself', () {
      expect(
        events.links.any((l) => l.fromNode == tick.id && l.toNode == call!.id),
        isTrue,
      );
      final made = blueprint.graph('${call!.literals[calledGraphKey]}')!;
      expect(
        made.links.any((l) => l.toNode == print.id && l.toPin == 'exec'),
        isTrue,
        reason: 'and the entry node picks it up inside',
      );
    });

    test('the control wire out continues after the call', () {
      expect(
        events.links.any((l) => l.fromNode == call!.id && l.toNode == after.id),
        isTrue,
      );
    });

    test('nothing is left wired to a node that has gone', () {
      final present = {for (final node in events.nodes) node.id};
      for (final link in events.links) {
        expect(present, contains(link.fromNode));
        expect(present, contains(link.toNode));
      }
    });
  });

  test('a wire that crossed out becomes a result', () {
    final blueprint = Blueprint();
    final events = VisualScriptGraph(name: 'Events');
    final maker = events.add('vector.make');
    final consumer = events.add('scene.setPosition');
    events.wire(maker, 'value', consumer, 'value');
    blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

    final call = collapseIntoGraph(
      blueprint: blueprint,
      source: events,
      selection: {maker.id},
      kind: VisualScriptGraphKind.function,
      typeOf: lookupFor(events),
    )!;
    final made = blueprint.graph('${call.literals[calledGraphKey]}')!;
    expect(made.results, hasLength(1));
    expect(made.results.single.type, VisualScriptType.vector3);
    expect(
      events.links.any((l) => l.fromNode == call.id && l.toNode == consumer.id),
      isTrue,
    );
  });

  test('collapsing nothing does nothing', () {
    final blueprint = Blueprint();
    final events = VisualScriptGraph(name: 'Events');
    blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);
    expect(
      collapseIntoGraph(
        blueprint: blueprint,
        source: events,
        selection: const {},
        kind: VisualScriptGraphKind.function,
        typeOf: lookupFor(events),
      ),
      isNull,
    );
    expect(blueprint.graphs, hasLength(1));
  });

  test('a self-contained selection needs no signature at all', () {
    final blueprint = Blueprint();
    final events = VisualScriptGraph(name: 'Events');
    final a = events.add('math.random');
    final b = events.add('math.add');
    events.wire(a, 'value', b, 'a');
    blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

    final call = collapseIntoGraph(
      blueprint: blueprint,
      source: events,
      selection: {a.id, b.id},
      kind: VisualScriptGraphKind.function,
      typeOf: lookupFor(events),
    )!;
    final made = blueprint.graph('${call.literals[calledGraphKey]}')!;
    expect(made.parameters, isEmpty);
    expect(made.results, isEmpty);
    expect(
      made.links.any((l) => l.fromNode == a.id && l.toNode == b.id),
      isTrue,
      reason: 'the wire between them came along',
    );
  });

  test('collapsing to a macro makes a macro', () {
    final blueprint = Blueprint();
    final events = VisualScriptGraph(name: 'Events');
    final node = events.add('debug.print');
    blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

    final call = collapseIntoGraph(
      blueprint: blueprint,
      source: events,
      selection: {node.id},
      kind: VisualScriptGraphKind.macro,
      typeOf: lookupFor(events),
    )!;
    expect(
      blueprint.graph('${call.literals[calledGraphKey]}')!.kind,
      VisualScriptGraphKind.macro,
    );
  });
}
