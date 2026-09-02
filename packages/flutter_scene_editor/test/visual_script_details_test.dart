// Declaring a graph's signature and a variable's type from the editor, which
// is the half of the function system that had no way in.

import 'package:flutter/material.dart';
import 'package:flutter_scene/visual_script.dart';
import 'package:flutter_scene_editor/src/panels/visual_script_details.dart';
import 'package:flutter_test/flutter_test.dart';

Future<int> showGraph(WidgetTester tester, VisualScriptGraph graph) async {
  var edits = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 280,
          height: 700,
          child: StatefulBuilder(
            builder: (context, setState) => VisualScriptGraphDetails(
              graph: graph,
              onChanged: () => setState(() => edits++),
            ),
          ),
        ),
      ),
    ),
  );
  return edits;
}

void main() {
  group('a function\'s signature', () {
    testWidgets('starts empty and says what that means', (tester) async {
      final graph = VisualScriptGraph(
        name: 'Double',
        kind: VisualScriptGraphKind.function,
      );
      await showGraph(tester, graph);
      expect(find.text('INPUTS'), findsOneWidget);
      expect(find.text('OUTPUTS'), findsOneWidget);
      expect(find.textContaining('No parameters'), findsOneWidget);
    });

    testWidgets('adding an input gives the graph a parameter', (tester) async {
      final graph = VisualScriptGraph(
        name: 'Double',
        kind: VisualScriptGraphKind.function,
      );
      await showGraph(tester, graph);

      // The add button beside the Inputs heading.
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pump();
      expect(graph.parameters, hasLength(1));
      expect(graph.parameters.single.type, VisualScriptType.number);
    });

    testWidgets('a second parameter does not reuse the first one\'s id', (
      tester,
    ) async {
      // Ids are what wires hold, so two parameters sharing one would land
      // every wire on whichever came first.
      final graph = VisualScriptGraph(
        name: 'Double',
        kind: VisualScriptGraphKind.function,
      );
      await showGraph(tester, graph);
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pump();
      expect(graph.parameters.map((p) => p.id).toSet(), hasLength(2));
    });

    testWidgets('an input and an output do not share an id either', (
      tester,
    ) async {
      final graph = VisualScriptGraph(
        name: 'Double',
        kind: VisualScriptGraphKind.function,
      );
      await showGraph(tester, graph);
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add).last);
      await tester.pump();
      expect(graph.parameters.single.id, isNot(graph.results.single.id));
    });

    testWidgets('renaming keeps the id, so a wire survives it', (tester) async {
      final graph = VisualScriptGraph(
        name: 'Double',
        kind: VisualScriptGraphKind.function,
        parameters: [
          const VisualScriptParameter(
            id: 'p1',
            name: 'N',
            type: VisualScriptType.number,
          ),
        ],
      );
      await showGraph(tester, graph);
      await tester.enterText(find.byType(TextField).first, 'Amount');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(graph.parameters.single.name, 'Amount');
      expect(graph.parameters.single.id, 'p1');
    });

    testWidgets('a name cleared to nothing is refused', (tester) async {
      final graph = VisualScriptGraph(
        name: 'Double',
        kind: VisualScriptGraphKind.function,
        parameters: [
          const VisualScriptParameter(
            id: 'p1',
            name: 'N',
            type: VisualScriptType.number,
          ),
        ],
      );
      await showGraph(tester, graph);
      await tester.enterText(find.byType(TextField).first, '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(graph.parameters.single.name, 'N');
    });

    testWidgets('exec is not offered as a parameter type', (tester) async {
      // A parameter of exec type would be a second control input nobody
      // could reach.
      expect(declarableTypes, isNot(contains(VisualScriptType.exec)));
      expect(declarableTypes, contains(VisualScriptType.vector3));
    });

    testWidgets('purity is offered for a function and not for a macro', (
      tester,
    ) async {
      await showGraph(
        tester,
        VisualScriptGraph(kind: VisualScriptGraphKind.function),
      );
      expect(find.text('Pure'), findsOneWidget);

      await showGraph(
        tester,
        VisualScriptGraph(kind: VisualScriptGraphKind.macro),
      );
      expect(find.text('Pure'), findsNothing);
    });

    testWidgets('an event graph is told it takes no parameters', (
      tester,
    ) async {
      await showGraph(
        tester,
        VisualScriptGraph(kind: VisualScriptGraphKind.eventGraph),
      );
      expect(find.text('INPUTS'), findsNothing);
      expect(find.textContaining('entered by its events'), findsOneWidget);
    });
  });

  group('a variable\'s details', () {
    testWidgets('offer a type and a scope, with the scope explained', (
      tester,
    ) async {
      VisualScriptVariable? replaced;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280,
              height: 500,
              child: VisualScriptVariableDetails(
                variable: VisualScriptVariable(
                  name: 'speed',
                  type: VisualScriptType.number,
                ),
                onReplace: (next) => replaced = next,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Scope'), findsOneWidget);
      expect(find.textContaining('every graph in this blueprint'), findsOne);

      await tester.tap(find.text('Number').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vector').last);
      await tester.pumpAndSettle();
      expect(replaced?.type, VisualScriptType.vector3);
      expect(replaced?.name, 'speed', reason: 'the name is its identity');
    });
  });
}
