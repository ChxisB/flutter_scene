// The control nodes: loops that run their own body, a Try that catches a
// Throw, and the nodes whose shape comes from what was typed into them.

import 'package:scene/visual_script.dart';
import 'package:test/test.dart';

/// A graph, a host to watch, and an interpreter to run it.
({
  VisualScriptGraph graph,
  NullVisualScriptHost host,
  VisualScriptInterpreter runner,
})
rig() => (
  graph: VisualScriptGraph(),
  host: NullVisualScriptHost(),
  runner: VisualScriptInterpreter(standardVisualScriptRegistry()),
);

extension on VisualScriptGraph {
  /// Wires [fromPin] on [from] to [toPin] on [to].
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

void main() {
  group('loops', () {
    test('a For Loop runs its body once per index, then continues', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final loop = r.graph.add('flow.forLoop')
        ..literals['first'] = 0
        ..literals['last'] = 3;
      final body = r.graph.add('debug.print')..literals['label'] = 'body';
      final done = r.graph.add('debug.print')..literals['value'] = 'done';
      r.graph
        ..wire(start, 'then', loop, 'exec')
        ..wire(loop, 'body', body, 'exec')
        ..wire(loop, 'index', body, 'value')
        ..wire(loop, 'completed', done, 'exec');

      final context = VisualScriptContext(graph: r.graph, host: r.host);
      r.runner.fire(context, onStart.id);
      expect(r.host.messages, ['body: 0', 'body: 1', 'body: 2', 'done']);
      expect(context.error, isNull);
    });

    test('a For Loop counts down when its step is negative', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final loop = r.graph.add('flow.forLoop')
        ..literals['first'] = 3
        ..literals['last'] = 0
        ..literals['step'] = -1;
      final body = r.graph.add('debug.print')..literals['label'] = 'n';
      r.graph
        ..wire(start, 'then', loop, 'exec')
        ..wire(loop, 'body', body, 'exec')
        ..wire(loop, 'index', body, 'value');

      r.runner.fire(
        VisualScriptContext(graph: r.graph, host: r.host),
        onStart.id,
      );
      expect(r.host.messages, ['n: 3', 'n: 2', 'n: 1']);
    });

    test('a For Loop with a zero step refuses rather than spinning', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final loop = r.graph.add('flow.forLoop')..literals['step'] = 0;
      r.graph.wire(start, 'then', loop, 'exec');

      final context = VisualScriptContext(graph: r.graph, host: r.host);
      r.runner.fire(context, onStart.id);
      expect(context.error, contains('Step of zero'));
    });

    test('Break leaves the loop and takes the Completed path', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final loop = r.graph.add('flow.forLoop')
        ..literals['first'] = 0
        ..literals['last'] = 5;
      final body = r.graph.add('debug.print')..literals['value'] = 'x';
      final stop = r.graph.add('flow.break');
      final done = r.graph.add('debug.print')..literals['value'] = 'done';
      r.graph
        ..wire(start, 'then', loop, 'exec')
        ..wire(loop, 'body', body, 'exec')
        ..wire(body, 'then', stop, 'exec')
        ..wire(loop, 'completed', done, 'exec');

      final context = VisualScriptContext(graph: r.graph, host: r.host);
      r.runner.fire(context, onStart.id);
      expect(r.host.messages, ['x', 'done'], reason: 'one pass, then out');
      expect(context.signal, isNull, reason: 'the loop swallowed the Break');
    });

    test('a For Each walks the collection it was given', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final loop = r.graph.add('flow.forEach')
        ..literals['collection'] = <Object?>['a', 'b'];
      final body = r.graph.add('debug.print')..literals['label'] = 'item';
      r.graph
        ..wire(start, 'then', loop, 'exec')
        ..wire(loop, 'body', body, 'exec')
        ..wire(loop, 'item', body, 'value');

      r.runner.fire(
        VisualScriptContext(graph: r.graph, host: r.host),
        onStart.id,
      );
      expect(r.host.messages, ['item: a', 'item: b']);
    });

    test('a While Loop re-reads its condition each time round', () {
      // Without re-pulling, the condition resolved before the body ran and
      // the loop would never end.
      final r = rig();
      r.graph.variables.add(
        VisualScriptVariable(
          name: 'n',
          type: VisualScriptType.number,
          initial: 0.0,
        ),
      );
      final start = r.graph.add('event.start');
      final loop = r.graph.add('flow.whileLoop');
      final read = r.graph.add('var.get')..literals['name'] = 'n';
      final under = r.graph.add('logic.less')..literals['b'] = 3.0;
      final add = r.graph.add('math.add')..literals['b'] = 1.0;
      final write = r.graph.add('var.set')..literals['name'] = 'n';
      final readAgain = r.graph.add('var.get')..literals['name'] = 'n';
      r.graph
        ..wire(start, 'then', loop, 'exec')
        ..wire(read, 'value', under, 'a')
        ..wire(under, 'value', loop, 'condition')
        ..wire(loop, 'body', write, 'exec')
        ..wire(readAgain, 'value', add, 'a')
        ..wire(add, 'value', write, 'value');

      final context = VisualScriptContext(graph: r.graph, host: r.host);
      r.runner.fire(context, onStart.id);
      expect(context.error, isNull);
      expect(context.variables['n'], 3.0);
    });

    test('a runaway While Loop stops and says so', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final loop = r.graph.add('flow.whileLoop')..literals['condition'] = true;
      final body = r.graph.add('debug.print')..literals['value'] = 'x';
      r.graph
        ..wire(start, 'then', loop, 'exec')
        ..wire(loop, 'body', body, 'exec');

      final context = VisualScriptContext(graph: r.graph, host: r.host);
      r.runner.fire(context, onStart.id);
      expect(context.error, isNotNull);
    });
  });

  group('exceptions', () {
    test('a Try catches a Throw and takes its Catch path', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final guard = r.graph.add('flow.tryCatch');
      final boom = r.graph.add('flow.throw')..literals['message'] = 'nope';
      final never = r.graph.add('debug.print')..literals['value'] = 'never';
      final caught = r.graph.add('debug.print')..literals['label'] = 'caught';
      final after = r.graph.add('debug.print')..literals['value'] = 'finally';
      r.graph
        ..wire(start, 'then', guard, 'exec')
        ..wire(guard, 'try', boom, 'exec')
        ..wire(boom, 'exec', never, 'exec')
        ..wire(guard, 'catch', caught, 'exec')
        ..wire(guard, 'message', caught, 'value')
        ..wire(guard, 'finally', after, 'exec');

      final context = VisualScriptContext(graph: r.graph, host: r.host);
      r.runner.fire(context, onStart.id);
      expect(r.host.messages, ['caught: nope', 'finally']);
      expect(context.error, isNull, reason: 'a caught Throw is not an error');
    });

    test('a Try that throws nothing runs Try and then Finally', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final guard = r.graph.add('flow.tryCatch');
      final ok = r.graph.add('debug.print')..literals['value'] = 'ok';
      final after = r.graph.add('debug.print')..literals['value'] = 'finally';
      r.graph
        ..wire(start, 'then', guard, 'exec')
        ..wire(guard, 'try', ok, 'exec')
        ..wire(guard, 'finally', after, 'exec');

      r.runner.fire(
        VisualScriptContext(graph: r.graph, host: r.host),
        onStart.id,
      );
      expect(r.host.messages, ['ok', 'finally']);
    });

    test('an uncaught Throw becomes the run\'s error', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final boom = r.graph.add('flow.throw')..literals['message'] = 'nope';
      r.graph.wire(start, 'then', boom, 'exec');

      final context = VisualScriptContext(graph: r.graph, host: r.host);
      r.runner.fire(context, onStart.id);
      expect(context.error, 'nope');
      expect(context.signal, isNull, reason: 'it stopped being control flow');
    });
  });

  group('nodes whose shape comes from the node', () {
    test('a Switch grows a pin per case and takes the matching one', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final pick = r.graph.add('flow.switchString')
        ..literals['cases'] = <Object?>['red', 'green']
        ..literals['selector'] = 'green';
      final red = r.graph.add('debug.print')..literals['value'] = 'red';
      final green = r.graph.add('debug.print')..literals['value'] = 'green';
      final other = r.graph.add('debug.print')..literals['value'] = 'other';
      r.graph
        ..wire(start, 'then', pick, 'exec')
        ..wire(pick, casePin(0), red, 'exec')
        ..wire(pick, casePin(1), green, 'exec')
        ..wire(pick, 'default', other, 'exec');

      final type = standardVisualScriptRegistry()['flow.switchString']!;
      expect(type.outputsOf(pick).map((pin) => pin.id), [
        'case_0',
        'case_1',
        'default',
      ]);
      r.runner.fire(
        VisualScriptContext(graph: r.graph, host: r.host),
        onStart.id,
      );
      expect(r.host.messages, ['green']);
    });

    test('a Switch with no matching case takes Default', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final pick = r.graph.add('flow.switchString')
        ..literals['cases'] = <Object?>['red']
        ..literals['selector'] = 'blue';
      final other = r.graph.add('debug.print')..literals['value'] = 'other';
      r.graph
        ..wire(start, 'then', pick, 'exec')
        ..wire(pick, 'default', other, 'exec');

      r.runner.fire(
        VisualScriptContext(graph: r.graph, host: r.host),
        onStart.id,
      );
      expect(r.host.messages, ['other']);
    });

    test('a Sequence still has a, b and c when nothing set a count', () {
      // Every Sequence saved before the count existed relies on this.
      final r = rig();
      final node = r.graph.add('flow.sequence');
      final type = standardVisualScriptRegistry()['flow.sequence']!;
      expect(type.outputsOf(node).map((pin) => pin.id), ['a', 'b', 'c']);
    });

    test('a Sequence given a count has that many outputs, in order', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final steps = r.graph.add('flow.sequence')..literals['count'] = 4;
      r.graph.wire(start, 'then', steps, 'exec');
      for (var i = 0; i < 4; i++) {
        final print = r.graph.add('debug.print')..literals['value'] = '$i';
        r.graph.wire(steps, sequencePin(i), print, 'exec');
      }

      r.runner.fire(
        VisualScriptContext(graph: r.graph, host: r.host),
        onStart.id,
      );
      expect(r.host.messages, ['0', '1', '2', '3']);
    });
  });

  group('gates and values', () {
    test('Once takes Once first and After afterwards', () {
      final r = rig();
      final tick = r.graph.add('event.tick');
      final gate = r.graph.add('flow.once');
      final first = r.graph.add('debug.print')..literals['value'] = 'first';
      final rest = r.graph.add('debug.print')..literals['value'] = 'rest';
      r.graph
        ..wire(tick, 'then', gate, 'exec')
        ..wire(gate, 'once', first, 'exec')
        ..wire(gate, 'after', rest, 'exec');

      final context = VisualScriptContext(graph: r.graph, host: r.host);
      r.runner
        ..fire(context, onTick.id)
        ..fire(context, onTick.id)
        ..fire(context, onTick.id);
      expect(r.host.messages, ['first', 'rest', 'rest']);
    });

    test('Toggle Flow passes On or Off, and its setters change which', () {
      final r = rig();
      final tick = r.graph.add('event.tick');
      final flip = r.graph.add('flow.toggleFlow');
      final on = r.graph.add('debug.print')..literals['value'] = 'on';
      final off = r.graph.add('debug.print')..literals['value'] = 'off';
      r.graph
        ..wire(tick, 'then', flip, 'exec')
        ..wire(flip, 'on', on, 'exec')
        ..wire(flip, 'off', off, 'exec');

      final context = VisualScriptContext(graph: r.graph, host: r.host);
      r.runner.fire(context, onTick.id);
      expect(r.host.messages, ['off'], reason: 'it starts off');

      // Enter through Turn On instead, then through Enter again.
      final turnOn = r.graph.add('event.signal');
      r.graph.wire(turnOn, 'then', flip, 'turnOn');
      r.runner
        ..fire(context, onSignal.id)
        ..fire(context, onTick.id);
      expect(r.host.messages, ['off', 'on']);
    });

    test('Null Coalesce falls back only when there is nothing', () {
      final r = rig();
      final pick = r.graph.add('flow.nullCoalesce')
        ..literals['fallback'] = 'fallback';
      final context = VisualScriptContext(graph: r.graph, host: r.host);
      expect(r.runner.evaluateOutput(context, pick.id, 'result'), 'fallback');

      pick.literals['value'] = 'present';
      expect(r.runner.evaluateOutput(context, pick.id, 'result'), 'present');
    });

    test('Select gives back the value whose case matches', () {
      final r = rig();
      final pick = r.graph.add('flow.select')
        ..literals['cases'] = <Object?>['a', 'b']
        ..literals['selector'] = 'b'
        ..literals[casePin(0)] = 1
        ..literals[casePin(1)] = 2
        ..literals['default'] = 0;
      final context = VisualScriptContext(graph: r.graph, host: r.host);
      expect(r.runner.evaluateOutput(context, pick.id, 'value'), 2);
    });
  });

  group('what an exec node produces', () {
    test('reading an exec node twice does not run it twice', () {
      // Play Animation asked for Found must not play the animation again.
      final r = rig();
      final start = r.graph.add('event.start');
      final call = r.graph.add('scene.call');
      final a = r.graph.add('debug.print')..literals['label'] = 'a';
      final b = r.graph.add('debug.print')..literals['label'] = 'b';
      r.graph
        ..wire(start, 'then', call, 'exec')
        ..wire(call, 'then', a, 'exec')
        ..wire(a, 'then', b, 'exec')
        ..wire(call, 'result', a, 'value')
        ..wire(call, 'result', b, 'value');

      final runner = VisualScriptInterpreter(
        standardVisualScriptRegistry()..register(_countingCall),
      );
      runner.fire(
        VisualScriptContext(graph: r.graph, host: r.host),
        onStart.id,
      );
      expect(_calls, 1, reason: 'it ran once, and both reads saw that run');
    });
  });
}

var _calls = 0;

/// Stands in for a node that does something when it runs and reports on it.
final VisualScriptNodeType _countingCall = VisualScriptNodeType(
  id: 'scene.call',
  label: 'Counting Call',
  category: 'Debug',
  pins: const [
    VisualScriptPin(id: 'exec', label: '', type: VisualScriptType.exec),
    VisualScriptPin(
      id: 'then',
      label: '',
      type: VisualScriptType.exec,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'result',
      label: 'Result',
      type: VisualScriptType.any,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) {
    _calls++;
    return (outputs: {'result': _calls}, next: const <String>['then']);
  },
);
