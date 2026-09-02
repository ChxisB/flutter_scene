/// Running a [VisualScriptGraph]: the node-type registry, the evaluation context, and
/// the interpreter that walks the wires.
///
/// Exec pushes and data pulls. An event node starts a run and hands control
/// along its exec output; whenever a node needs an input value it pulls
/// backward through the data wire and evaluates whoever is on the other end.
/// That is the whole execution model, and every node type is written against
/// it rather than against a schedule.
library;

import 'package:vector_math/vector_math.dart';

import 'visual_script_graph.dart';
import 'visual_script_trace.dart';

/// What a node can do while it runs.
///
/// The host supplies this. Everything a graph can reach outside its own
/// values goes through it, so the interpreter itself has no idea what a scene
/// is and the same graph runs in a test with a stub.
/// {@category Visual scripting}
abstract class VisualScriptHost {
  /// Seconds since the previous tick, for the nodes that integrate.
  double get deltaSeconds;

  /// Seconds since the graph started.
  double get elapsedSeconds;

  /// Reads a scene value by a dotted path the host understands
  /// (`position`, `rotation.y`, `target.position`).
  Object? read(String path);

  /// Writes one, and reports whether anything was written: a graph pointed at
  /// a node that no longer exists should say so rather than fail silently.
  bool write(String path, Object? value);

  /// Calls a host action by name with named arguments, returning whatever it
  /// produces. This is where playing a sound, spawning a prefab, or firing an
  /// application callback lands.
  Object? invoke(String action, Map<String, Object?> arguments);

  /// Reports a message from a Print node.
  void log(String message);
}

/// A host that does nothing, for a graph exercised without a scene.
/// {@category Visual scripting}
class NullVisualScriptHost implements VisualScriptHost {
  NullVisualScriptHost({this.deltaSeconds = 1 / 60, this.elapsedSeconds = 0});

  @override
  double deltaSeconds;

  @override
  double elapsedSeconds;

  /// Everything [log] was given, in order.
  final List<String> messages = [];

  /// Every [invoke] made, in order.
  final List<(String, Map<String, Object?>)> calls = [];

  /// Values [read] and [write] see, keyed by path.
  final Map<String, Object?> values = {};

  @override
  Object? read(String path) => values[path];

  @override
  bool write(String path, Object? value) {
    values[path] = value;
    return true;
  }

  @override
  Object? invoke(String action, Map<String, Object?> arguments) {
    calls.add((action, arguments));
    return null;
  }

  @override
  void log(String message) => messages.add(message);
}

/// Finds a graph a node names, for the node types whose shape or behaviour
/// comes from another graph — a Subgraph, a state's transition.
///
/// [Blueprint.graph] has this signature and tears off directly, which is why
/// this is a function rather than an interface the runtime would have to
/// import a blueprint to satisfy.
/// {@category Visual scripting}
typedef VisualScriptGraphLookup = VisualScriptGraph? Function(String name);

/// Control flow travelling outward past the node that raised it: a Break
/// leaving a loop, a Throw looking for a Try.
///
/// Deliberately not a Dart exception. A node's evaluate calls
/// [VisualScriptHost.invoke], which is application code, and an application
/// that wrapped its own `invoke` in a `catch` would silently swallow a
/// graph's Break — a coupling nobody would ever find.
/// {@category Visual scripting}
sealed class VisualScriptSignal {
  const VisualScriptSignal();
}

/// Leaves the innermost loop.
/// {@category Visual scripting}
final class VisualScriptBreak extends VisualScriptSignal {
  const VisualScriptBreak();
}

/// Unwinds until a Try catches it, or until it reaches the top and becomes
/// the run's error.
/// {@category Visual scripting}
final class VisualScriptThrow extends VisualScriptSignal {
  const VisualScriptThrow(this.message, [this.value]);

  /// What to show whoever is looking at the graph.
  final String message;

  /// An optional payload, for a Catch that wants more than the message.
  final Object? value;
}

/// How a nested run ended.
/// {@category Visual scripting}
enum VisualScriptFlowStatus {
  /// Ran off the end of its wires, which is the ordinary ending.
  completed,

  /// A Break is travelling outward. A loop clears it and stops iterating;
  /// anything else passes it on.
  broke,

  /// A Throw is travelling outward. A Try clears it and takes its Catch pin.
  threw,

  /// The run stopped on an error — the step budget, the nesting depth, or a
  /// node the registry does not have. Nothing catches this one.
  failed,
}

/// Running a nested flow from inside a node's evaluate.
///
/// This is what a loop, a Try, a Subgraph and a state transition all need and
/// what pushing onto the interpreter's work stack cannot give: a sub-flow
/// that finishes *before* the node that started it decides what to do next.
/// Reached as [VisualScriptContext.flow], rather than as another parameter to
/// every `evaluate` in the library.
/// {@category Visual scripting}
abstract class VisualScriptFlow {
  /// Runs whatever is wired to [node]'s exec output [pinId], to completion,
  /// in the caller's own frame.
  VisualScriptFlowStatus runPin(
    VisualScriptContext context,
    VisualScriptNodeSpec node,
    String pinId,
  );

  /// Reads an output pin in the running frame, evaluating whoever is behind
  /// it — the same pull a wired input goes through.
  ///
  /// A node needs this when a value has to be re-read rather than taken from
  /// the inputs it was handed: a While Loop's condition was resolved before
  /// its body ran, and a loop that could not see the body change its own
  /// condition would never end.
  Object? pull(VisualScriptContext context, int nodeId, String pinId);

  /// Runs [graph] from its [entry] event, in a frame of its own, entered from
  /// [caller].
  ///
  /// A frame of its own because node ids are unique only within a graph: run
  /// a nested graph in the caller's frame and its node 7 would read node 7's
  /// scratch, and the data-cycle guard would report a node feeding itself
  /// when it does no such thing. [caller] keys that frame's scratch, so two
  /// Subgraph nodes wrapping one graph keep their state apart.
  VisualScriptFlowStatus runGraph(
    VisualScriptContext context,
    VisualScriptNodeSpec caller,
    VisualScriptGraph graph, {
    String entry = 'event.start',
  });

  /// Pulls a value out of a nested graph, for a subgraph's output ports.
  Object? pullFrom(
    VisualScriptContext context,
    VisualScriptNodeSpec caller,
    VisualScriptGraph graph,
    int nodeId,
    String pinId,
  );
}

/// One graph on the call stack: what the run is walking, and the scratch its
/// nodes keep.
/// {@category Visual scripting}
class VisualScriptFrame {
  VisualScriptFrame({
    required this.graph,
    required this.nodeState,
    required this.path,
  });

  /// The graph this frame is running.
  final VisualScriptGraph graph;

  /// Per-node scratch for this frame. Held by the context and keyed by
  /// [path], so it outlives the frame — a Delay inside a subgraph has to keep
  /// counting between ticks.
  final Map<int, Object?> nodeState;

  /// Nodes whose data pull is in progress in this frame.
  ///
  /// Per frame rather than per run: an exec boundary genuinely resets what
  /// "currently pulling" means, and sharing one set would make every
  /// legitimate re-pull inside a sub-flow look like a cycle.
  final Set<int> pulling = {};

  /// What each exec node produced the last time it ran, keyed by node id.
  ///
  /// An exec node's outputs happen when it runs, not when somebody reads
  /// them: a Play Animation asked twice for its Found pin must not play the
  /// animation twice, and a For Loop asked for its Index must answer with the
  /// iteration it is on rather than starting the loop again.
  final Map<int, Map<String, Object?>> execOutputs = {};

  /// The call site, outermost first — `''` for the root, then `'/12'`,
  /// `'/12/4'`. Two Subgraph nodes wrapping the same graph get different
  /// paths, so each keeps its own scratch.
  final String path;
}

/// The state one run of a graph carries.
/// {@category Visual scripting}
class VisualScriptContext {
  VisualScriptContext({
    required VisualScriptGraph graph,
    required this.host,
    this.trace,
    this.graphs,
    Map<String, Object?>? variables,
  }) : variables = variables ?? {} {
    _frames.add(
      VisualScriptFrame(
        graph: graph,
        nodeState: _stateByPath.putIfAbsent('', () => {}),
        path: '',
      ),
    );
    // putIfAbsent rather than assignment: a blueprint's graphs share one map,
    // already seeded from the blueprint's own variables, and a second graph
    // declaring the same name must not reset what the first one has been
    // doing with it.
    for (final variable in graph.variables) {
      this.variables.putIfAbsent(variable.name, () => variable.initial);
    }
  }

  final VisualScriptHost host;

  /// How to find a graph a node names, or null when nothing nests.
  final VisualScriptGraphLookup? graphs;

  /// Where to record what the run did, or null to record nothing.
  ///
  /// Null by default, so a graph nobody is watching pays a null check per
  /// node rather than the bookkeeping.
  final VisualScriptTrace? trace;

  /// The variables in scope, seeded from their initial values.
  ///
  /// Shared across a blueprint's graphs when one is passed in, because a
  /// variable belongs to the blueprint rather than to the graph that happens
  /// to read it.
  final Map<String, Object?> variables;

  final List<VisualScriptFrame> _frames = [];

  /// Every frame's scratch, keyed by call path so it survives the frame being
  /// popped and re-pushed on the next tick. Never cleared by [beginTick]:
  /// forgetting it is how a Delay restarts every frame.
  final Map<String, Map<int, Object?>> _stateByPath = {};

  /// The graph currently running — the one at the top of the call stack, not
  /// the one the context was made for.
  VisualScriptGraph get graph => _frames.last.graph;

  /// The graph this context was made for, whatever is nested inside it.
  VisualScriptGraph get rootGraph => _frames.first.graph;

  /// Per-node scratch, for the node types that remember something between
  /// ticks (a delay's remaining time, a Do Once's latch).
  Map<int, Object?> get nodeState => _frames.last.nodeState;

  /// Nodes whose data pull is currently in progress, in the running frame.
  ///
  /// Re-entering one is a cycle in the data wires, which unlike an exec loop
  /// cannot be caught by a step budget: the pull is recursive, so it
  /// overflows the stack long before any count is reached. A node evaluated
  /// twice in one pull because two inputs share a source is not in here at
  /// the second visit, so the diamond that is legitimate stays legal.
  Set<int> get pulling => _frames.last.pulling;

  /// How deep the call stack is. One while an ordinary graph runs.
  int get depth => _frames.length;

  /// What each exec node in the running frame last produced.
  Map<int, Map<String, Object?>> get execOutputs => _frames.last.execOutputs;

  /// Clears what one tick accumulated: the step budget and the values exec
  /// nodes left behind. Not the scratch — a Delay counting down across ticks
  /// is the whole point of scratch.
  void beginTick() {
    steps = 0;
    for (final frame in _frames) {
      frame.execOutputs.clear();
    }
  }

  /// Whether the running frame is the one the context was made for, which is
  /// the only frame whose node ids mean anything to a canvas drawing the
  /// root graph.
  bool get isRootFrame => _frames.length == 1;

  /// Pushes a frame for [graph], called from [nodeId], and returns whether
  /// there was room. Sets [error] and returns false when there was not.
  bool pushFrame(VisualScriptGraph graph, int nodeId) {
    if (_frames.length >= maxDepth) {
      error =
          'Graphs are nested $maxDepth deep here, which is either a very '
          'deep subgraph or one that contains itself.';
      return false;
    }
    final path = '${_frames.last.path}/$nodeId';
    _frames.add(
      VisualScriptFrame(
        graph: graph,
        nodeState: _stateByPath.putIfAbsent(path, () => {}),
        path: path,
      ),
    );
    return true;
  }

  /// Pops the frame [pushFrame] pushed. Never pops the root.
  void popFrame() {
    if (_frames.length > 1) _frames.removeLast();
  }

  /// Runs a nested flow. Non-null while a run is in progress.
  VisualScriptFlow? flow;

  /// Which exec input the running node was entered through.
  ///
  /// Most nodes have one and never ask. A node with several — a Toggle Flow's
  /// Turn On beside its Enter, a Once's Reset — behaves differently depending
  /// on which wire arrived, and this is the only thing that says which.
  String enteredPin = 'exec';

  /// A Break or a Throw travelling outward, or null.
  ///
  /// Set by the node that raised it and cleared by whatever catches it. A run
  /// stops while one is set, which is what unwinding is here.
  VisualScriptSignal? signal;

  /// How many exec steps this run has taken, so a cycle in the wires stops
  /// rather than hangs the frame.
  int steps = 0;

  /// The step budget one run gets. A graph is authored by hand, so anything
  /// past a few thousand steps in one tick is a loop the author did not mean.
  ///
  /// Shared across nested runs on purpose: it is a budget for the whole
  /// tick's work, and a runaway For Loop is exactly what it exists to catch.
  static const int maxSteps = 10000;

  /// How many graphs may be nested before the run is stopped.
  ///
  /// The step budget cannot stand in for this. Each nested run is real Dart
  /// frames, so a graph that contains itself overflows the machine stack long
  /// before ten thousand steps are counted.
  static const int maxDepth = 32;

  String? _error;

  /// Set when the budget runs out, so the caller can surface it once rather
  /// than every frame. Mirrored into [trace], so a canvas showing the run
  /// shows why it stopped without being handed the context as well.
  String? get error => _error;
  set error(String? value) {
    _error = value;
    trace?.error = value;
  }
}

/// What a node's evaluation produced.
/// {@category Visual scripting}
typedef VisualScriptResult = ({
  /// Values on the node's output data pins, keyed by pin id.
  Map<String, Object?> outputs,

  /// The exec outputs to follow, in order. Empty stops this branch.
  ///
  /// A list rather than a single pin because a node that fans out (Sequence)
  /// has to be expressible without reaching into the interpreter: it names
  /// its branches and they are run in the order given.
  List<String> next,
});

/// A registered node type: what it looks like, and what it does.
/// {@category Visual scripting}
class VisualScriptNodeType {
  const VisualScriptNodeType({
    required this.id,
    required this.label,
    required this.category,
    required this.pins,
    required this.evaluate,
    this.doc = '',
    this.isEvent = false,
    this.pinsFor,
  });

  /// The stable id a [VisualScriptNodeSpec] names.
  final String id;

  /// The title drawn on the node.
  final String label;

  /// The palette group.
  final String category;

  /// What the node is for, shown in the palette and on hover.
  final String doc;

  /// Whether this node starts a run rather than being reached by one. Events
  /// have no exec input.
  final bool isEvent;

  /// The pins a freshly placed node has. Also the whole answer for the node
  /// types whose shape never varies, which is most of them.
  final List<VisualScriptPin> pins;

  /// The pins one particular node has, when they depend on that node.
  ///
  /// Null for a fixed shape. A Switch has an output per case, a Sequence as
  /// many as it was given, and a Subgraph the ports of the graph it wraps —
  /// none of which can be written as a list on the type. [graphs] is how the
  /// last of those finds the graph it names.
  ///
  /// Generated pin ids must match `[A-Za-z0-9_]+`: the text format writes
  /// them unquoted on both sides of a wire.
  final List<VisualScriptPin> Function(
    VisualScriptNodeSpec node,
    VisualScriptGraphLookup? graphs,
  )?
  pinsFor;

  /// Runs the node. [inputs] holds every input pin's resolved value; the
  /// result carries the output values and which exec pin to follow.
  final VisualScriptResult Function(
    VisualScriptContext context,
    VisualScriptNodeSpec node,
    Map<String, Object?> inputs,
  )
  evaluate;

  /// The pins [node] has, asking [pinsFor] when there is one.
  List<VisualScriptPin> pinsOf(
    VisualScriptNodeSpec node, [
    VisualScriptGraphLookup? graphs,
  ]) => pinsFor?.call(node, graphs) ?? pins;

  Iterable<VisualScriptPin> inputsOf(
    VisualScriptNodeSpec node, [
    VisualScriptGraphLookup? graphs,
  ]) => pinsOf(node, graphs).where((pin) => pin.isInput);

  Iterable<VisualScriptPin> outputsOf(
    VisualScriptNodeSpec node, [
    VisualScriptGraphLookup? graphs,
  ]) => pinsOf(node, graphs).where((pin) => !pin.isInput);

  VisualScriptPin? pinOf(
    VisualScriptNodeSpec node,
    String id, [
    VisualScriptGraphLookup? graphs,
  ]) {
    for (final pin in pinsOf(node, graphs)) {
      if (pin.id == id) return pin;
    }
    return null;
  }

  /// The pins a fresh node of this type has. For a type with a dynamic
  /// shape this is the starting shape, not the only one — prefer
  /// [inputsOf]/[outputsOf]/[pinOf] anywhere a node is in hand.
  Iterable<VisualScriptPin> get inputs => pins.where((pin) => pin.isInput);
  Iterable<VisualScriptPin> get outputs => pins.where((pin) => !pin.isInput);

  VisualScriptPin? pin(String id) {
    for (final pin in pins) {
      if (pin.id == id) return pin;
    }
    return null;
  }

  /// Whether [node] is reached by control flow rather than pulled for a value.
  ///
  /// An exec pin of either direction is the tell: a node that participates in
  /// the exec order produces its outputs when it runs. A node with none is
  /// pure data and is evaluated on demand.
  bool isExecDriven(
    VisualScriptNodeSpec node, [
    VisualScriptGraphLookup? graphs,
  ]) => pinsOf(node, graphs).any((pin) => pin.type == VisualScriptType.exec);
}

/// The node types a graph may use.
/// {@category Visual scripting}
class VisualScriptRegistry {
  final Map<String, VisualScriptNodeType> _types = {};

  void register(VisualScriptNodeType type) {
    if (_types.containsKey(type.id)) {
      throw StateError(
        'Visual script node type already registered: ${type.id}',
      );
    }
    _types[type.id] = type;
  }

  void registerAll(Iterable<VisualScriptNodeType> types) =>
      types.forEach(register);

  VisualScriptNodeType? operator [](String id) => _types[id];

  Iterable<VisualScriptNodeType> get all => _types.values;

  /// The registered categories, in first-registration order.
  List<String> get categories {
    final seen = <String>[];
    for (final type in _types.values) {
      if (!seen.contains(type.category)) seen.add(type.category);
    }
    return seen;
  }

  List<VisualScriptNodeType> inCategory(String category) => [
    for (final type in _types.values)
      if (type.category == category) type,
  ];
}

/// Walks a graph.
/// {@category Visual scripting}
class VisualScriptInterpreter implements VisualScriptFlow {
  VisualScriptInterpreter(this.registry);

  final VisualScriptRegistry registry;

  /// Runs every node of type [eventType] as a starting point.
  ///
  /// [where] narrows that to the nodes it accepts, which is how a named event
  /// reaches only the listeners that asked for that name: two On Signal nodes
  /// in one graph listening for different things must not both run because
  /// one of them was raised.
  ///
  /// Returns how many events fired, so a caller can tell a graph with no
  /// matching event from one that ran.
  int fire(
    VisualScriptContext context,
    String eventType, {
    bool Function(VisualScriptNodeSpec node)? where,
  }) {
    context.flow ??= this;
    var fired = 0;
    for (final node in context.graph.nodes) {
      if (node.type != eventType) continue;
      if (where != null && !where(node)) continue;
      fired++;
      _run(context, node);
      // A failed run has already said why. Starting the next event would
      // evaluate one more node before noticing, and overwrite the reason.
      if (context.error != null) break;
      // A Throw nothing caught stops being control flow and becomes the
      // run's error: there is no outer graph left to hand it to.
      if (context.signal case final VisualScriptThrow raised) {
        context.signal = null;
        context.error = raised.message;
        break;
      }
      context.signal = null;
    }
    return fired;
  }

  @override
  VisualScriptFlowStatus runPin(
    VisualScriptContext context,
    VisualScriptNodeSpec node,
    String pinId,
  ) {
    for (final link in context.graph.outputsFrom(node.id, pinId)) {
      final target = context.graph.node(link.toNode);
      if (target == null) continue;
      final status = _run(context, target, enteredPin: link.toPin);
      if (status != VisualScriptFlowStatus.completed) return status;
    }
    return VisualScriptFlowStatus.completed;
  }

  @override
  Object? pull(VisualScriptContext context, int nodeId, String pinId) =>
      evaluateOutput(context, nodeId, pinId);

  @override
  VisualScriptFlowStatus runGraph(
    VisualScriptContext context,
    VisualScriptNodeSpec caller,
    VisualScriptGraph graph, {
    String entry = 'event.start',
  }) {
    if (!context.pushFrame(graph, caller.id)) {
      return VisualScriptFlowStatus.failed;
    }
    try {
      var status = VisualScriptFlowStatus.completed;
      for (final node in graph.nodes) {
        if (node.type != entry) continue;
        status = _run(context, node);
        if (status != VisualScriptFlowStatus.completed) break;
      }
      return status;
    } finally {
      context.popFrame();
    }
  }

  @override
  Object? pullFrom(
    VisualScriptContext context,
    VisualScriptNodeSpec caller,
    VisualScriptGraph graph,
    int nodeId,
    String pinId,
  ) {
    if (!context.pushFrame(graph, caller.id)) return null;
    try {
      return evaluateOutput(context, nodeId, pinId);
    } finally {
      context.popFrame();
    }
  }

  /// Runs [start], then every exec branch it names, in order.
  ///
  /// An explicit work stack rather than recursion. A node may name several
  /// branches and each has to finish before the next begins, which is what a
  /// stack gives when the branches are pushed in reverse; recursion would
  /// give the same order but put the step budget's worth of frames on the
  /// real stack, and the budget is deliberately larger than that is safe.
  VisualScriptFlowStatus _run(
    VisualScriptContext context,
    VisualScriptNodeSpec start, {
    String enteredPin = 'exec',
  }) {
    final pending = <(VisualScriptNodeSpec, String)>[(start, enteredPin)];
    while (pending.isNotEmpty) {
      if (++context.steps > VisualScriptContext.maxSteps) {
        context.error =
            'The graph ran for ${VisualScriptContext.maxSteps} steps without '
            'finishing, which is either a loop in the exec wires or a loop '
            'node counting further than a frame can afford.';
        return VisualScriptFlowStatus.failed;
      }
      final (node, entered) = pending.removeLast();
      final type = registry[node.type];
      if (type == null) {
        context.error = 'Unknown node type "${node.type}".';
        return VisualScriptFlowStatus.failed;
      }
      context.enteredPin = entered;
      final inputs = _resolveInputs(context, node, type);
      // Published before the branches run, so a node downstream reading this
      // one's outputs — a loop's Index, an event's Delta — sees them.
      final result = type.evaluate(context, node, inputs);
      context.execOutputs[node.id] = result.outputs;
      _record(context, node, inputs, result.outputs, fired: result.next);
      if (context.error != null) return VisualScriptFlowStatus.failed;
      // A signal raised while this node ran is travelling outward. Its own
      // exec outputs are not taken — that is what unwinding means.
      if (context.signal case final raised?) {
        return raised is VisualScriptBreak
            ? VisualScriptFlowStatus.broke
            : VisualScriptFlowStatus.threw;
      }

      // Reverse, so the first branch named is the first popped and its whole
      // subtree runs before the second begins.
      for (var i = result.next.length - 1; i >= 0; i--) {
        // An exec output carries one wire (connect enforces it), but reading
        // them all keeps a hand-edited document from silently dropping one.
        for (final link in context.graph.outputsFrom(node.id, result.next[i])) {
          final target = context.graph.node(link.toNode);
          if (target != null) pending.add((target, link.toPin));
        }
      }
    }
    return VisualScriptFlowStatus.completed;
  }

  /// Records a node's step, its values, and the exec pins it took.
  ///
  /// Only for the frame the context was made for. A nested graph's node 7 is
  /// not the root graph's node 7, and a trace keyed by node id alone would
  /// light up the wrong node on the canvas — better to show nothing than to
  /// show a lie.
  void _record(
    VisualScriptContext context,
    VisualScriptNodeSpec node,
    Map<String, Object?> inputs,
    Map<String, Object?> outputs, {
    List<String> fired = const [],
  }) {
    final trace = context.trace;
    if (trace == null || !context.isRootFrame) return;
    trace.recordStep(node.id, node.type);
    for (final entry in inputs.entries) {
      trace.recordValue(node.id, entry.key, entry.value);
    }
    for (final entry in outputs.entries) {
      trace.recordValue(node.id, entry.key, entry.value);
    }
    for (final pin in fired) {
      trace.recordExec(node.id, pin);
    }
  }

  /// Resolves every input pin of [node]: the wire if there is one, otherwise
  /// the literal typed into it, otherwise the pin's default.
  Map<String, Object?> _resolveInputs(
    VisualScriptContext context,
    VisualScriptNodeSpec node,
    VisualScriptNodeType type,
  ) {
    final values = <String, Object?>{};
    for (final pin in type.inputsOf(node, context.graphs)) {
      if (pin.type == VisualScriptType.exec) continue;
      final link = context.graph.inputTo(node.id, pin.id);
      if (link != null) {
        values[pin.id] = evaluateOutput(context, link.fromNode, link.fromPin);
        continue;
      }
      values[pin.id] = node.literals.containsKey(pin.id)
          ? node.literals[pin.id]
          : pin.defaultValue;
    }
    return values;
  }

  /// Pulls the value of an output pin, evaluating the node behind it.
  ///
  /// Pure data nodes are evaluated on demand rather than scheduled, so a
  /// value nothing asks for is never computed. A node reached twice in one
  /// pull is evaluated twice; caching would need a notion of when a value
  /// goes stale, and at the size a hand-authored graph reaches, recomputing a
  /// multiply is cheaper than tracking that.
  Object? evaluateOutput(
    VisualScriptContext context,
    int nodeId,
    String pinId,
  ) {
    context.flow ??= this;
    // Read once: a nested run inside this node's evaluate pushes a frame, and
    // the set to clean up at the end is the one entered here.
    final pulling = context.pulling;
    if (!pulling.add(nodeId)) {
      context.error =
          'Node $nodeId feeds itself, which is a cycle in the data wires.';
      return null;
    }
    try {
      if (++context.steps > VisualScriptContext.maxSteps) {
        context.error =
            'The graph ran for ${VisualScriptContext.maxSteps} steps without '
            'finishing.';
        return null;
      }
      final node = context.graph.node(nodeId);
      if (node == null) return null;
      final type = registry[node.type];
      if (type == null) {
        context.error = 'Unknown node type "${node.type}".';
        return null;
      }
      // An exec node answers with what it produced when it ran. Evaluating it
      // here instead would play the animation a second time, or restart the
      // loop whose index was being read. A node that has not run yet has no
      // value to give, and null is the honest answer.
      if (type.isExecDriven(node, context.graphs)) {
        return context.execOutputs[nodeId]?[pinId];
      }
      final inputs = _resolveInputs(context, node, type);
      final outputs = type.evaluate(context, node, inputs).outputs;
      // A pulled node is recorded too. Its value is what a data wire is
      // carrying, and a wire with no label is the thing a trace exists to
      // fix; that a value node never appears in the exec order is the point.
      _record(context, node, inputs, outputs);
      return outputs[pinId];
    } finally {
      pulling.remove(nodeId);
    }
  }
}

/// Coerces [value] to a double, or [fallback].
/// {@category Visual scripting}
double scriptNumber(Object? value, [double fallback = 0]) => switch (value) {
  double v => v,
  int v => v.toDouble(),
  bool v => v ? 1 : 0,
  String v => double.tryParse(v) ?? fallback,
  _ => fallback,
};

/// Coerces [value] to an int, or [fallback].
/// {@category Visual scripting}
int scriptInteger(Object? value, [int fallback = 0]) => switch (value) {
  int v => v,
  double v => v.round(),
  bool v => v ? 1 : 0,
  String v => int.tryParse(v) ?? fallback,
  _ => fallback,
};

/// Coerces [value] to a bool.
///
/// A number is true when nonzero and a string when non-empty, which is what a
/// Branch fed a count or a name is asking for.
/// {@category Visual scripting}
bool scriptBool(Object? value, [bool fallback = false]) => switch (value) {
  bool v => v,
  double v => v != 0,
  int v => v != 0,
  String v => v.isNotEmpty,
  null => fallback,
  _ => true,
};

/// Coerces [value] to a vector, or zero.
///
/// A scalar broadcasts to all three components, which is what `scale * 2`
/// means to whoever wired it. A wider vector drops its tail rather than
/// refusing, so a Break/Make round trip through a Vector 4 pin still works.
/// {@category Visual scripting}
Vector3 scriptVector(Object? value) => switch (value) {
  Vector3 v => v,
  Vector2 v => Vector3(v.x, v.y, 0),
  Vector4 v => Vector3(v.x, v.y, v.z),
  double v => Vector3.all(v),
  int v => Vector3.all(v.toDouble()),
  _ => Vector3.zero(),
};

/// Coerces [value] to a 2D vector, or zero.
/// {@category Visual scripting}
Vector2 scriptVector2(Object? value) => switch (value) {
  Vector2 v => v,
  Vector3 v => Vector2(v.x, v.y),
  Vector4 v => Vector2(v.x, v.y),
  double v => Vector2.all(v),
  int v => Vector2.all(v.toDouble()),
  _ => Vector2.zero(),
};

/// Coerces [value] to a 4D vector, or zero.
///
/// A [Vector3] gains a w of 0, which is the right answer for a direction and
/// the wrong one for a colour; colour pins go through [scriptColor], which
/// fills alpha with 1 instead.
/// {@category Visual scripting}
Vector4 scriptVector4(Object? value) => switch (value) {
  Vector4 v => v,
  Vector3 v => Vector4(v.x, v.y, v.z, 0),
  Vector2 v => Vector4(v.x, v.y, 0, 0),
  double v => Vector4.all(v),
  int v => Vector4.all(v.toDouble()),
  _ => Vector4.zero(),
};

/// Coerces [value] to a linear RGBA colour, defaulting to opaque white.
///
/// An unspecified alpha is 1, not 0: a colour wired from a Vector 3 is a
/// colour somebody wants to see.
/// {@category Visual scripting}
Vector4 scriptColor(Object? value) => switch (value) {
  Vector4 v => v,
  Vector3 v => Vector4(v.x, v.y, v.z, 1),
  double v => Vector4(v, v, v, 1),
  int v => Vector4(v.toDouble(), v.toDouble(), v.toDouble(), 1),
  _ => Vector4(1, 1, 1, 1),
};

/// Coerces [value] to a rotation, or the identity.
///
/// A [Vector3] is read as Euler angles in degrees, because that is what a
/// user typing into three boxes means by a rotation.
/// {@category Visual scripting}
Quaternion scriptQuaternion(Object? value) => switch (value) {
  Quaternion v => v,
  Vector3 v => Quaternion.euler(
    v.y * degrees2Radians,
    v.x * degrees2Radians,
    v.z * degrees2Radians,
  ),
  _ => Quaternion.identity(),
};

/// Coerces [value] to a list.
///
/// A single value becomes a one-element list rather than an empty one, so a
/// For Each fed one thing iterates it. Null is the empty list.
/// {@category Visual scripting}
List<Object?> scriptList(Object? value) => switch (value) {
  List<Object?> v => v,
  Iterable<Object?> v => v.toList(),
  null => <Object?>[],
  _ => <Object?>[value],
};

/// Coerces [value] to a string-keyed map, or an empty one.
/// {@category Visual scripting}
Map<String, Object?> scriptMap(Object? value) => switch (value) {
  Map<String, Object?> v => v,
  Map<Object?, Object?> v => v.map((key, val) => MapEntry('$key', val)),
  _ => <String, Object?>{},
};

/// Renders [value] the way a Print node shows it.
/// {@category Visual scripting}
String scriptString(Object? value) => switch (value) {
  null => 'null',
  Vector3 v =>
    '(${v.x.toStringAsFixed(3)}, ${v.y.toStringAsFixed(3)}, '
        '${v.z.toStringAsFixed(3)})',
  _ => '$value',
};
