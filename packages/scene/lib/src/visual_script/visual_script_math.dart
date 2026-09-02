/// The arithmetic a graph reaches for: scalars, vectors, rotations, and the
/// comparisons between them.
///
/// The base library has the eight operations a graph needs to move something
/// along a line. This is the rest — the ones you notice are missing the first
/// time a graph has to face a target, stay inside a circle, or ease anything.
///
/// Every node here is pure: no exec pins, no host, no scratch. They are pulled
/// when a value is wanted and are free when nothing wants them.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'visual_script_graph.dart';
import 'visual_script_runtime.dart';

VisualScriptResult _out(Map<String, Object?> outputs) =>
    (outputs: outputs, next: const <String>[]);

VisualScriptPin _in(
  String id,
  String label,
  VisualScriptType type, {
  Object? defaultValue,
  String doc = '',
}) => VisualScriptPin(
  id: id,
  label: label,
  type: type,
  defaultValue: defaultValue,
  doc: doc,
);

VisualScriptPin _outPin(String id, String label, VisualScriptType type) =>
    VisualScriptPin(id: id, label: label, type: type, isInput: false);

/// A node taking one number and giving one back.
VisualScriptNodeType _unary(
  String id,
  String label,
  String doc,
  double Function(double a) compute, {
  String category = 'Math',
}) => VisualScriptNodeType(
  id: id,
  label: label,
  category: category,
  doc: doc,
  pins: [
    _in('a', 'A', VisualScriptType.number, defaultValue: 0.0),
    _outPin('value', 'Value', VisualScriptType.number),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': compute(scriptNumber(inputs['a']))}),
);

/// A node taking two numbers and giving one back.
VisualScriptNodeType _binary(
  String id,
  String label,
  String doc,
  double Function(double a, double b) compute, {
  double defaultB = 0,
}) => VisualScriptNodeType(
  id: id,
  label: label,
  category: 'Math',
  doc: doc,
  pins: [
    _in('a', 'A', VisualScriptType.number, defaultValue: 0.0),
    _in('b', 'B', VisualScriptType.number, defaultValue: defaultB),
    _outPin('value', 'Value', VisualScriptType.number),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': compute(scriptNumber(inputs['a']), scriptNumber(inputs['b'])),
  }),
);

/// A node taking one vector and giving a number back.
VisualScriptNodeType _vectorToNumber(
  String id,
  String label,
  String doc,
  double Function(Vector3 a) compute,
) => VisualScriptNodeType(
  id: id,
  label: label,
  category: 'Vector',
  doc: doc,
  pins: [
    _in('a', 'A', VisualScriptType.vector3),
    _outPin('value', 'Value', VisualScriptType.number),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': compute(scriptVector(inputs['a']))}),
);

/// A node taking two vectors and giving a vector back.
VisualScriptNodeType _vectorPair(
  String id,
  String label,
  String doc,
  Vector3 Function(Vector3 a, Vector3 b) compute,
) => VisualScriptNodeType(
  id: id,
  label: label,
  category: 'Vector',
  doc: doc,
  pins: [
    _in('a', 'A', VisualScriptType.vector3),
    _in('b', 'B', VisualScriptType.vector3),
    _outPin('value', 'Value', VisualScriptType.vector3),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': compute(scriptVector(inputs['a']), scriptVector(inputs['b'])),
  }),
);

// ---------------------------------------------------------------------------
// Scalars.
// ---------------------------------------------------------------------------

final VisualScriptNodeType absoluteNumber = _unary(
  'math.abs',
  'Absolute',
  'Drops the sign.',
  (a) => a.abs(),
);

final VisualScriptNodeType negateNumber = _unary(
  'math.negate',
  'Negate',
  'Flips the sign.',
  (a) => -a,
);

final VisualScriptNodeType signOfNumber = _unary(
  'math.sign',
  'Sign',
  'Gives -1, 0 or 1, depending on which side of zero the number is.',
  (a) => a == 0 ? 0 : a.sign,
);

final VisualScriptNodeType floorNumber = _unary(
  'math.floor',
  'Floor',
  'Rounds down to a whole number.',
  (a) => a.floorToDouble(),
);

final VisualScriptNodeType ceilNumber = _unary(
  'math.ceil',
  'Ceiling',
  'Rounds up to a whole number.',
  (a) => a.ceilToDouble(),
);

final VisualScriptNodeType roundNumber = _unary(
  'math.round',
  'Round',
  'Rounds to the nearest whole number.',
  (a) => a.roundToDouble(),
);

final VisualScriptNodeType squareRoot = _unary(
  'math.sqrt',
  'Square Root',
  'The square root. Negative input gives zero rather than a value no pin '
      'can carry.',
  (a) => a <= 0 ? 0 : math.sqrt(a),
);

final VisualScriptNodeType minimumNumber = _binary(
  'math.min',
  'Minimum',
  'The smaller of the two.',
  math.min,
);

final VisualScriptNodeType maximumNumber = _binary(
  'math.max',
  'Maximum',
  'The larger of the two.',
  math.max,
);

final VisualScriptNodeType powerNumber = _binary(
  'math.power',
  'Power',
  'A raised to B.',
  (a, b) => math.pow(a, b).toDouble(),
  defaultB: 2,
);

final VisualScriptNodeType moduloNumber = _binary(
  'math.modulo',
  'Modulo',
  'The remainder of A divided by B. A B of zero gives zero rather than '
      'stopping the graph.',
  (a, b) => b == 0 ? 0 : a % b,
  defaultB: 1,
);

final VisualScriptNodeType degreesToRadians = _unary(
  'math.toRadians',
  'To Radians',
  'Turns degrees into radians.',
  (a) => a * degrees2Radians,
);

final VisualScriptNodeType radiansToDegrees = _unary(
  'math.toDegrees',
  'To Degrees',
  'Turns radians into degrees.',
  (a) => a * radians2Degrees,
);

final VisualScriptNodeType sineOf = _unary(
  'math.sin',
  'Sine',
  'The sine of an angle in degrees.',
  (a) => math.sin(a * degrees2Radians),
  category: 'Math',
);

final VisualScriptNodeType cosineOf = _unary(
  'math.cos',
  'Cosine',
  'The cosine of an angle in degrees.',
  (a) => math.cos(a * degrees2Radians),
);

final VisualScriptNodeType tangentOf = _unary(
  'math.tan',
  'Tangent',
  'The tangent of an angle in degrees.',
  (a) => math.tan(a * degrees2Radians),
);

final VisualScriptNodeType arcTangent2 = _binary(
  'math.atan2',
  'Arc Tangent 2',
  'The angle in degrees from the X axis to the point (B, A). This is the '
      'one that gives a heading from an offset.',
  (a, b) => math.atan2(a, b) * radians2Degrees,
);

final VisualScriptNodeType remapNumber = VisualScriptNodeType(
  id: 'math.remap',
  label: 'Remap',
  category: 'Math',
  doc:
      'Moves a value from one range to another — 5 in 0..10 becomes 0.5 in '
      '0..1. A source range of zero width gives the target\'s start.',
  pins: [
    _in('input', 'Value', VisualScriptType.number, defaultValue: 0.0),
    _in('fromMin', 'From Min', VisualScriptType.number, defaultValue: 0.0),
    _in('fromMax', 'From Max', VisualScriptType.number, defaultValue: 1.0),
    _in('toMin', 'To Min', VisualScriptType.number, defaultValue: 0.0),
    _in('toMax', 'To Max', VisualScriptType.number, defaultValue: 1.0),
    _in(
      'clamp',
      'Clamp',
      VisualScriptType.boolean,
      defaultValue: true,
      doc: 'Whether a value outside the source range stays inside the target.',
    ),
    _outPin('value', 'Value', VisualScriptType.number),
  ],
  evaluate: (context, node, inputs) {
    final fromMin = scriptNumber(inputs['fromMin']);
    final fromMax = scriptNumber(inputs['fromMax'], 1);
    final toMin = scriptNumber(inputs['toMin']);
    final toMax = scriptNumber(inputs['toMax'], 1);
    final span = fromMax - fromMin;
    if (span == 0) return _out({'value': toMin});
    var t = (scriptNumber(inputs['input']) - fromMin) / span;
    if (scriptBool(inputs['clamp'], true)) t = t.clamp(0.0, 1.0);
    return _out({'value': toMin + (toMax - toMin) * t});
  },
);

final VisualScriptNodeType inverseLerp = VisualScriptNodeType(
  id: 'math.inverseLerp',
  label: 'Inverse Lerp',
  category: 'Math',
  doc: 'Where Value sits between A and B, as 0 to 1. The opposite of Lerp.',
  pins: [
    _in('a', 'A', VisualScriptType.number, defaultValue: 0.0),
    _in('b', 'B', VisualScriptType.number, defaultValue: 1.0),
    _in('value', 'Value', VisualScriptType.number, defaultValue: 0.0),
    _outPin('t', 'T', VisualScriptType.number),
  ],
  evaluate: (context, node, inputs) {
    final a = scriptNumber(inputs['a']);
    final b = scriptNumber(inputs['b'], 1);
    if (a == b) return _out({'t': 0.0});
    return _out({'t': ((scriptNumber(inputs['value']) - a) / (b - a))});
  },
);

final VisualScriptNodeType moveTowardsNumber = VisualScriptNodeType(
  id: 'math.moveTowards',
  label: 'Move Towards',
  category: 'Math',
  doc:
      'Steps Current towards Target by at most Max Delta, without '
      'overshooting. This is the one to use for a value that should arrive.',
  pins: [
    _in('current', 'Current', VisualScriptType.number, defaultValue: 0.0),
    _in('target', 'Target', VisualScriptType.number, defaultValue: 0.0),
    _in('maxDelta', 'Max Delta', VisualScriptType.number, defaultValue: 1.0),
    _outPin('value', 'Value', VisualScriptType.number),
  ],
  evaluate: (context, node, inputs) {
    final current = scriptNumber(inputs['current']);
    final target = scriptNumber(inputs['target']);
    final maxDelta = scriptNumber(inputs['maxDelta'], 1).abs();
    final difference = target - current;
    if (difference.abs() <= maxDelta) return _out({'value': target});
    return _out({'value': current + difference.sign * maxDelta});
  },
);

final VisualScriptNodeType smoothStep = VisualScriptNodeType(
  id: 'math.smoothStep',
  label: 'Smooth Step',
  category: 'Math',
  doc:
      'Like Lerp, but eased in and out at both ends, so a value driven by it '
      'starts and stops rather than snapping into motion.',
  pins: [
    _in('a', 'A', VisualScriptType.number, defaultValue: 0.0),
    _in('b', 'B', VisualScriptType.number, defaultValue: 1.0),
    _in('t', 'T', VisualScriptType.number, defaultValue: 0.0),
    _outPin('value', 'Value', VisualScriptType.number),
  ],
  evaluate: (context, node, inputs) {
    final t = scriptNumber(inputs['t']).clamp(0.0, 1.0);
    final eased = t * t * (3 - 2 * t);
    final a = scriptNumber(inputs['a']);
    final b = scriptNumber(inputs['b'], 1);
    return _out({'value': a + (b - a) * eased});
  },
);

final VisualScriptNodeType randomInteger = VisualScriptNodeType(
  id: 'math.randomInteger',
  label: 'Random Integer',
  category: 'Math',
  doc: 'A whole number from Min up to but not including Max.',
  pins: [
    _in('min', 'Min', VisualScriptType.integer, defaultValue: 0),
    _in('max', 'Max', VisualScriptType.integer, defaultValue: 100),
    _outPin('value', 'Value', VisualScriptType.integer),
  ],
  evaluate: (context, node, inputs) {
    final min = scriptInteger(inputs['min']);
    final max = scriptInteger(inputs['max'], 100);
    if (max <= min) return _out({'value': min});
    return _out({'value': min + _random.nextInt(max - min)});
  },
);

final VisualScriptNodeType randomBoolean = VisualScriptNodeType(
  id: 'math.randomBoolean',
  label: 'Random Boolean',
  category: 'Math',
  doc: 'True as often as Chance says, which is half the time by default.',
  pins: [
    _in('chance', 'Chance', VisualScriptType.number, defaultValue: 0.5),
    _outPin('value', 'Value', VisualScriptType.boolean),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': _random.nextDouble() < scriptNumber(inputs['chance'])}),
);

// A shared generator, unseeded: a graph asking for randomness wants different
// answers on different runs.
final math.Random _random = math.Random();

// ---------------------------------------------------------------------------
// Vectors.
// ---------------------------------------------------------------------------

final VisualScriptNodeType subtractVectors = _vectorPair(
  'vector.subtract',
  'Subtract Vectors',
  'A minus B. The offset from B to A.',
  (a, b) => a - b,
);

final VisualScriptNodeType multiplyVectors = _vectorPair(
  'vector.multiply',
  'Multiply Vectors',
  'Component by component.',
  (a, b) => Vector3(a.x * b.x, a.y * b.y, a.z * b.z),
);

final VisualScriptNodeType crossProduct = _vectorPair(
  'vector.cross',
  'Cross Product',
  'A vector at right angles to both, whose length is the area they span.',
  (a, b) => a.cross(b),
);

final VisualScriptNodeType vectorLength = _vectorToNumber(
  'vector.length',
  'Length',
  'How long the vector is.',
  (a) => a.length,
);

final VisualScriptNodeType normalizeVector = VisualScriptNodeType(
  id: 'vector.normalize',
  label: 'Normalize',
  category: 'Vector',
  doc:
      'The same direction, one unit long. A zero vector has no direction, so '
      'it comes back unchanged rather than as a division by zero.',
  pins: [
    _in('a', 'A', VisualScriptType.vector3),
    _outPin('value', 'Value', VisualScriptType.vector3),
  ],
  evaluate: (context, node, inputs) {
    final a = scriptVector(inputs['a']);
    return _out({'value': a.length == 0 ? a : a.normalized()});
  },
);

final VisualScriptNodeType dotProduct = VisualScriptNodeType(
  id: 'vector.dot',
  label: 'Dot Product',
  category: 'Vector',
  doc:
      'How much the two point the same way: 1 for the same direction, 0 for '
      'at right angles, -1 for opposite, when both are one unit long.',
  pins: [
    _in('a', 'A', VisualScriptType.vector3),
    _in('b', 'B', VisualScriptType.vector3),
    _outPin('value', 'Value', VisualScriptType.number),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': scriptVector(inputs['a']).dot(scriptVector(inputs['b']))}),
);

final VisualScriptNodeType distanceBetween = VisualScriptNodeType(
  id: 'vector.distance',
  label: 'Distance',
  category: 'Vector',
  doc: 'How far apart two points are.',
  pins: [
    _in('a', 'A', VisualScriptType.vector3),
    _in('b', 'B', VisualScriptType.vector3),
    _outPin('value', 'Value', VisualScriptType.number),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': scriptVector(inputs['a']).distanceTo(scriptVector(inputs['b'])),
  }),
);

final VisualScriptNodeType lerpVector = VisualScriptNodeType(
  id: 'vector.lerp',
  label: 'Lerp Vectors',
  category: 'Vector',
  doc: 'A point T of the way from A to B.',
  pins: [
    _in('a', 'A', VisualScriptType.vector3),
    _in('b', 'B', VisualScriptType.vector3),
    _in('t', 'T', VisualScriptType.number, defaultValue: 0.5),
    _outPin('value', 'Value', VisualScriptType.vector3),
  ],
  evaluate: (context, node, inputs) {
    final a = scriptVector(inputs['a']);
    final b = scriptVector(inputs['b']);
    final t = scriptNumber(inputs['t'], 0.5);
    return _out({'value': a + (b - a) * t});
  },
);

final VisualScriptNodeType moveTowardsVector = VisualScriptNodeType(
  id: 'vector.moveTowards',
  label: 'Move Towards',
  category: 'Vector',
  doc: 'Steps Current towards Target by at most Max Distance.',
  pins: [
    _in('current', 'Current', VisualScriptType.vector3),
    _in('target', 'Target', VisualScriptType.vector3),
    _in(
      'maxDistance',
      'Max Distance',
      VisualScriptType.number,
      defaultValue: 1.0,
    ),
    _outPin('value', 'Value', VisualScriptType.vector3),
  ],
  evaluate: (context, node, inputs) {
    final current = scriptVector(inputs['current']);
    final target = scriptVector(inputs['target']);
    final maxDistance = scriptNumber(inputs['maxDistance'], 1).abs();
    final offset = target - current;
    if (offset.length <= maxDistance || offset.length == 0) {
      return _out({'value': target});
    }
    return _out({'value': current + offset.normalized() * maxDistance});
  },
);

final VisualScriptNodeType projectOnVector = VisualScriptNodeType(
  id: 'vector.project',
  label: 'Project',
  category: 'Vector',
  doc: 'The part of A that lies along B.',
  pins: [
    _in('a', 'A', VisualScriptType.vector3),
    _in('b', 'On', VisualScriptType.vector3),
    _outPin('value', 'Value', VisualScriptType.vector3),
  ],
  evaluate: (context, node, inputs) {
    final a = scriptVector(inputs['a']);
    final b = scriptVector(inputs['b']);
    final lengthSquared = b.length2;
    if (lengthSquared == 0) return _out({'value': Vector3.zero()});
    return _out({'value': b * (a.dot(b) / lengthSquared)});
  },
);

final VisualScriptNodeType reflectVector = VisualScriptNodeType(
  id: 'vector.reflect',
  label: 'Reflect',
  category: 'Vector',
  doc: 'A bounced off a surface facing Normal.',
  pins: [
    _in('a', 'A', VisualScriptType.vector3),
    _in('normal', 'Normal', VisualScriptType.vector3),
    _outPin('value', 'Value', VisualScriptType.vector3),
  ],
  evaluate: (context, node, inputs) {
    final a = scriptVector(inputs['a']);
    final normal = scriptVector(inputs['normal']);
    if (normal.length == 0) return _out({'value': a});
    final unit = normal.normalized();
    return _out({'value': a - unit * (2 * a.dot(unit))});
  },
);

final VisualScriptNodeType angleBetween = VisualScriptNodeType(
  id: 'vector.angle',
  label: 'Angle Between',
  category: 'Vector',
  doc: 'The angle in degrees between two directions.',
  pins: [
    _in('a', 'A', VisualScriptType.vector3),
    _in('b', 'B', VisualScriptType.vector3),
    _outPin('value', 'Value', VisualScriptType.number),
  ],
  evaluate: (context, node, inputs) {
    final a = scriptVector(inputs['a']);
    final b = scriptVector(inputs['b']);
    if (a.length == 0 || b.length == 0) return _out({'value': 0.0});
    final cosine = (a.dot(b) / (a.length * b.length)).clamp(-1.0, 1.0);
    return _out({'value': math.acos(cosine) * radians2Degrees});
  },
);

// ---------------------------------------------------------------------------
// Rotations.
// ---------------------------------------------------------------------------

final VisualScriptNodeType makeRotation = VisualScriptNodeType(
  id: 'rotation.fromEuler',
  label: 'Make Rotation',
  category: 'Rotation',
  doc: 'A rotation from pitch, yaw and roll in degrees.',
  pins: [
    _in('pitch', 'Pitch (X)', VisualScriptType.number, defaultValue: 0.0),
    _in('yaw', 'Yaw (Y)', VisualScriptType.number, defaultValue: 0.0),
    _in('roll', 'Roll (Z)', VisualScriptType.number, defaultValue: 0.0),
    _outPin('value', 'Value', VisualScriptType.quaternion),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': Quaternion.euler(
      scriptNumber(inputs['yaw']) * degrees2Radians,
      scriptNumber(inputs['pitch']) * degrees2Radians,
      scriptNumber(inputs['roll']) * degrees2Radians,
    ),
  }),
);

final VisualScriptNodeType combineRotations = VisualScriptNodeType(
  id: 'rotation.combine',
  label: 'Combine Rotations',
  category: 'Rotation',
  doc: 'A then B. Order matters: rotations do not commute.',
  pins: [
    _in('a', 'A', VisualScriptType.quaternion),
    _in('b', 'B', VisualScriptType.quaternion),
    _outPin('value', 'Value', VisualScriptType.quaternion),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': scriptQuaternion(inputs['b']) * scriptQuaternion(inputs['a']),
  }),
);

final VisualScriptNodeType invertRotation = VisualScriptNodeType(
  id: 'rotation.invert',
  label: 'Invert Rotation',
  category: 'Rotation',
  doc: 'The rotation that undoes this one.',
  pins: [
    _in('a', 'A', VisualScriptType.quaternion),
    _outPin('value', 'Value', VisualScriptType.quaternion),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': scriptQuaternion(inputs['a']).conjugated()}),
);

final VisualScriptNodeType rotateVector = VisualScriptNodeType(
  id: 'rotation.rotateVector',
  label: 'Rotate Vector',
  category: 'Rotation',
  doc: 'Turns a direction by a rotation.',
  pins: [
    _in('rotation', 'Rotation', VisualScriptType.quaternion),
    _in('vector', 'Vector', VisualScriptType.vector3),
    _outPin('value', 'Value', VisualScriptType.vector3),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': rotateVectorBy(
      scriptQuaternion(inputs['rotation']),
      scriptVector(inputs['vector']),
    ),
  }),
);

/// [v] rotated by [q], on the same side of the argument as the scene graph.
///
/// **Not `Quaternion.rotate` or `rotated`.** vector_math's pair compute
/// `conjugate(q) * v * q`, which is the *inverse* of the rotation
/// `Matrix4.compose` builds from the same quaternion — and every transform in
/// this engine is on the matrix side. The two agree for the identity and for
/// any single-axis rotation, so the wrong one passes every simple test and
/// only diverges once a rotation is compound enough to notice.
///
/// `flutter_scene`'s `QuaternionRotate.rotateVector` is the same maths and the
/// canonical spelling; this package sits underneath that one and cannot reach
/// it, so the formula is written out rather than the convention guessed at.
/// {@category Visual scripting}
Vector3 rotateVectorBy(Quaternion q, Vector3 v) {
  // v + 2w(a x v) + 2(a x (a x v)), for the axis part `a` of the quaternion.
  final cx = q.y * v.z - q.z * v.y;
  final cy = q.z * v.x - q.x * v.z;
  final cz = q.x * v.y - q.y * v.x;
  return Vector3(
    v.x + 2.0 * (q.w * cx + q.y * cz - q.z * cy),
    v.y + 2.0 * (q.w * cy + q.z * cx - q.x * cz),
    v.z + 2.0 * (q.w * cz + q.x * cy - q.y * cx),
  );
}

final VisualScriptNodeType slerpRotations = VisualScriptNodeType(
  id: 'rotation.slerp',
  label: 'Blend Rotations',
  category: 'Rotation',
  doc:
      'A rotation T of the way from A to B, taking the short way round. This '
      'is what a turn should be blended with, not a Lerp of the angles.',
  pins: [
    _in('a', 'A', VisualScriptType.quaternion),
    _in('b', 'B', VisualScriptType.quaternion),
    _in('t', 'T', VisualScriptType.number, defaultValue: 0.5),
    _outPin('value', 'Value', VisualScriptType.quaternion),
  ],
  evaluate: (context, node, inputs) {
    final a = scriptQuaternion(inputs['a']);
    final b = scriptQuaternion(inputs['b']);
    final t = scriptNumber(inputs['t'], 0.5).clamp(0.0, 1.0);
    return _out({'value': _slerp(a, b, t)});
  },
);

/// Spherical blend from [a] to [b], taking the shorter arc.
Quaternion _slerp(Quaternion a, Quaternion b, double t) {
  var cosine = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
  var end = b;
  // Two quaternions describe every rotation, and one of the pair is the long
  // way round. Flipping the sign picks the short one.
  if (cosine < 0) {
    end = Quaternion(-b.x, -b.y, -b.z, -b.w);
    cosine = -cosine;
  }
  if (cosine > 0.9995) {
    // Close enough that the arc is a straight line, and the sine below would
    // be dividing by nearly nothing.
    return Quaternion(
      a.x + (end.x - a.x) * t,
      a.y + (end.y - a.y) * t,
      a.z + (end.z - a.z) * t,
      a.w + (end.w - a.w) * t,
    )..normalize();
  }
  final angle = math.acos(cosine);
  final sine = math.sin(angle);
  final from = math.sin((1 - t) * angle) / sine;
  final to = math.sin(t * angle) / sine;
  return Quaternion(
    a.x * from + end.x * to,
    a.y * from + end.y * to,
    a.z * from + end.z * to,
    a.w * from + end.w * to,
  )..normalize();
}

// ---------------------------------------------------------------------------
// Comparison.
// ---------------------------------------------------------------------------

VisualScriptNodeType _compare(
  String id,
  String label,
  String doc,
  bool Function(double a, double b) compute,
) => VisualScriptNodeType(
  id: id,
  label: label,
  category: 'Logic',
  doc: doc,
  pins: [
    _in('a', 'A', VisualScriptType.number, defaultValue: 0.0),
    _in('b', 'B', VisualScriptType.number, defaultValue: 0.0),
    _outPin('value', 'Value', VisualScriptType.boolean),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': compute(scriptNumber(inputs['a']), scriptNumber(inputs['b'])),
  }),
);

final VisualScriptNodeType numberAtLeast = _compare(
  'logic.greaterOrEqual',
  'Greater Or Equal',
  'Whether A is at least B.',
  (a, b) => a >= b,
);

final VisualScriptNodeType numberAtMost = _compare(
  'logic.lessOrEqual',
  'Less Or Equal',
  'Whether A is at most B.',
  (a, b) => a <= b,
);

final VisualScriptNodeType valuesEqual = VisualScriptNodeType(
  id: 'logic.equalValues',
  label: 'Equal',
  category: 'Logic',
  doc:
      'Whether two values are the same. Works on anything, not just numbers — '
      'strings, vectors, nothing at all.',
  pins: [
    _in('a', 'A', VisualScriptType.any),
    _in('b', 'B', VisualScriptType.any),
    _outPin('value', 'Value', VisualScriptType.boolean),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': inputs['a'] == inputs['b']}),
);

final VisualScriptNodeType valuesNotEqual = VisualScriptNodeType(
  id: 'logic.notEqualValues',
  label: 'Not Equal',
  category: 'Logic',
  doc: 'Whether two values differ.',
  pins: [
    _in('a', 'A', VisualScriptType.any),
    _in('b', 'B', VisualScriptType.any),
    _outPin('value', 'Value', VisualScriptType.boolean),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': inputs['a'] != inputs['b']}),
);

final VisualScriptNodeType exclusiveOr = VisualScriptNodeType(
  id: 'logic.xor',
  label: 'Exclusive Or',
  category: 'Logic',
  doc: 'True when exactly one of the two is true.',
  pins: [
    _in('a', 'A', VisualScriptType.boolean, defaultValue: false),
    _in('b', 'B', VisualScriptType.boolean, defaultValue: false),
    _outPin('value', 'Value', VisualScriptType.boolean),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': scriptBool(inputs['a']) != scriptBool(inputs['b'])}),
);

final VisualScriptNodeType numberInRange = VisualScriptNodeType(
  id: 'logic.inRange',
  label: 'In Range',
  category: 'Logic',
  doc: 'Whether a number sits between Min and Max.',
  pins: [
    _in('input', 'Value', VisualScriptType.number, defaultValue: 0.0),
    _in('min', 'Min', VisualScriptType.number, defaultValue: 0.0),
    _in('max', 'Max', VisualScriptType.number, defaultValue: 1.0),
    _outPin('value', 'Value', VisualScriptType.boolean),
  ],
  evaluate: (context, node, inputs) {
    final value = scriptNumber(inputs['input']);
    final min = scriptNumber(inputs['min']);
    final max = scriptNumber(inputs['max'], 1);
    return _out({'value': value >= min && value <= max});
  },
);

/// Every maths, vector, rotation and comparison node here.
/// {@category Visual scripting}
final List<VisualScriptNodeType> mathVisualScriptNodes = [
  absoluteNumber,
  negateNumber,
  signOfNumber,
  floorNumber,
  ceilNumber,
  roundNumber,
  squareRoot,
  minimumNumber,
  maximumNumber,
  powerNumber,
  moduloNumber,
  degreesToRadians,
  radiansToDegrees,
  sineOf,
  cosineOf,
  tangentOf,
  arcTangent2,
  remapNumber,
  inverseLerp,
  moveTowardsNumber,
  smoothStep,
  randomInteger,
  randomBoolean,
  subtractVectors,
  multiplyVectors,
  crossProduct,
  vectorLength,
  normalizeVector,
  dotProduct,
  distanceBetween,
  lerpVector,
  moveTowardsVector,
  projectOnVector,
  reflectVector,
  angleBetween,
  makeRotation,
  combineRotations,
  invertRotation,
  rotateVector,
  slerpRotations,
  numberAtLeast,
  numberAtMost,
  valuesEqual,
  valuesNotEqual,
  exclusiveOr,
  numberInRange,
];
