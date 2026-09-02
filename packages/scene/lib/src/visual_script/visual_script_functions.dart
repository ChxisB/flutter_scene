/// Calling one graph from another: entry and return nodes, and the call node
/// that reaches them.
///
/// A blueprint could always hold functions and macros, and nothing could run
/// one. There was no node that called anything, and no way for a graph to
/// take an argument or hand a value back — so a "function" was a second
/// canvas that ran only if Dart asked it to. This is the part that makes a
/// graph reusable rather than merely tidy.
///
/// **Functions and macros differ in one thing here**: a function gets a frame
/// of its own, so its Local variables and its nodes' scratch belong to that
/// call. A macro is pasted in — it shares the caller's frame — which is why a
/// macro may have several exec outputs and a function has one.
///
/// A **pure** graph has no exec pins on its call node and runs whenever
/// something reads one of its results, the way an addition does. An impure
/// one sits in the exec order, because *when* it runs is part of what it
/// does.
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

/// The literal a call node keeps the name of the graph it calls in.
const String calledGraphKey = 'graph';

/// The graph [node] calls, or null when it names nothing this blueprint has.
/// {@category Visual scripting}
VisualScriptGraph? calledGraphOf(
  VisualScriptNodeSpec node,
  VisualScriptShapeContext context,
) {
  final name = node.literals[calledGraphKey];
  if (name is! String || name.isEmpty) return null;
  return context.graphs?.call(name);
}

// ---------------------------------------------------------------------------
// Inside the function.
// ---------------------------------------------------------------------------

final VisualScriptNodeType functionEntry = VisualScriptNodeType(
  id: 'function.entry',
  label: 'Entry',
  category: 'Function',
  doc:
      'Where a call arrives. Its outputs are the parameters this graph '
      'declares, so adding one here is adding one to every node that calls it.',
  isEvent: true,
  pins: const [_execOut],
  pinsFor: (node, context) => [
    _execOut,
    for (final parameter in context.graph?.parameters ?? const [])
      parameter.asPin(isInput: false),
  ],
  // The values were put in the frame by whoever called; this node hands them
  // to the wires.
  evaluate: (context, node, inputs) =>
      (outputs: context.arguments, next: const <String>['then']),
);

final VisualScriptNodeType functionResult = VisualScriptNodeType(
  id: 'function.result',
  label: 'Return',
  category: 'Function',
  doc:
      'Hands values back to whoever called, and ends the call. Its inputs are '
      'the results this graph declares.',
  pins: const [_execIn],
  pinsFor: (node, context) => [
    _execIn,
    for (final result in context.graph?.results ?? const [])
      result.asPin(isInput: true),
  ],
  evaluate: (context, node, inputs) {
    context.results.addAll(inputs);
    // Nothing follows a return. A second Return further down the same wire
    // would overwrite the first, which is why this one stops here.
    return (outputs: const <String, Object?>{}, next: const <String>[]);
  },
);

// ---------------------------------------------------------------------------
// Calling it.
// ---------------------------------------------------------------------------

/// The pins a call node has, taken from the graph it names.
List<VisualScriptPin> _callPins(
  VisualScriptNodeSpec node,
  VisualScriptShapeContext context,
) {
  final target = calledGraphOf(node, context);
  if (target == null) {
    // Nothing named, or nothing found. The bare exec pins keep the node
    // wireable so a graph renamed underneath it is repairable rather than
    // stranded.
    return const [_execIn, _execOut];
  }
  return [
    if (!target.isPure) _execIn,
    for (final parameter in target.parameters) parameter.asPin(isInput: true),
    if (!target.isPure) _execOut,
    for (final result in target.results) result.asPin(isInput: false),
  ];
}

final VisualScriptNodeType callFunction = VisualScriptNodeType(
  id: 'function.call',
  label: 'Call Function',
  category: 'Function',
  doc:
      'Runs another graph in this blueprint and waits for it. Its pins are '
      'that graph\'s parameters and results.',
  pins: const [_execIn, _execOut],
  pinsFor: _callPins,
  evaluate: (context, node, inputs) {
    final flow = context.flow;
    final target = calledGraphOf(node, context.shape);
    if (flow == null || target == null) {
      // A call to nothing is a mistake worth naming: silently continuing
      // would leave whoever wrote it looking for the missing behaviour
      // somewhere else entirely.
      context.signal = VisualScriptThrow(
        'There is no graph called "${node.literals[calledGraphKey] ?? ''}" to '
        'call.',
      );
      return (outputs: const <String, Object?>{}, next: const <String>[]);
    }

    // A macro is pasted in and shares the caller's frame; a function gets one
    // of its own, so its Local variables and its Delays are per call.
    final called = target.kind == VisualScriptGraphKind.macro
        ? flow.runInline(context, node, target, arguments: inputs)
        : flow.callGraph(context, node, target, arguments: inputs);

    if (called.status != VisualScriptFlowStatus.completed) {
      // A Break or a Throw from inside keeps travelling; the caller is not
      // where it was meant to stop.
      return (outputs: called.results, next: const <String>[]);
    }
    return (
      outputs: called.results,
      next: target.isPure ? const <String>[] : const <String>['then'],
    );
  },
);

// ---------------------------------------------------------------------------
// Custom events.
// ---------------------------------------------------------------------------

/// The literal an event node keeps the event's name in.
const String namedEventKey = 'event';

/// The event [node] names, or null when it names nothing declared.
/// {@category Visual scripting}
VisualScriptEventSpec? namedEventOf(
  VisualScriptNodeSpec node,
  VisualScriptShapeContext context,
) {
  final name = node.literals[namedEventKey];
  if (name is! String || name.isEmpty) return null;
  return context.events?.call(name);
}

final VisualScriptNodeType onCustomEvent = VisualScriptNodeType(
  id: 'event.custom',
  label: 'On Event',
  category: 'Events',
  doc:
      'Runs when something calls the event it names, and hands on whatever '
      'that call carried.',
  isEvent: true,
  pins: const [_execOut],
  pinsFor: (node, context) => [
    _execOut,
    for (final parameter
        in namedEventOf(node, context)?.parameters ??
            const <VisualScriptParameter>[])
      parameter.asPin(isInput: false),
  ],
  evaluate: (context, node, inputs) =>
      (outputs: context.arguments, next: const <String>['then']),
);

final VisualScriptNodeType callCustomEvent = VisualScriptNodeType(
  id: 'flow.callEvent',
  label: 'Call Event',
  category: 'Events',
  doc:
      'Raises a named event. Every On Event node listening for that name runs '
      'before this one continues.',
  pins: const [_execIn, _execOut],
  pinsFor: (node, context) => [
    _execIn,
    for (final parameter
        in namedEventOf(node, context)?.parameters ??
            const <VisualScriptParameter>[])
      parameter.asPin(isInput: true),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    final flow = context.flow;
    final name = node.literals[namedEventKey];
    if (flow == null || name is! String || name.isEmpty) {
      return (outputs: const <String, Object?>{}, next: const <String>['then']);
    }
    // Synchronously, before continuing: a call that queued would put the
    // listener's effects after everything downstream of the caller, which is
    // not what "call" means anywhere else.
    flow.raiseEvent(context, node, name, arguments: inputs);
    if (context.error != null || context.signal != null) {
      return (outputs: const <String, Object?>{}, next: const <String>[]);
    }
    return (outputs: const <String, Object?>{}, next: const <String>['then']);
  },
);

/// The function nodes, for registering in one go.
/// {@category Visual scripting}
final List<VisualScriptNodeType> functionVisualScriptNodes = [
  functionEntry,
  functionResult,
  callFunction,
  onCustomEvent,
  callCustomEvent,
];
