/// A [VisualScriptGraph]'s text form.
///
/// Plain JSON rather than the document's binary payloads: a graph is source,
/// people diff it, and a merge conflict in a level's logic should be readable.
library;

import 'dart:convert';

import 'package:vector_math/vector_math.dart';

import 'blueprint.dart';
import 'visual_script_graph.dart';

/// The format version written, so a reader can tell an old file from a
/// corrupt one.
const int visualScriptVersion = 1;

/// Encodes [graph] as a JSON object.
/// {@category Visual scripting}
Map<String, Object?> encodeVisualScript(VisualScriptGraph graph) => {
  'version': visualScriptVersion,
  'nextNodeId': graph.nextNodeId,
  if (graph.name.isNotEmpty) 'name': graph.name,
  if (graph.kind != VisualScriptGraphKind.eventGraph) 'kind': graph.kind.name,
  'nodes': [
    for (final node in graph.nodes)
      {
        'id': node.id,
        'type': node.type,
        'x': node.position.x,
        'y': node.position.y,
        if (node.literals.isNotEmpty)
          'literals': {
            for (final entry in node.literals.entries)
              entry.key: _encodeValue(entry.value),
          },
      },
  ],
  'links': [
    for (final link in graph.links)
      {
        'from': link.fromNode,
        'fromPin': link.fromPin,
        'to': link.toNode,
        'toPin': link.toPin,
      },
  ],
  if (graph.isPure) 'pure': true,
  if (graph.parameters.isNotEmpty)
    'parameters': [
      for (final entry in graph.parameters) _encodeParameter(entry),
    ],
  if (graph.results.isNotEmpty)
    'results': [for (final entry in graph.results) _encodeParameter(entry)],
  if (graph.variables.isNotEmpty)
    'variables': [
      for (final variable in graph.variables)
        {
          'name': variable.name,
          'type': variable.type.name,
          // Omitted for graph scope, which is what every variable saved
          // before scopes existed is.
          if (variable.scope != VisualScriptVariableScope.graph)
            'scope': variable.scope.name,
          if (variable.initial != null)
            'initial': _encodeValue(variable.initial),
        },
    ],
};

/// Decodes a graph written by [encodeVisualScript].
///
/// Lenient about what it does not recognize: an unknown pin literal or a
/// variable of a type this build does not have is kept rather than dropped
/// where it can be, because a graph opened by an older editor and saved again
/// should not quietly lose half of itself.
/// {@category Visual scripting}
VisualScriptGraph decodeVisualScript(Map<String, Object?> json) {
  final graph = VisualScriptGraph(
    nextNodeId: json['nextNodeId'] is num
        ? (json['nextNodeId']! as num).toInt()
        : 1,
    name: json['name'] is String ? json['name']! as String : '',
    // A graph written before kinds existed is an event graph, which is what
    // every graph was.
    kind:
        VisualScriptGraphKind.values
            .where((kind) => kind.name == json['kind'])
            .firstOrNull ??
        VisualScriptGraphKind.eventGraph,
  );
  for (final raw in (json['nodes'] as List? ?? const [])) {
    if (raw is! Map) continue;
    final map = raw.cast<String, Object?>();
    final id = map['id'];
    final type = map['type'];
    if (id is! num || type is! String) continue;
    graph.nodes.add(
      VisualScriptNodeSpec(
        id: id.toInt(),
        type: type,
        position: Vector2(_double(map['x']), _double(map['y'])),
        literals: {
          for (final entry in ((map['literals'] as Map?) ?? const {}).entries)
            '${entry.key}': _decodeValue(entry.value),
        },
      ),
    );
  }
  for (final raw in (json['links'] as List? ?? const [])) {
    if (raw is! Map) continue;
    final map = raw.cast<String, Object?>();
    final from = map['from'];
    final to = map['to'];
    if (from is! num || to is! num) continue;
    if (map['fromPin'] is! String || map['toPin'] is! String) continue;
    graph.links.add(
      VisualScriptLink(
        fromNode: from.toInt(),
        fromPin: map['fromPin']! as String,
        toNode: to.toInt(),
        toPin: map['toPin']! as String,
      ),
    );
  }
  graph.isPure = json['pure'] == true;
  graph.parameters.addAll(_decodeParameters(json['parameters']));
  graph.results.addAll(_decodeParameters(json['results']));
  for (final raw in (json['variables'] as List? ?? const [])) {
    if (raw is! Map) continue;
    final map = raw.cast<String, Object?>();
    final name = map['name'];
    if (name is! String) continue;
    graph.variables.add(
      VisualScriptVariable(
        name: name,
        type: VisualScriptType.values.firstWhere(
          (candidate) => candidate.name == map['type'],
          orElse: () => VisualScriptType.any,
        ),
        scope: VisualScriptVariableScope.parse(map['scope'] as String?),
        initial: _decodeValue(map['initial']),
      ),
    );
  }
  // A hand-edited file can leave the counter behind the ids in use, which
  // would hand a fresh node an id a wire already points at.
  for (final node in graph.nodes) {
    if (node.id >= graph.nextNodeId) graph.nextNodeId = node.id + 1;
  }
  return graph;
}

/// [encodeVisualScript] as an indented JSON string.
/// {@category Visual scripting}
String writeVisualScript(VisualScriptGraph graph) =>
    const JsonEncoder.withIndent('  ').convert(encodeVisualScript(graph));

/// Parses a graph from [writeVisualScript] output.
/// {@category Visual scripting}
VisualScriptGraph readVisualScript(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw const FormatException('A flow graph must be a JSON object');
  }
  return decodeVisualScript(decoded.cast<String, Object?>());
}

/// Vectors and rotations are the values that are not already JSON, so each is
/// tagged rather than written as a bare list, which would decode as a list —
/// and a list is now a value in its own right, so the ambiguity would be real.
///
/// Lists and maps carry no tag: they encode as themselves, element by element,
/// so a list of vectors survives.
Object? _encodeValue(Object? value) => switch (value) {
  Vector2 v => {
    r'$vec2': [v.x, v.y],
  },
  Vector3 v => {
    r'$vec3': [v.x, v.y, v.z],
  },
  Vector4 v => {
    r'$vec4': [v.x, v.y, v.z, v.w],
  },
  Quaternion v => {
    r'$quat': [v.x, v.y, v.z, v.w],
  },
  List<Object?> v => v.map(_encodeValue).toList(),
  Map<Object?, Object?> v => v.map(
    (key, val) => MapEntry('$key', _encodeValue(val)),
  ),
  _ => value,
};

Object? _decodeValue(Object? value) {
  if (value is List) return value.map(_decodeValue).toList();
  if (value is Map) {
    for (final entry in _vectorTags.entries) {
      final tagged = value[entry.key];
      if (tagged is List && tagged.length >= entry.value.$1) {
        return entry.value.$2(tagged);
      }
    }
    return value
        .map((key, val) => MapEntry('$key', _decodeValue(val)))
        .cast<String, Object?>();
  }
  return value;
}

/// Each tag, the arity it needs, and how to rebuild it. Checked in order, so
/// a hand-written file carrying two tags resolves the same way every time.
final Map<String, (int, Object Function(List<Object?>))> _vectorTags = {
  r'$vec2': (2, (v) => Vector2(_double(v[0]), _double(v[1]))),
  r'$vec3': (3, (v) => Vector3(_double(v[0]), _double(v[1]), _double(v[2]))),
  r'$vec4': (
    4,
    (v) => Vector4(_double(v[0]), _double(v[1]), _double(v[2]), _double(v[3])),
  ),
  r'$quat': (
    4,
    (v) =>
        Quaternion(_double(v[0]), _double(v[1]), _double(v[2]), _double(v[3])),
  ),
};

Map<String, Object?> _encodeParameter(VisualScriptParameter parameter) => {
  'id': parameter.id,
  'name': parameter.name,
  'type': parameter.type.name,
  if (parameter.doc.isNotEmpty) 'doc': parameter.doc,
  if (parameter.defaultValue != null)
    'default': _encodeValue(parameter.defaultValue),
};

List<VisualScriptParameter> _decodeParameters(Object? raw) => [
  for (final entry in (raw as List? ?? const []))
    if (entry is Map)
      if (entry['id'] case final String id)
        VisualScriptParameter(
          id: id,
          name: entry['name'] is String ? entry['name']! as String : id,
          type:
              VisualScriptType.values
                  .where((type) => type.name == entry['type'])
                  .firstOrNull ??
              VisualScriptType.any,
          doc: entry['doc'] is String ? entry['doc']! as String : '',
          defaultValue: _decodeValue(entry['default']),
        ),
];

double _double(Object? value) => value is num ? value.toDouble() : 0;

/// Encodes [blueprint] as a JSON object.
///
/// The graphs carry their own kinds and names; the variables sit on the
/// blueprint, because that is where they belong once there is more than one
/// graph to share them.
/// {@category Visual scripting}
Map<String, Object?> encodeBlueprint(Blueprint blueprint) => {
  'version': visualScriptVersion,
  if (blueprint.name.isNotEmpty) 'name': blueprint.name,
  // Written as deltas from the defaults, like everything else: a plain class
  // extending a node says neither, which is what every blueprint written
  // before these existed looks like.
  if (blueprint.kind != BlueprintKind.blueprintClass)
    'kind': blueprint.kind.name,
  if (blueprint.parentClass != defaultBlueprintParent)
    'parent': blueprint.parentClass,
  if (blueprint.variables.isNotEmpty)
    'variables': [
      for (final variable in blueprint.variables)
        {
          'name': variable.name,
          'type': variable.type.name,
          // Omitted for graph scope, which is what every variable saved
          // before scopes existed is.
          if (variable.scope != VisualScriptVariableScope.graph)
            'scope': variable.scope.name,
          if (variable.initial != null)
            'initial': _encodeValue(variable.initial),
        },
    ],
  'graphs': [for (final graph in blueprint.graphs) encodeVisualScript(graph)],
};

/// Decodes a blueprint written by [encodeBlueprint].
///
/// A document holding a bare graph rather than a blueprint reads as a
/// blueprint with that one event graph in it, which is what it was.
/// {@category Visual scripting}
Blueprint decodeBlueprint(Map<String, Object?> json) {
  final raw = json['graphs'];
  if (raw is! List) return Blueprint.of(decodeVisualScript(json));
  final blueprint = Blueprint(
    name: json['name'] is String ? json['name']! as String : '',
    kind: BlueprintKind.parse(json['kind'] as String?),
    parentClass: json['parent'] is String
        ? json['parent']! as String
        : defaultBlueprintParent,
  );
  for (final entry in raw) {
    if (entry is! Map) continue;
    blueprint.graphs.add(decodeVisualScript(entry.cast<String, Object?>()));
  }
  for (final entry in (json['variables'] as List? ?? const [])) {
    if (entry is! Map) continue;
    final map = entry.cast<String, Object?>();
    final name = map['name'];
    if (name is! String) continue;
    blueprint.variables.add(
      VisualScriptVariable(
        name: name,
        type:
            VisualScriptType.values
                .where((type) => type.name == map['type'])
                .firstOrNull ??
            VisualScriptType.any,
        scope: VisualScriptVariableScope.parse(map['scope'] as String?),
        initial: _decodeValue(map['initial']),
      ),
    );
  }
  return blueprint;
}

/// [blueprint] as its canonical JSON text.
/// {@category Visual scripting}
String writeBlueprint(Blueprint blueprint) =>
    jsonEncode(encodeBlueprint(blueprint));

/// Reads a blueprint from [source].
/// {@category Visual scripting}
Blueprint readBlueprint(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw const FormatException('A blueprint is a JSON object');
  }
  return decodeBlueprint(decoded.cast<String, Object?>());
}
