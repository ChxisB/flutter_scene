// Variable scopes: which store a Get and a Set reach, and how long each one
// keeps what was put in it.

import 'package:scene/visual_script.dart';
import 'package:test/test.dart';

/// A graph that sets `name` in [scope] to [value] on every tick, then reads it
/// back and prints it.
({VisualScriptGraph graph, NullVisualScriptHost host}) roundTrip(
  VisualScriptVariableScope scope, {
  String name = 'n',
  Object? value = 1,
}) {
  final graph = VisualScriptGraph();
  final tick = graph.add('event.tick');
  final write = graph.add('var.set')
    ..literals['name'] = name
    ..literals['value'] = value
    ..literals['scope'] = scope.name;
  final read = graph.add('var.get')
    ..literals['name'] = name
    ..literals['scope'] = scope.name;
  final print = graph.add('debug.print');
  graph
    ..connect(
      VisualScriptLink(
        fromNode: tick.id,
        fromPin: 'then',
        toNode: write.id,
        toPin: 'exec',
      ),
    )
    ..connect(
      VisualScriptLink(
        fromNode: write.id,
        fromPin: 'then',
        toNode: print.id,
        toPin: 'exec',
      ),
    )
    ..connect(
      VisualScriptLink(
        fromNode: read.id,
        fromPin: 'value',
        toNode: print.id,
        toPin: 'value',
      ),
    );
  return (graph: graph, host: NullVisualScriptHost());
}

void main() {
  setUp(applicationVisualScriptVariables.clear);

  group('every scope round-trips a value within one run', () {
    for (final scope in VisualScriptVariableScope.values) {
      test(scope.label, () {
        final r = roundTrip(scope, value: 7);
        final context = VisualScriptContext(graph: r.graph, host: r.host);
        VisualScriptInterpreter(
          standardVisualScriptRegistry(),
        ).fire(context, onTick.id);
        expect(r.host.messages, ['7']);
      });
    }
  });

  group('how long each one lasts', () {
    test('a flow variable does not survive into the next event', () {
      final graph = VisualScriptGraph();
      final start = graph.add('event.start')..position.setValues(0, 0);
      final write = graph.add('var.set')
        ..literals['name'] = 'n'
        ..literals['value'] = 5
        ..literals['scope'] = 'flow';
      final tick = graph.add('event.tick');
      final read = graph.add('var.get')
        ..literals['name'] = 'n'
        ..literals['scope'] = 'flow';
      final print = graph.add('debug.print');
      graph
        ..connect(
          VisualScriptLink(
            fromNode: start.id,
            fromPin: 'then',
            toNode: write.id,
            toPin: 'exec',
          ),
        )
        ..connect(
          VisualScriptLink(
            fromNode: tick.id,
            fromPin: 'then',
            toNode: print.id,
            toPin: 'exec',
          ),
        )
        ..connect(
          VisualScriptLink(
            fromNode: read.id,
            fromPin: 'value',
            toNode: print.id,
            toPin: 'value',
          ),
        );

      final host = NullVisualScriptHost();
      final context = VisualScriptContext(graph: graph, host: host);
      final runner = VisualScriptInterpreter(standardVisualScriptRegistry())
        ..fire(context, onStart.id)
        ..fire(context, onTick.id);
      expect(host.messages, ['null'], reason: 'the flow that set it has ended');
      expect(runner, isNotNull);
    });

    test('a graph variable is shared by every graph in the blueprint', () {
      final blueprint = Blueprint(
        variables: [
          VisualScriptVariable(
            name: 'n',
            type: VisualScriptType.number,
            initial: 3.0,
          ),
        ],
      );
      final construction = VisualScriptGraph();
      final built = construction.add('event.start');
      final write = construction.add('var.set')
        ..literals['name'] = 'n'
        ..literals['value'] = 9.0;
      construction.connect(
        VisualScriptLink(
          fromNode: built.id,
          fromPin: 'then',
          toNode: write.id,
          toPin: 'exec',
        ),
      );
      blueprint.addGraph(
        construction,
        kind: VisualScriptGraphKind.constructionScript,
      );

      final events = VisualScriptGraph();
      final tick = events.add('event.tick');
      final read = events.add('var.get')..literals['name'] = 'n';
      final print = events.add('debug.print');
      events
        ..connect(
          VisualScriptLink(
            fromNode: tick.id,
            fromPin: 'then',
            toNode: print.id,
            toPin: 'exec',
          ),
        )
        ..connect(
          VisualScriptLink(
            fromNode: read.id,
            fromPin: 'value',
            toNode: print.id,
            toPin: 'value',
          ),
        );
      blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

      final host = NullVisualScriptHost();
      BlueprintRunner(blueprint: blueprint, host: host)
        ..build()
        ..fire(onTick.id);
      expect(host.messages, [
        '9.0',
      ], reason: 'construction wrote what tick read');
    });

    test('an application variable outlives the host that set it', () {
      final first = roundTrip(VisualScriptVariableScope.application, value: 12);
      VisualScriptInterpreter(standardVisualScriptRegistry()).fire(
        VisualScriptContext(graph: first.graph, host: first.host),
        onTick.id,
      );

      // A different graph and a different host: application scope is the
      // whole process, which is the entire point of it.
      final second = VisualScriptGraph();
      final tick = second.add('event.tick');
      final read = second.add('var.get')
        ..literals['name'] = 'n'
        ..literals['scope'] = 'application';
      final print = second.add('debug.print');
      second
        ..connect(
          VisualScriptLink(
            fromNode: tick.id,
            fromPin: 'then',
            toNode: print.id,
            toPin: 'exec',
          ),
        )
        ..connect(
          VisualScriptLink(
            fromNode: read.id,
            fromPin: 'value',
            toNode: print.id,
            toPin: 'value',
          ),
        );
      final host = NullVisualScriptHost();
      VisualScriptInterpreter(
        standardVisualScriptRegistry(),
      ).fire(VisualScriptContext(graph: second, host: host), onTick.id);
      expect(host.messages, ['12']);
    });

    test('an object variable does not reach a different host', () {
      final first = roundTrip(VisualScriptVariableScope.object, value: 12);
      VisualScriptInterpreter(standardVisualScriptRegistry()).fire(
        VisualScriptContext(graph: first.graph, host: first.host),
        onTick.id,
      );
      expect(
        NullVisualScriptHost().variablesIn(
          VisualScriptVariableScope.object,
        )['n'],
        isNull,
      );
    });
  });

  group('reading one that is not there', () {
    test('gives nothing, and says it was not there', () {
      final graph = VisualScriptGraph();
      final read = graph.add('var.get')..literals['name'] = 'missing';
      final context = VisualScriptContext(
        graph: graph,
        host: NullVisualScriptHost(),
      );
      final runner = VisualScriptInterpreter(standardVisualScriptRegistry());
      expect(runner.evaluateOutput(context, read.id, 'value'), isNull);
      expect(runner.evaluateOutput(context, read.id, 'found'), isFalse);
    });

    test('is distinguishable from one holding nothing', () {
      final graph = VisualScriptGraph();
      graph.variables.add(
        VisualScriptVariable(name: 'n', type: VisualScriptType.any),
      );
      final read = graph.add('var.get')..literals['name'] = 'n';
      final context = VisualScriptContext(
        graph: graph,
        host: NullVisualScriptHost(),
      );
      expect(
        VisualScriptInterpreter(
          standardVisualScriptRegistry(),
        ).evaluateOutput(context, read.id, 'found'),
        isTrue,
        reason: 'declared with a null initial is still declared',
      );
    });
  });

  group('serialization', () {
    test('a scope survives JSON and the text form', () {
      final graph = VisualScriptGraph();
      for (final scope in VisualScriptVariableScope.values) {
        graph.variables.add(
          VisualScriptVariable(
            name: scope.name,
            type: VisualScriptType.number,
            scope: scope,
            initial: 1.0,
          ),
        );
      }

      for (final restored in [
        readVisualScript(writeVisualScript(graph)),
        parseBlueprint(printBlueprint(graph)).graph,
      ]) {
        for (final scope in VisualScriptVariableScope.values) {
          expect(
            restored.variable(scope.name)?.scope,
            scope,
            reason: scope.name,
          );
        }
      }
    });

    test('a variable saved before scopes existed reads as a graph one', () {
      final restored = readVisualScript(
        '{"variables":[{"name":"n","type":"number"}]}',
      );
      expect(restored.variable('n')!.scope, VisualScriptVariableScope.graph);
    });

    test('a graph-scope variable is written the way it always was', () {
      final graph = VisualScriptGraph();
      graph.variables.add(
        VisualScriptVariable(
          name: 'speed',
          type: VisualScriptType.number,
          initial: 2.0,
        ),
      );
      expect(printBlueprint(graph), contains('var speed: number = 2'));
    });
  });

  test('renaming a variable only follows its own scope', () {
    final blueprint = Blueprint(
      variables: [
        VisualScriptVariable(name: 'n', type: VisualScriptType.number),
        VisualScriptVariable(
          name: 'n',
          type: VisualScriptType.number,
          scope: VisualScriptVariableScope.object,
        ),
      ],
    );
    final graph = VisualScriptGraph();
    final graphRead = graph.add('var.get')..literals['name'] = 'n';
    final objectRead = graph.add('var.get')
      ..literals['name'] = 'n'
      ..literals['scope'] = 'object';
    blueprint.addGraph(graph, kind: VisualScriptGraphKind.eventGraph);

    expect(blueprint.renameVariable('n', 'count'), isTrue);
    expect(graphRead.literals['name'], 'count');
    expect(
      objectRead.literals['name'],
      'n',
      reason: 'a different scope is a different variable',
    );
  });
}
