// Calling one graph from another: parameters in, results out, and the
// difference between a function and a macro.

import 'package:scene/visual_script.dart';
import 'package:test/test.dart';

extension on VisualScriptGraph {
  void wire(
    VisualScriptNodeSpec from,
    String fromPin,
    VisualScriptNodeSpec to,
    String toPin,
  ) => connect(
    VisualScriptLink(
      fromNode: from.id,
      fromPin: fromPin,
      toNode: to.id,
      toPin: toPin,
    ),
  );
}

/// A graph that doubles its `n` parameter into its `out` result.
VisualScriptGraph doubler({
  VisualScriptGraphKind kind = VisualScriptGraphKind.function,
  bool isPure = false,
}) {
  final graph = VisualScriptGraph(
    name: 'Double',
    kind: kind,
    isPure: isPure,
    parameters: [
      const VisualScriptParameter(
        id: 'n',
        name: 'N',
        type: VisualScriptType.number,
      ),
    ],
    results: [
      const VisualScriptParameter(
        id: 'out',
        name: 'Out',
        type: VisualScriptType.number,
      ),
    ],
  );
  final entry = graph.add('function.entry');
  final times = graph.add('math.multiply')..literals['b'] = 2.0;
  final back = graph.add('function.result');
  // Purity is about the *call* node's pins, not the graph's insides: even a
  // pure function walks from its entry to its return.
  graph
    ..wire(entry, 'n', times, 'a')
    ..wire(times, 'value', back, 'out')
    ..wire(entry, 'then', back, 'exec');
  return graph;
}

/// Runs [blueprint]'s event graph once and returns what Print saw.
List<String> run(Blueprint blueprint) {
  final host = NullVisualScriptHost();
  BlueprintRunner(blueprint: blueprint, host: host).fire(onTick.id);
  return host.messages;
}

void main() {
  group('a function', () {
    test('takes an argument and hands a value back', () {
      final blueprint = Blueprint()..graphs.add(doubler());
      final events = VisualScriptGraph(name: 'Events');
      final tick = events.add('event.tick');
      final call = events.add('function.call')
        ..literals[calledGraphKey] = 'Double'
        ..literals['n'] = 21.0;
      final print = events.add('debug.print');
      events
        ..wire(tick, 'then', call, 'exec')
        ..wire(call, 'then', print, 'exec')
        ..wire(call, 'out', print, 'value');
      blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

      expect(run(blueprint), ['42.0']);
    });

    test('its call node grows the pins of the graph it names', () {
      final blueprint = Blueprint()..graphs.add(doubler());
      final events = VisualScriptGraph();
      final call = events.add('function.call')
        ..literals[calledGraphKey] = 'Double';
      final type = standardVisualScriptRegistry()['function.call']!;
      final shape = VisualScriptShapeContext(
        graph: events,
        graphs: blueprint.graph,
      );
      expect(type.inputsOf(call, shape).map((p) => p.id), ['exec', 'n']);
      expect(type.outputsOf(call, shape).map((p) => p.id), ['then', 'out']);
    });

    test('a call to nothing says so rather than doing nothing quietly', () {
      final blueprint = Blueprint();
      final events = VisualScriptGraph();
      final tick = events.add('event.tick');
      final call = events.add('function.call')
        ..literals[calledGraphKey] = 'Missing';
      events.wire(tick, 'then', call, 'exec');
      blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

      final runner = BlueprintRunner(
        blueprint: blueprint,
        host: NullVisualScriptHost(),
      )..fire(onTick.id);
      expect(runner.error, contains('Missing'));
    });

    test('is entered again for a second call, with fresh locals', () {
      // A Local variable is a scratch pad for one call. If the second call
      // saw the first one's value, it would not be one.
      final counter = VisualScriptGraph(
        name: 'Count',
        kind: VisualScriptGraphKind.function,
        results: [
          const VisualScriptParameter(
            id: 'out',
            name: 'Out',
            type: VisualScriptType.number,
          ),
        ],
        variables: [
          VisualScriptVariable(
            name: 'seen',
            type: VisualScriptType.number,
            scope: VisualScriptVariableScope.local,
            initial: 0.0,
          ),
        ],
      );
      final entry = counter.add('function.entry');
      final read = counter.add('var.get')
        ..literals['name'] = 'seen'
        ..literals['scope'] = 'local';
      final add = counter.add('math.add')..literals['b'] = 1.0;
      final write = counter.add('var.set')
        ..literals['name'] = 'seen'
        ..literals['scope'] = 'local';
      final back = counter.add('function.result');
      counter
        ..wire(entry, 'then', write, 'exec')
        ..wire(read, 'value', add, 'a')
        ..wire(add, 'value', write, 'value')
        ..wire(write, 'then', back, 'exec')
        ..wire(write, 'out', back, 'out');

      final blueprint = Blueprint()..graphs.add(counter);
      final events = VisualScriptGraph();
      final tick = events.add('event.tick');
      final first = events.add('function.call')
        ..literals[calledGraphKey] = 'Count';
      final second = events.add('function.call')
        ..literals[calledGraphKey] = 'Count';
      final printA = events.add('debug.print');
      final printB = events.add('debug.print');
      events
        ..wire(tick, 'then', first, 'exec')
        ..wire(first, 'then', printA, 'exec')
        ..wire(first, 'out', printA, 'value')
        ..wire(printA, 'then', second, 'exec')
        ..wire(second, 'then', printB, 'exec')
        ..wire(second, 'out', printB, 'value');
      blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

      expect(run(blueprint), [
        '1.0',
        '1.0',
      ], reason: 'each call starts its locals over');
    });

    test('a Graph variable, by contrast, is shared across calls', () {
      final blueprint = Blueprint(
        variables: [
          VisualScriptVariable(
            name: 'total',
            type: VisualScriptType.number,
            initial: 0.0,
          ),
        ],
      );
      final adder = VisualScriptGraph(
        name: 'Bump',
        kind: VisualScriptGraphKind.function,
        results: [
          const VisualScriptParameter(
            id: 'out',
            name: 'Out',
            type: VisualScriptType.number,
          ),
        ],
      );
      final entry = adder.add('function.entry');
      final read = adder.add('var.get')..literals['name'] = 'total';
      final add = adder.add('math.add')..literals['b'] = 1.0;
      final write = adder.add('var.set')..literals['name'] = 'total';
      final back = adder.add('function.result');
      adder
        ..wire(entry, 'then', write, 'exec')
        ..wire(read, 'value', add, 'a')
        ..wire(add, 'value', write, 'value')
        ..wire(write, 'then', back, 'exec')
        ..wire(write, 'out', back, 'out');
      blueprint.graphs.add(adder);

      final events = VisualScriptGraph();
      final tick = events.add('event.tick');
      final first = events.add('function.call')
        ..literals[calledGraphKey] = 'Bump';
      final second = events.add('function.call')
        ..literals[calledGraphKey] = 'Bump';
      final print = events.add('debug.print');
      events
        ..wire(tick, 'then', first, 'exec')
        ..wire(first, 'then', second, 'exec')
        ..wire(second, 'then', print, 'exec')
        ..wire(second, 'out', print, 'value');
      blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

      expect(run(blueprint), ['2.0']);
    });
  });

  group('a pure function', () {
    test('has no exec pins, and runs when its result is read', () {
      final blueprint = Blueprint()..graphs.add(doubler(isPure: true));
      final events = VisualScriptGraph();
      final tick = events.add('event.tick');
      final call = events.add('function.call')
        ..literals[calledGraphKey] = 'Double'
        ..literals['n'] = 4.0;
      final print = events.add('debug.print');
      events
        ..wire(tick, 'then', print, 'exec')
        ..wire(call, 'out', print, 'value');
      blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

      final type = standardVisualScriptRegistry()['function.call']!;
      final shape = VisualScriptShapeContext(
        graph: events,
        graphs: blueprint.graph,
      );
      expect(
        type.pinsOf(call, shape).map((p) => p.type),
        isNot(contains(VisualScriptType.exec)),
      );
      expect(run(blueprint), ['8.0']);
    });
  });

  group('a macro', () {
    test('shares the caller\'s Local variables, where a function does not', () {
      // The distinction that makes a macro a macro: it is pasted in, so a
      // Local it writes is the caller's Local.
      final macro = VisualScriptGraph(
        name: 'Stamp',
        kind: VisualScriptGraphKind.macro,
      );
      final entry = macro.add('function.entry');
      final write = macro.add('var.set')
        ..literals['name'] = 'mark'
        ..literals['scope'] = 'flow'
        ..literals['value'] = 'was here';
      macro.wire(entry, 'then', write, 'exec');

      final blueprint = Blueprint()..graphs.add(macro);
      final events = VisualScriptGraph();
      final tick = events.add('event.tick');
      final call = events.add('function.call')
        ..literals[calledGraphKey] = 'Stamp';
      final read = events.add('var.get')
        ..literals['name'] = 'mark'
        ..literals['scope'] = 'flow';
      final print = events.add('debug.print');
      events
        ..wire(tick, 'then', call, 'exec')
        ..wire(call, 'then', print, 'exec')
        ..wire(read, 'value', print, 'value');
      blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

      expect(run(blueprint), ['was here']);
    });
  });

  group('guards', () {
    test('a function that calls itself is stopped by the depth limit', () {
      final loop = VisualScriptGraph(
        name: 'Forever',
        kind: VisualScriptGraphKind.function,
      );
      final entry = loop.add('function.entry');
      final again = loop.add('function.call')
        ..literals[calledGraphKey] = 'Forever';
      loop.wire(entry, 'then', again, 'exec');

      final blueprint = Blueprint()..graphs.add(loop);
      final events = VisualScriptGraph();
      final tick = events.add('event.tick');
      final call = events.add('function.call')
        ..literals[calledGraphKey] = 'Forever';
      events.wire(tick, 'then', call, 'exec');
      blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

      final runner = BlueprintRunner(
        blueprint: blueprint,
        host: NullVisualScriptHost(),
      )..fire(onTick.id);
      expect(runner.error, contains('deep'));
    });

    test('a graph with no entry node runs nothing and is not an error', () {
      final empty = VisualScriptGraph(
        name: 'Empty',
        kind: VisualScriptGraphKind.function,
      );
      final blueprint = Blueprint()..graphs.add(empty);
      final events = VisualScriptGraph();
      final tick = events.add('event.tick');
      final call = events.add('function.call')
        ..literals[calledGraphKey] = 'Empty';
      final print = events.add('debug.print')..literals['value'] = 'after';
      events
        ..wire(tick, 'then', call, 'exec')
        ..wire(call, 'then', print, 'exec');
      blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

      final host = NullVisualScriptHost();
      final runner = BlueprintRunner(blueprint: blueprint, host: host)
        ..fire(onTick.id);
      expect(runner.error, isNull);
      expect(host.messages, ['after']);
    });
  });

  group('a custom event', () {
    Blueprint withEvent() => Blueprint(
      events: [
        VisualScriptEventSpec(
          name: 'Damaged',
          parameters: [
            const VisualScriptParameter(
              id: 'amount',
              name: 'Amount',
              type: VisualScriptType.number,
            ),
          ],
        ),
      ],
    );

    test('carries its arguments from the call to the listener', () {
      final blueprint = withEvent();
      final events = VisualScriptGraph();
      final tick = events.add('event.tick');
      final call = events.add('flow.callEvent')
        ..literals[namedEventKey] = 'Damaged'
        ..literals['amount'] = 30.0;
      final listener = events.add('event.custom')
        ..literals[namedEventKey] = 'Damaged';
      final print = events.add('debug.print')..literals['label'] = 'hit';
      events
        ..wire(tick, 'then', call, 'exec')
        ..wire(listener, 'then', print, 'exec')
        ..wire(listener, 'amount', print, 'value');
      blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

      expect(run(blueprint), ['hit: 30.0']);
    });

    test('runs before the caller continues', () {
      final blueprint = withEvent();
      final events = VisualScriptGraph();
      final tick = events.add('event.tick');
      final call = events.add('flow.callEvent')
        ..literals[namedEventKey] = 'Damaged';
      final after = events.add('debug.print')..literals['value'] = 'after';
      final listener = events.add('event.custom')
        ..literals[namedEventKey] = 'Damaged';
      final during = events.add('debug.print')..literals['value'] = 'during';
      events
        ..wire(tick, 'then', call, 'exec')
        ..wire(call, 'then', after, 'exec')
        ..wire(listener, 'then', during, 'exec');
      blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

      expect(run(blueprint), [
        'during',
        'after',
      ], reason: 'a call that queued would not be a call');
    });

    test('reaches every listener of that name, and no others', () {
      final blueprint = withEvent()
        ..events.add(VisualScriptEventSpec(name: 'Healed'));
      final events = VisualScriptGraph();
      final tick = events.add('event.tick');
      final call = events.add('flow.callEvent')
        ..literals[namedEventKey] = 'Damaged';
      for (final (name, message) in [
        ('Damaged', 'one'),
        ('Damaged', 'two'),
        ('Healed', 'other'),
      ]) {
        final listener = events.add('event.custom')
          ..literals[namedEventKey] = name;
        final print = events.add('debug.print')..literals['value'] = message;
        events.wire(listener, 'then', print, 'exec');
      }
      events.wire(tick, 'then', call, 'exec');
      blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

      expect(run(blueprint), ['one', 'two']);
    });

    test('its pins are the parameters the blueprint declared', () {
      final blueprint = withEvent();
      final events = VisualScriptGraph();
      final call = events.add('flow.callEvent')
        ..literals[namedEventKey] = 'Damaged';
      final listener = events.add('event.custom')
        ..literals[namedEventKey] = 'Damaged';
      final registry = standardVisualScriptRegistry();
      final shape = VisualScriptShapeContext(
        graph: events,
        graphs: blueprint.graph,
        events: blueprint.event,
      );
      expect(
        registry['flow.callEvent']!.inputsOf(call, shape).map((p) => p.id),
        ['exec', 'amount'],
      );
      expect(
        registry['event.custom']!.outputsOf(listener, shape).map((p) => p.id),
        ['then', 'amount'],
      );
    });

    test('calling one nothing listens for is not an error', () {
      final blueprint = withEvent();
      final events = VisualScriptGraph();
      final tick = events.add('event.tick');
      final call = events.add('flow.callEvent')
        ..literals[namedEventKey] = 'Damaged';
      final after = events.add('debug.print')..literals['value'] = 'after';
      events
        ..wire(tick, 'then', call, 'exec')
        ..wire(call, 'then', after, 'exec');
      blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

      final host = NullVisualScriptHost();
      final runner = BlueprintRunner(blueprint: blueprint, host: host)
        ..fire(onTick.id);
      expect(runner.error, isNull);
      expect(host.messages, ['after']);
    });

    test('an event that calls itself is stopped by the depth limit', () {
      final blueprint = withEvent();
      final events = VisualScriptGraph();
      final tick = events.add('event.tick');
      final call = events.add('flow.callEvent')
        ..literals[namedEventKey] = 'Damaged';
      final listener = events.add('event.custom')
        ..literals[namedEventKey] = 'Damaged';
      final again = events.add('flow.callEvent')
        ..literals[namedEventKey] = 'Damaged';
      events
        ..wire(tick, 'then', call, 'exec')
        ..wire(listener, 'then', again, 'exec');
      blueprint.addGraph(events, kind: VisualScriptGraphKind.eventGraph);

      final runner = BlueprintRunner(
        blueprint: blueprint,
        host: NullVisualScriptHost(),
      )..fire(onTick.id);
      expect(runner.error, isNotNull);
    });

    test('its declaration survives being saved', () {
      final after = readBlueprint(writeBlueprint(withEvent()));
      expect(after.event('Damaged')!.parameters.single.name, 'Amount');
    });
  });

  group('the signature survives being saved', () {
    test('parameters and results round-trip through JSON', () {
      final blueprint = Blueprint()..graphs.add(doubler(isPure: true));
      final after = readBlueprint(writeBlueprint(blueprint));
      final graph = after.graph('Double')!;
      expect(graph.isPure, isTrue);
      expect(graph.parameters.single.id, 'n');
      expect(graph.parameters.single.type, VisualScriptType.number);
      expect(graph.results.single.name, 'Out');
    });
  });
}
