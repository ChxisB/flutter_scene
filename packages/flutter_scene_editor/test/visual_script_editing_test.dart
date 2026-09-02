// Editing a graph from the editor: typing values into a node, and finding a
// node to put on the end of a wire.
//
// The inspector takes a graph and a registry and nothing else, so unlike the
// canvas it can be driven in a widget test without a GPU.

import 'package:flutter/material.dart';
import 'package:flutter_scene/visual_script.dart';
import 'package:flutter_scene_editor/src/panels/visual_script_inspector.dart';
import 'package:flutter_scene_editor/src/panels/visual_script_layout.dart';
import 'package:flutter_scene_editor/src/panels/visual_script_palette.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector2, Vector3;

final VisualScriptRegistry registry = sceneVisualScriptRegistry();

/// Puts [node]'s inspector on screen and reports every edit it makes.
Future<List<(String, Object?)>> showInspector(
  WidgetTester tester,
  VisualScriptGraph graph,
  VisualScriptNodeSpec? node,
) async {
  final edits = <(String, Object?)>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 260,
          height: 600,
          child: VisualScriptInspector(
            graph: graph,
            registry: registry,
            node: node,
            onChanged: (key, value) => edits.add((key, value)),
          ),
        ),
      ),
    ),
  );
  return edits;
}

void main() {
  group('the inspector', () {
    testWidgets('offers a row for every unwired input', (tester) async {
      final graph = VisualScriptGraph();
      final node = graph.add('flow.delay');
      await showInspector(tester, graph, node);
      expect(find.text('Seconds'), findsOneWidget);
    });

    testWidgets('does not offer a box for a pin that has a wire', (
      tester,
    ) async {
      final graph = VisualScriptGraph();
      final source = graph.add('math.random');
      final delay = graph.add('flow.delay');
      graph.connect(
        VisualScriptLink(
          fromNode: source.id,
          fromPin: 'value',
          toNode: delay.id,
          toPin: 'seconds',
        ),
      );
      await showInspector(tester, graph, delay);
      expect(
        find.text('WIRED'),
        findsOneWidget,
        reason: 'it says where the value comes from instead',
      );
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('writes a number back as a number', (tester) async {
      final graph = VisualScriptGraph();
      final node = graph.add('flow.delay');
      final edits = await showInspector(tester, graph, node);

      await tester.enterText(find.byType(TextField).first, '2.5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(edits, [('seconds', 2.5)]);
    });

    testWidgets('clearing a value puts the pin back on its default', (
      tester,
    ) async {
      final graph = VisualScriptGraph();
      final node = graph.add('flow.delay')..literals['seconds'] = 4.0;
      final edits = await showInspector(tester, graph, node);

      await tester.enterText(find.byType(TextField).first, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(edits, [
        ('seconds', null),
      ], reason: 'null clears the key rather than storing null');
    });

    testWidgets('a Switch has a Cases setting, written back as a list', (
      tester,
    ) async {
      final graph = VisualScriptGraph();
      final node = graph.add('flow.switchString');
      final edits = await showInspector(tester, graph, node);
      expect(find.text('Cases'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'red, green, 3');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      // Compared part by part: two records holding equal lists are not equal
      // records, because a list compares by identity.
      expect(edits.single.$1, 'cases');
      expect(edits.single.$2, [
        'red',
        'green',
        3,
      ], reason: 'a case that looks like a number is read as one');
    });

    testWidgets('a Get Variable offers its scope as a choice', (tester) async {
      final graph = VisualScriptGraph();
      final node = graph.add('var.get');
      await showInspector(tester, graph, node);
      expect(find.text('Scope'), findsOneWidget);
      expect(find.text('graph'), findsWidgets);
    });

    testWidgets('a vector is three boxes, and one edit keeps the rest', (
      tester,
    ) async {
      final graph = VisualScriptGraph();
      final node = graph.add('scene.setPosition')
        ..literals['value'] = Vector3(1, 2, 3);
      final edits = await showInspector(tester, graph, node);
      expect(find.text('X'), findsOneWidget);
      expect(find.text('Z'), findsOneWidget);

      // Set Position leads with its Target pin, so the vector's three boxes
      // are the second, third and fourth fields on the panel.
      await tester.enterText(find.byType(TextField).at(2), '9');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(edits.single.$1, 'value');
      expect(
        edits.single.$2,
        Vector3(1, 9, 3),
        reason: 'editing Y leaves X and Z where they were',
      );
    });

    testWidgets('a Call node offers the blueprint\'s functions', (
      tester,
    ) async {
      final graph = VisualScriptGraph();
      final node = graph.add('function.call');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              height: 600,
              child: VisualScriptInspector(
                graph: graph,
                registry: registry,
                node: node,
                callableGraphs: const ['Double', 'Stamp'],
                onChanged: (_, _) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Function'), findsOneWidget);
      expect(find.text('Double'), findsWidgets);
    });

    testWidgets('and says so when there are none yet', (tester) async {
      final graph = VisualScriptGraph();
      final node = graph.add('function.call');
      await showInspector(tester, graph, node);
      expect(find.textContaining('Nothing to choose'), findsOneWidget);
    });

    testWidgets('an unknown node type says so rather than showing nothing', (
      tester,
    ) async {
      final graph = VisualScriptGraph();
      final node = graph.add('not.a.real.node');
      await showInspector(tester, graph, node);
      expect(find.textContaining('not.a.real.node'), findsOneWidget);
    });

    testWidgets('nothing selected says what to do', (tester) async {
      await showInspector(tester, VisualScriptGraph(), null);
      expect(find.textContaining('Select a node'), findsOneWidget);
    });
  });

  group('finding a node for the end of a wire', () {
    test('an output offers a node with an input that takes it', () {
      final pin = visualScriptConnectablePin(
        registry['debug.print']!,
        VisualScriptType.exec,
        fromIsInput: false,
      );
      expect(pin, 'exec');
    });

    test('an input offers a node with an output that gives it', () {
      final pin = visualScriptConnectablePin(
        registry['math.random']!,
        VisualScriptType.number,
        fromIsInput: true,
      );
      expect(pin, 'value');
    });

    test('a type that cannot connect offers nothing', () {
      // A Make Vector has no exec pin at all, so an exec wire has nowhere to
      // land on it.
      expect(
        visualScriptConnectablePin(
          registry['vector.make']!,
          VisualScriptType.exec,
          fromIsInput: false,
        ),
        isNull,
      );
    });

    test('widening counts: an integer wire lands on a number pin', () {
      expect(
        visualScriptConnectablePin(
          registry['math.add']!,
          VisualScriptType.integer,
          fromIsInput: false,
        ),
        'a',
      );
    });

    test('a dynamic-pin type is asked what a fresh one would look like', () {
      // A Switch with no cases still has its selector and its default, and
      // the probe must not need a graph to find them.
      expect(
        visualScriptConnectablePin(
          registry['flow.switchString']!,
          VisualScriptType.string,
          fromIsInput: false,
        ),
        'selector',
      );
    });
  });

  group('searching the palette', () {
    int? rank(String id, String needle) =>
        visualScriptPaletteRank(registry[id]!, needle);

    test('an empty search matches everything equally', () {
      expect(rank('flow.forLoop', ''), 0);
      expect(rank('text.format', ''), 0);
    });

    test('a label that starts with the search beats one that contains it', () {
      // Typing "for" into a graph editor means For Loop, not Format Text.
      expect(rank('flow.forLoop', 'for')! < rank('text.format', 'for')!, true);
    });

    test('the shorter of two prefix matches comes first', () {
      // Typing "add" should reach Add before Add Vectors.
      expect(rank('math.add', 'add')! < rank('vector.add', 'add')!, true);
    });

    test('a label beats an id beats the documentation', () {
      expect(
        rank('debug.print', 'print')! < rank('debug.print', 'debug')!,
        true,
      );
    });

    test('no match anywhere is no match', () {
      expect(rank('debug.print', 'quaternion'), isNull);
    });
  });

  group('what a wire is allowed to connect to', () {
    /// A layout over a graph built by [build].
    VisualScriptLayout layoutFor(void Function(VisualScriptGraph) build) {
      final graph = VisualScriptGraph();
      build(graph);
      return VisualScriptLayout(graph, registry);
    }

    VisualScriptPortRef out(int node, String pin) =>
        (node: node, pin: pin, isInput: false);
    VisualScriptPortRef inp(int node, String pin) =>
        (node: node, pin: pin, isInput: true);

    test('a value fits a pin of its own type', () {
      late VisualScriptNodeSpec a;
      late VisualScriptNodeSpec b;
      final layout = layoutFor((g) {
        a = g.add('math.random');
        b = g.add('math.add');
      });
      expect(
        layout.refuseWire(
          out(a.id, 'value'),
          VisualScriptType.number,
          inp(b.id, 'a'),
          VisualScriptType.number,
        ),
        isNull,
      );
    });

    test('a control wire is refused by a value pin, and says so', () {
      late VisualScriptNodeSpec a;
      late VisualScriptNodeSpec b;
      final layout = layoutFor((g) {
        a = g.add('event.start');
        b = g.add('math.add');
      });
      expect(
        layout.refuseWire(
          out(a.id, 'then'),
          VisualScriptType.exec,
          inp(b.id, 'a'),
          VisualScriptType.number,
        ),
        contains('control wire'),
      );
    });

    test('a mismatch names both types', () {
      late VisualScriptNodeSpec a;
      late VisualScriptNodeSpec b;
      final layout = layoutFor((g) {
        a = g.add('math.random');
        b = g.add('flow.branch');
      });
      final reason = layout.refuseWire(
        out(a.id, 'value'),
        VisualScriptType.number,
        inp(b.id, 'condition'),
        VisualScriptType.boolean,
      );
      expect(reason, contains('Number'));
      expect(reason, contains('Boolean'));
    });

    test('a widening that only works one way says which way', () {
      late VisualScriptNodeSpec a;
      late VisualScriptNodeSpec b;
      final layout = layoutFor((g) {
        a = g.add('math.random');
        b = g.add('flow.forLoop');
      });
      // Number into Integer is refused, but Integer into Number is fine, and
      // saying so is the difference between a rule and a wall.
      expect(
        layout.refuseWire(
          out(a.id, 'value'),
          VisualScriptType.number,
          inp(b.id, 'first'),
          VisualScriptType.integer,
        ),
        contains('other way round'),
      );
    });

    test('two inputs, or two outputs, is not a wire', () {
      late VisualScriptNodeSpec a;
      late VisualScriptNodeSpec b;
      final layout = layoutFor((g) {
        a = g.add('math.add');
        b = g.add('math.add');
      });
      expect(
        layout.refuseWire(
          inp(a.id, 'a'),
          VisualScriptType.number,
          inp(b.id, 'a'),
          VisualScriptType.number,
        ),
        contains('Both of those are inputs'),
      );
    });

    test('a node cannot wire into itself', () {
      late VisualScriptNodeSpec a;
      final layout = layoutFor((g) => a = g.add('math.add'));
      expect(
        layout.refuseWire(
          out(a.id, 'value'),
          VisualScriptType.number,
          inp(a.id, 'a'),
          VisualScriptType.number,
        ),
        contains('itself'),
      );
    });

    test('a data wire that would close a loop is refused', () {
      late VisualScriptNodeSpec a;
      late VisualScriptNodeSpec b;
      final layout = layoutFor((g) {
        a = g.add('math.add');
        b = g.add('math.add');
        g.connect(
          VisualScriptLink(
            fromNode: a.id,
            fromPin: 'value',
            toNode: b.id,
            toPin: 'a',
          ),
        );
      });
      // A already feeds B, so B feeding A is a value defined by itself.
      expect(
        layout.refuseWire(
          out(b.id, 'value'),
          VisualScriptType.number,
          inp(a.id, 'a'),
          VisualScriptType.number,
        ),
        contains('loop'),
      );
    });

    test('but a diamond is not a loop', () {
      late VisualScriptNodeSpec a;
      late VisualScriptNodeSpec b;
      final layout = layoutFor((g) {
        a = g.add('math.random');
        b = g.add('math.add');
        g.connect(
          VisualScriptLink(
            fromNode: a.id,
            fromPin: 'value',
            toNode: b.id,
            toPin: 'a',
          ),
        );
      });
      expect(
        layout.refuseWire(
          out(a.id, 'value'),
          VisualScriptType.number,
          inp(b.id, 'b'),
          VisualScriptType.number,
        ),
        isNull,
        reason: 'one source feeding two inputs is ordinary',
      );
    });

    test('a loop in the control wires is allowed, because that is a loop', () {
      late VisualScriptNodeSpec branch;
      late VisualScriptNodeSpec steps;
      final layout = layoutFor((g) {
        branch = g.add('flow.branch');
        steps = g.add('flow.sequence');
        g.connect(
          VisualScriptLink(
            fromNode: branch.id,
            fromPin: 'true',
            toNode: steps.id,
            toPin: 'exec',
          ),
        );
      });
      expect(
        layout.refuseWire(
          out(steps.id, 'a'),
          VisualScriptType.exec,
          inp(branch.id, 'exec'),
          VisualScriptType.exec,
        ),
        isNull,
      );
    });

    test('dropping near a pin lands on it', () {
      late VisualScriptNodeSpec a;
      late VisualScriptNodeSpec b;
      final layout = layoutFor((g) {
        a = g.add('math.random', position: Vector2(0, 0));
        b = g.add('math.add', position: Vector2(300, 0));
      });
      final target = layout.portCentre(b.id, 'a')!;
      final landed = layout.nearestAcceptingPort(
        target + const Offset(11, 6),
        out(a.id, 'value'),
      );
      expect(landed?.node, b.id);
      expect(landed?.pin, 'a');
    });

    test('and does not land on a pin it could not connect to', () {
      late VisualScriptNodeSpec a;
      late VisualScriptNodeSpec b;
      final layout = layoutFor((g) {
        a = g.add('event.start', position: Vector2(0, 0));
        b = g.add('math.add', position: Vector2(300, 0));
      });
      // An exec wire let go right on a number pin snaps to nothing, rather
      // than to whichever pin happens to be nearest.
      expect(
        layout.nearestAcceptingPort(
          layout.portCentre(b.id, 'a')!,
          out(a.id, 'then'),
        ),
        isNull,
      );
    });

    test('a node with nothing compatible does not accept the wire', () {
      late VisualScriptNodeSpec a;
      late VisualScriptNodeSpec b;
      final layout = layoutFor((g) {
        a = g.add('event.start');
        b = g.add('vector.make');
      });
      expect(
        layout.acceptsWire(b, out(a.id, 'then')),
        isFalse,
        reason: 'Make Vector has no control pin at all',
      );
    });

    test('a node with one compatible pin does accept it', () {
      late VisualScriptNodeSpec a;
      late VisualScriptNodeSpec b;
      final layout = layoutFor((g) {
        a = g.add('event.start');
        b = g.add('debug.print');
      });
      expect(layout.acceptsWire(b, out(a.id, 'then')), isTrue);
    });
  });

  group('comments and reroutes', () {
    test('a comment takes an id from the same counter as a node', () {
      // One counter for both, so an id in a saved document is unambiguous
      // about what it names.
      final graph = VisualScriptGraph();
      final node = graph.add('debug.print');
      final comment = graph.addComment();
      expect(comment.id, isNot(node.id));
      expect(graph.comment(comment.id), same(comment));
    });

    test('only its title bar is grabbable, so nodes inside stay clickable', () {
      final graph = VisualScriptGraph();
      final comment = graph.addComment(position: Vector2(0, 0));
      final layout = VisualScriptLayout(graph, registry);
      expect(layout.commentHeaderAt(const Offset(20, 6)), comment.id);
      expect(
        layout.commentHeaderAt(const Offset(20, 90)),
        isNull,
        reason: 'the body is not a handle',
      );
    });

    test('its corner grip is where a resize starts', () {
      final graph = VisualScriptGraph();
      final comment = graph.addComment(position: Vector2(0, 0));
      final layout = VisualScriptLayout(graph, registry);
      expect(
        layout.commentGripAt(Offset(comment.size.x - 4, comment.size.y - 4)),
        comment.id,
      );
      expect(layout.commentGripAt(const Offset(10, 10)), isNull);
    });

    test('it collects the nodes wholly inside it, and no others', () {
      final graph = VisualScriptGraph();
      final comment = graph.addComment(
        position: Vector2(0, 0),
        size: Vector2(400, 400),
      );
      final inside = graph.add('debug.print', position: Vector2(20, 40));
      final outside = graph.add('debug.print', position: Vector2(900, 40));
      // Straddling the edge is not inside: half a node moving with the box
      // would be worse than none.
      final straddling = graph.add('debug.print', position: Vector2(320, 40));
      final layout = VisualScriptLayout(graph, registry);
      final collected = layout.nodesInside(comment).map((n) => n.id).toSet();
      expect(collected, contains(inside.id));
      expect(collected, isNot(contains(outside.id)));
      expect(collected, isNot(contains(straddling.id)));
    });

    test('a reroute is a knot: both pins sit at the same point', () {
      final graph = VisualScriptGraph();
      final knot = graph.add('flow.reroute', position: Vector2(100, 50));
      final layout = VisualScriptLayout(graph, registry);
      expect(layout.isReroute(knot), isTrue);
      expect(layout.portCentre(knot.id, 'value'), const Offset(100, 50));
      expect(layout.portCentre(knot.id, 'out'), const Offset(100, 50));
    });

    test('and it is small enough to be a bend rather than an obstacle', () {
      final graph = VisualScriptGraph();
      final knot = graph.add('flow.reroute', position: Vector2(100, 50));
      // Well clear of the knot: an overlapping node would win the hit test on
      // paint order, which is correct and not what this is measuring.
      final node = graph.add('debug.print', position: Vector2(400, 400));
      final layout = VisualScriptLayout(graph, registry);
      expect(
        layout.boundsOf(knot).width,
        lessThan(layout.boundsOf(node).width / 4),
      );
      expect(layout.nodeAt(const Offset(100, 50)), knot.id);
    });

    test('a comment survives being saved', () {
      final graph = VisualScriptGraph();
      graph.addComment(position: Vector2(10, 20), size: Vector2(300, 200))
        ..text = 'Movement'
        ..color = 2;
      final after = readVisualScript(writeVisualScript(graph));
      final comment = after.comments.single;
      expect(comment.text, 'Movement');
      expect(comment.color, 2);
      expect(comment.position.x, 10);
      expect(comment.size.y, 200);
    });

    test('and does not hand its id to the next node added', () {
      final graph = VisualScriptGraph();
      graph.addComment();
      final after = readVisualScript(writeVisualScript(graph));
      expect(after.add('debug.print').id, isNot(after.comments.single.id));
    });
  });

  group('the canvas draws what the node actually has', () {
    test('a Switch grows a row per case', () {
      final graph = VisualScriptGraph();
      final node = graph.add('flow.switchString');
      final layout = VisualScriptLayout(graph, registry);
      final before = layout.boundsOf(node).height;

      node.literals['cases'] = <Object?>['a', 'b', 'c'];
      final after = layout.boundsOf(node).height;
      expect(
        after,
        greaterThan(before),
        reason: 'three cases are three more output rows',
      );
      expect(
        layout.portCentre(node.id, casePin(2)),
        isNotNull,
        reason: 'and the third one can be wired',
      );
    });

    test('a Sequence given a count grows with it', () {
      final graph = VisualScriptGraph();
      final node = graph.add('flow.sequence');
      final layout = VisualScriptLayout(graph, registry);
      expect(layout.outputsOf(node).length, 3);

      node.literals['count'] = 6;
      expect(layout.outputsOf(node).length, 6);
      expect(layout.portCentre(node.id, sequencePin(5)), isNotNull);
    });

    test('every pin type has a colour of its own', () {
      final seen = <Color>{};
      for (final type in VisualScriptType.values) {
        expect(
          seen.add(visualScriptTypeColor(type)),
          isTrue,
          reason: type.name,
        );
      }
    });
  });
}
