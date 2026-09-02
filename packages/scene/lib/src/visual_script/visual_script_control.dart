/// The control nodes: the ones that branch, loop, merge, and decide.
///
/// These are the node types that need to run a flow and then look at how it
/// ended, which is what [VisualScriptFlow] is for. A Branch can be written
/// without it — it names an output and the interpreter walks there. A For Each
/// cannot: it has to run its body, find out whether the body broke out, and
/// only then decide whether there is another iteration.
///
/// Several of them have a shape that depends on the node rather than the type
/// — a Switch has an output per case, a Sequence as many as it was given — and
/// those declare `pinsFor` instead of a fixed pin list.
library;

import 'visual_script_graph.dart';
import 'visual_script_runtime.dart';

const VisualScriptPin _execIn = VisualScriptPin(
  id: 'exec',
  label: '',
  type: VisualScriptType.exec,
);
const VisualScriptPin _execOut = VisualScriptPin(
  id: 'then',
  label: '',
  type: VisualScriptType.exec,
  isInput: false,
);

VisualScriptResult _then([String pin = 'then']) =>
    (outputs: const <String, Object?>{}, next: <String>[pin]);
VisualScriptResult _stop() =>
    (outputs: const <String, Object?>{}, next: const <String>[]);
VisualScriptResult _out(Map<String, Object?> outputs) =>
    (outputs: outputs, next: const <String>[]);

VisualScriptPin _exec(String id, String label, {bool isInput = false}) =>
    VisualScriptPin(
      id: id,
      label: label,
      type: VisualScriptType.exec,
      isInput: isInput,
    );

/// Runs [pin]'s wire and reports whether the caller should keep going.
///
/// Collapses the three ways a nested run can end into the one question a loop
/// body asks: a Break is swallowed here and stops the loop, an error or a
/// Throw keeps travelling, and completing means go round again.
bool _bodyContinues(
  VisualScriptContext context,
  VisualScriptNodeSpec node,
  String pin,
) {
  final flow = context.flow;
  if (flow == null) return false;
  final status = flow.runPin(context, node, pin);
  if (status == VisualScriptFlowStatus.broke) {
    context.signal = null;
    return false;
  }
  return status == VisualScriptFlowStatus.completed;
}

/// Whether a run that ended this way should stop the node that started it.
bool _unwinding(VisualScriptContext context) =>
    context.signal != null || context.error != null;

// ---------------------------------------------------------------------------
// Loops.
// ---------------------------------------------------------------------------

/// The number of iterations a single loop node may take in one tick.
///
/// Separate from the step budget, and much smaller than it: a loop that has
/// gone this far round is a mistake in the condition, and saying so names the
/// node rather than blaming the whole graph.
const int maxLoopIterations = 100000;

final VisualScriptNodeType forLoop = VisualScriptNodeType(
  id: 'flow.forLoop',
  label: 'For Loop',
  category: 'Flow Control',
  doc:
      'Runs Body once for each number from First up to but not including '
      'Last, then continues from Completed.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'first',
      label: 'First',
      type: VisualScriptType.integer,
      defaultValue: 0,
    ),
    VisualScriptPin(
      id: 'last',
      label: 'Last',
      type: VisualScriptType.integer,
      defaultValue: 10,
    ),
    VisualScriptPin(
      id: 'step',
      label: 'Step',
      type: VisualScriptType.integer,
      defaultValue: 1,
      doc: 'How much the index moves each time. Negative counts down.',
    ),
    VisualScriptPin(
      id: 'body',
      label: 'Body',
      type: VisualScriptType.exec,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'index',
      label: 'Index',
      type: VisualScriptType.integer,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'completed',
      label: 'Completed',
      type: VisualScriptType.exec,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) {
    final first = scriptInteger(inputs['first']);
    final last = scriptInteger(inputs['last']);
    final step = scriptInteger(inputs['step'], 1);
    // A zero step is an infinite loop written by accident. Refusing to run is
    // kinder than running until the budget notices.
    if (step == 0) {
      context.signal = const VisualScriptThrow(
        'A For Loop with a Step of zero would never reach Last.',
      );
      return _stop();
    }
    var index = first;
    var iterations = 0;
    while (step > 0 ? index < last : index > last) {
      if (++iterations > maxLoopIterations) {
        context.error =
            'A For Loop ran $maxLoopIterations times in one tick, which is '
            'further than First, Last and Step were meant to reach.';
        return _stop();
      }
      // Published before the body runs, so a node reading Index sees the
      // iteration it is on.
      context.execOutputs[node.id] = {'index': index};
      if (!_bodyContinues(context, node, 'body')) {
        return _unwinding(context) ? _stop() : _then('completed');
      }
      index += step;
    }
    return (outputs: {'index': index}, next: const <String>['completed']);
  },
);

final VisualScriptNodeType whileLoop = VisualScriptNodeType(
  id: 'flow.whileLoop',
  label: 'While Loop',
  category: 'Flow Control',
  doc:
      'Runs Body for as long as Condition stays true, re-reading it each '
      'time round, then continues from Completed.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'condition',
      label: 'Condition',
      type: VisualScriptType.boolean,
      defaultValue: false,
    ),
    VisualScriptPin(
      id: 'body',
      label: 'Body',
      type: VisualScriptType.exec,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'completed',
      label: 'Completed',
      type: VisualScriptType.exec,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) {
    final flow = context.flow;
    if (flow == null) return _stop();
    // The condition is re-pulled rather than read from `inputs`: the value
    // handed in was resolved once, before the body ran, and a while loop that
    // could not see the body change its own condition would never end.
    final link = context.graph.inputTo(node.id, 'condition');
    bool condition() => link == null
        ? scriptBool(inputs['condition'])
        : scriptBool(flow.pull(context, link.fromNode, link.fromPin));

    var iterations = 0;
    while (condition()) {
      if (++iterations > maxLoopIterations) {
        context.error =
            'A While Loop ran $maxLoopIterations times in one tick without '
            'its condition becoming false.';
        return _stop();
      }
      if (!_bodyContinues(context, node, 'body')) break;
      if (_unwinding(context)) return _stop();
    }
    return _unwinding(context) ? _stop() : _then('completed');
  },
);

final VisualScriptNodeType forEachLoop = VisualScriptNodeType(
  id: 'flow.forEach',
  label: 'For Each',
  category: 'Flow Control',
  doc:
      'Runs Body once for each item in Collection, then continues from '
      'Completed.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'collection',
      label: 'Collection',
      type: VisualScriptType.list,
    ),
    VisualScriptPin(
      id: 'body',
      label: 'Body',
      type: VisualScriptType.exec,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'index',
      label: 'Index',
      type: VisualScriptType.integer,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'item',
      label: 'Item',
      type: VisualScriptType.any,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'completed',
      label: 'Completed',
      type: VisualScriptType.exec,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) {
    // Copied, so a body that adds to the collection it is walking iterates
    // what was there when it started rather than looping forever.
    final items = List<Object?>.of(scriptList(inputs['collection']));
    for (var i = 0; i < items.length; i++) {
      context.execOutputs[node.id] = {'index': i, 'item': items[i]};
      if (!_bodyContinues(context, node, 'body')) {
        return _unwinding(context) ? _stop() : _then('completed');
      }
    }
    return (
      outputs: {'index': items.length, 'item': null},
      next: const <String>['completed'],
    );
  },
);

final VisualScriptNodeType breakLoop = VisualScriptNodeType(
  id: 'flow.break',
  label: 'Break',
  category: 'Flow Control',
  doc: 'Leaves the loop that is running, and continues after it.',
  pins: const [_execIn],
  evaluate: (context, node, inputs) {
    context.signal = const VisualScriptBreak();
    return _stop();
  },
);

// ---------------------------------------------------------------------------
// Exceptions.
// ---------------------------------------------------------------------------

final VisualScriptNodeType tryCatch = VisualScriptNodeType(
  id: 'flow.tryCatch',
  label: 'Try Catch',
  category: 'Flow Control',
  doc:
      'Runs Try. If something in it throws, runs Catch with the message '
      'instead. Finally runs either way.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'try',
      label: 'Try',
      type: VisualScriptType.exec,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'catch',
      label: 'Catch',
      type: VisualScriptType.exec,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'finally',
      label: 'Finally',
      type: VisualScriptType.exec,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'message',
      label: 'Message',
      type: VisualScriptType.string,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'value',
      label: 'Value',
      type: VisualScriptType.any,
      isInput: false,
      doc: 'Whatever the Throw carried, if anything.',
    ),
  ],
  evaluate: (context, node, inputs) {
    final flow = context.flow;
    if (flow == null) return _stop();
    context.execOutputs[node.id] = {'message': '', 'value': null};
    final status = flow.runPin(context, node, 'try');

    if (status == VisualScriptFlowStatus.threw) {
      final raised = context.signal;
      context.signal = null;
      final caught = raised is VisualScriptThrow
          ? raised
          : const VisualScriptThrow('');
      context.execOutputs[node.id] = {
        'message': caught.message,
        'value': caught.value,
      };
      flow.runPin(context, node, 'catch');
      if (_unwinding(context)) return _stop();
    } else if (status != VisualScriptFlowStatus.completed) {
      // A Break belongs to a loop further out, and an error stops everything.
      // Finally does not run: it is part of this node's flow, and this node's
      // flow is over.
      return _stop();
    }
    return _then('finally');
  },
);

final VisualScriptNodeType throwError = VisualScriptNodeType(
  id: 'flow.throw',
  label: 'Throw',
  category: 'Flow Control',
  doc:
      'Stops the flow and unwinds until a Try Catch catches it. Uncaught, it '
      'becomes the script\'s error.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'message',
      label: 'Message',
      type: VisualScriptType.string,
      defaultValue: 'Something went wrong',
    ),
    VisualScriptPin(id: 'value', label: 'Value', type: VisualScriptType.any),
  ],
  evaluate: (context, node, inputs) {
    context.signal = VisualScriptThrow(
      scriptString(inputs['message']),
      inputs['value'],
    );
    return _stop();
  },
);

// ---------------------------------------------------------------------------
// Branching on a value: Switch and Select.
// ---------------------------------------------------------------------------

/// The case values a Switch or a Select was given, as written into the node.
///
/// A list literal rather than a pin, because the cases decide the node's
/// shape: they have to be readable without running anything.
List<Object?> casesOf(VisualScriptNodeSpec node) =>
    scriptList(node.literals['cases']);

/// The pin id for case [index]. Kept to `[A-Za-z0-9_]` because the text format
/// writes pin ids unquoted on both sides of a wire.
String casePin(int index) => 'case_$index';

List<VisualScriptPin> _switchPins(
  VisualScriptNodeSpec node,
  VisualScriptGraphLookup? graphs, {
  required VisualScriptType selector,
}) {
  final cases = casesOf(node);
  return [
    _execIn,
    VisualScriptPin(id: 'selector', label: 'Selector', type: selector),
    for (var i = 0; i < cases.length; i++)
      _exec(casePin(i), scriptString(cases[i])),
    _exec('default', 'Default'),
  ];
}

VisualScriptResult _switch(
  VisualScriptContext context,
  VisualScriptNodeSpec node,
  Map<String, Object?> inputs,
  String Function(Object?) normalize,
) {
  final wanted = normalize(inputs['selector']);
  final cases = casesOf(node);
  for (var i = 0; i < cases.length; i++) {
    if (normalize(cases[i]) == wanted) return _then(casePin(i));
  }
  return _then('default');
}

final VisualScriptNodeType switchOnString = VisualScriptNodeType(
  id: 'flow.switchString',
  label: 'Switch on String',
  category: 'Flow Control',
  doc: 'Takes the branch whose case matches Selector, or Default.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'selector',
      label: 'Selector',
      type: VisualScriptType.string,
    ),
    VisualScriptPin(
      id: 'default',
      label: 'Default',
      type: VisualScriptType.exec,
      isInput: false,
    ),
  ],
  pinsFor: (node, graphs) =>
      _switchPins(node, graphs, selector: VisualScriptType.string),
  evaluate: (context, node, inputs) =>
      _switch(context, node, inputs, scriptString),
);

final VisualScriptNodeType switchOnInteger = VisualScriptNodeType(
  id: 'flow.switchInteger',
  label: 'Switch on Integer',
  category: 'Flow Control',
  doc: 'Takes the branch whose case matches Selector, or Default.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'selector',
      label: 'Selector',
      type: VisualScriptType.integer,
    ),
    VisualScriptPin(
      id: 'default',
      label: 'Default',
      type: VisualScriptType.exec,
      isInput: false,
    ),
  ],
  pinsFor: (node, graphs) =>
      _switchPins(node, graphs, selector: VisualScriptType.integer),
  evaluate: (context, node, inputs) =>
      _switch(context, node, inputs, (value) => '${scriptInteger(value)}'),
);

final VisualScriptNodeType selectValue = VisualScriptNodeType(
  id: 'flow.select',
  label: 'Select',
  category: 'Flow Control',
  doc:
      'The opposite of a Switch: gives back the value whose case matches '
      'Selector, without branching.',
  pins: const [
    VisualScriptPin(
      id: 'selector',
      label: 'Selector',
      type: VisualScriptType.string,
    ),
    VisualScriptPin(
      id: 'default',
      label: 'Default',
      type: VisualScriptType.any,
    ),
    VisualScriptPin(
      id: 'value',
      label: 'Value',
      type: VisualScriptType.any,
      isInput: false,
    ),
  ],
  pinsFor: (node, graphs) {
    final cases = casesOf(node);
    return [
      const VisualScriptPin(
        id: 'selector',
        label: 'Selector',
        type: VisualScriptType.string,
      ),
      for (var i = 0; i < cases.length; i++)
        VisualScriptPin(
          id: casePin(i),
          label: scriptString(cases[i]),
          type: VisualScriptType.any,
        ),
      const VisualScriptPin(
        id: 'default',
        label: 'Default',
        type: VisualScriptType.any,
      ),
      const VisualScriptPin(
        id: 'value',
        label: 'Value',
        type: VisualScriptType.any,
        isInput: false,
      ),
    ];
  },
  evaluate: (context, node, inputs) {
    final wanted = scriptString(inputs['selector']);
    final cases = casesOf(node);
    for (var i = 0; i < cases.length; i++) {
      if (scriptString(cases[i]) == wanted) {
        return _out({'value': inputs[casePin(i)]});
      }
    }
    return _out({'value': inputs['default']});
  },
);

final VisualScriptNodeType toggleValue = VisualScriptNodeType(
  id: 'flow.toggleValue',
  label: 'Toggle Value',
  category: 'Flow Control',
  doc: 'Gives back one of two values, depending on a condition.',
  pins: const [
    VisualScriptPin(
      id: 'condition',
      label: 'Condition',
      type: VisualScriptType.boolean,
      defaultValue: true,
    ),
    VisualScriptPin(id: 'true', label: 'If True', type: VisualScriptType.any),
    VisualScriptPin(id: 'false', label: 'If False', type: VisualScriptType.any),
    VisualScriptPin(
      id: 'value',
      label: 'Value',
      type: VisualScriptType.any,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': scriptBool(inputs['condition']) ? inputs['true'] : inputs['false'],
  }),
);

// ---------------------------------------------------------------------------
// Gates and latches.
// ---------------------------------------------------------------------------

final VisualScriptNodeType toggleFlow = VisualScriptNodeType(
  id: 'flow.toggleFlow',
  label: 'Toggle Flow',
  category: 'Flow Control',
  doc:
      'A switch you flip from the graph. Enter passes through On or Off '
      'depending on its state; Turn On, Turn Off and Toggle set it.',
  pins: const [
    VisualScriptPin(id: 'exec', label: 'Enter', type: VisualScriptType.exec),
    VisualScriptPin(
      id: 'turnOn',
      label: 'Turn On',
      type: VisualScriptType.exec,
    ),
    VisualScriptPin(
      id: 'turnOff',
      label: 'Turn Off',
      type: VisualScriptType.exec,
    ),
    VisualScriptPin(id: 'toggle', label: 'Toggle', type: VisualScriptType.exec),
    VisualScriptPin(
      id: 'startOn',
      label: 'Start On',
      type: VisualScriptType.boolean,
      defaultValue: false,
    ),
    VisualScriptPin(
      id: 'on',
      label: 'On',
      type: VisualScriptType.exec,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'off',
      label: 'Off',
      type: VisualScriptType.exec,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'isOn',
      label: 'Is On',
      type: VisualScriptType.boolean,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) {
    var on =
        context.nodeState[node.id] as bool? ?? scriptBool(inputs['startOn']);
    // Which input was entered from is not something a node is told, so the
    // setters are read as their own wires: an exec pin with something on it
    // that was just walked. The interpreter enters through exactly one, and
    // the state pins are checked before the pass-through.
    final entered = context.enteredPin;
    switch (entered) {
      case 'turnOn':
        on = true;
      case 'turnOff':
        on = false;
      case 'toggle':
        on = !on;
    }
    context.nodeState[node.id] = on;
    if (entered != 'exec') return _out({'isOn': on});
    return (outputs: {'isOn': on}, next: <String>[on ? 'on' : 'off']);
  },
);

final VisualScriptNodeType once = VisualScriptNodeType(
  id: 'flow.once',
  label: 'Once',
  category: 'Flow Control',
  doc:
      'Takes Once the first time it is reached and After every time '
      'afterwards. Reset arms it again.',
  pins: const [
    _execIn,
    VisualScriptPin(id: 'reset', label: 'Reset', type: VisualScriptType.exec),
    VisualScriptPin(
      id: 'once',
      label: 'Once',
      type: VisualScriptType.exec,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'after',
      label: 'After',
      type: VisualScriptType.exec,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) {
    if (context.enteredPin == 'reset') {
      context.nodeState[node.id] = false;
      return _stop();
    }
    final already = context.nodeState[node.id] == true;
    context.nodeState[node.id] = true;
    return _then(already ? 'after' : 'once');
  },
);

final VisualScriptNodeType cacheValue = VisualScriptNodeType(
  id: 'flow.cache',
  label: 'Cache',
  category: 'Flow Control',
  doc:
      'Reads its input once, when the flow reaches it, and hands back the '
      'same value until the flow reaches it again.',
  pins: const [
    _execIn,
    VisualScriptPin(id: 'value', label: 'Value', type: VisualScriptType.any),
    _execOut,
    VisualScriptPin(
      id: 'cached',
      label: 'Cached',
      type: VisualScriptType.any,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) {
    context.nodeState[node.id] = inputs['value'];
    return (outputs: {'cached': inputs['value']}, next: const <String>['then']);
  },
);

// ---------------------------------------------------------------------------
// Nothing, and what to do about it.
// ---------------------------------------------------------------------------

final VisualScriptNodeType nullCheck = VisualScriptNodeType(
  id: 'flow.nullCheck',
  label: 'Null Check',
  category: 'Flow Control',
  doc:
      'Takes one branch when its input is something, and the other when it '
      'is nothing.',
  pins: const [
    _execIn,
    VisualScriptPin(id: 'value', label: 'Value', type: VisualScriptType.any),
    VisualScriptPin(
      id: 'notNull',
      label: 'Is Something',
      type: VisualScriptType.exec,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'isNull',
      label: 'Is Nothing',
      type: VisualScriptType.exec,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) =>
      _then(inputs['value'] == null ? 'isNull' : 'notNull'),
);

final VisualScriptNodeType nullCoalesce = VisualScriptNodeType(
  id: 'flow.nullCoalesce',
  label: 'Null Coalesce',
  category: 'Flow Control',
  doc: 'Gives back its input, or the fallback when the input is nothing.',
  pins: const [
    VisualScriptPin(id: 'value', label: 'Value', type: VisualScriptType.any),
    VisualScriptPin(id: 'fallback', label: 'Or', type: VisualScriptType.any),
    VisualScriptPin(
      id: 'result',
      label: 'Result',
      type: VisualScriptType.any,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) =>
      _out({'result': inputs['value'] ?? inputs['fallback']}),
);

/// Every control node here, for registering in one go.
/// {@category Visual scripting}
final List<VisualScriptNodeType> controlVisualScriptNodes = [
  breakLoop,
  cacheValue,
  forEachLoop,
  forLoop,
  nullCheck,
  nullCoalesce,
  once,
  selectValue,
  switchOnInteger,
  switchOnString,
  throwError,
  toggleFlow,
  toggleValue,
  tryCatch,
  whileLoop,
];
