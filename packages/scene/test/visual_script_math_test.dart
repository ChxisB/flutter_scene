// The maths, vector and rotation nodes, and the text and collection ones.
//
// Mostly these are one-liners over `dart:math`, so what is worth a test is the
// edges: the divisions that could be by zero, and the rotation convention that
// silently disagrees with vector_math.

import 'package:scene/visual_script.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Pulls [pin] off a node of [type] built with [literals].
Object? evaluate(String type, Map<String, Object?> literals, [String? pin]) {
  final graph = VisualScriptGraph();
  final node = graph.add(type);
  node.literals.addAll(literals);
  final context = VisualScriptContext(
    graph: graph,
    host: NullVisualScriptHost(),
  );
  return VisualScriptInterpreter(
    standardVisualScriptRegistry(),
  ).evaluateOutput(context, node.id, pin ?? 'value');
}

void main() {
  group('rotations', () {
    test('rotating a vector agrees with the matrix the engine builds', () {
      // The whole point of rotateVectorBy. vector_math's own `rotated`
      // computes the inverse, and the two only diverge once a rotation is
      // compound — which is why this test uses one that is.
      final rotation = Quaternion.euler(0.9, 0.4, 0.2);
      final vector = Vector3(1, 2, 3);
      final byMatrix = Matrix4.compose(
        Vector3.zero(),
        rotation,
        Vector3.all(1),
      ).transformed3(vector.clone());

      final byNode = rotateVectorBy(rotation, vector);
      expect(byNode.x, closeTo(byMatrix.x, 1e-9));
      expect(byNode.y, closeTo(byMatrix.y, 1e-9));
      expect(byNode.z, closeTo(byMatrix.z, 1e-9));
    });

    test('and disagrees with vector_math, which is the trap', () {
      // If this ever passes, vector_math changed its convention and the
      // comment on rotateVectorBy needs revisiting rather than deleting.
      final rotation = Quaternion.euler(0.9, 0.4, 0.2);
      final vector = Vector3(1, 2, 3);
      expect(
        rotateVectorBy(rotation, vector).x,
        isNot(closeTo(rotation.rotated(vector).x, 1e-6)),
      );
    });

    test('the Rotate Vector node uses the engine convention', () {
      final rotation = Quaternion.euler(0.9, 0.4, 0.2);
      final result = evaluate('rotation.rotateVector', {
        'rotation': rotation,
        'vector': Vector3(1, 2, 3),
      });
      expect(result, isA<Vector3>());
      final expected = rotateVectorBy(rotation, Vector3(1, 2, 3));
      expect((result! as Vector3).x, closeTo(expected.x, 1e-9));
    });

    test('blending two rotations takes the short way round', () {
      final a = Quaternion.euler(0, 0, 0);
      // The negated form of a 170-degree turn: the same rotation, expressed
      // as the long way round. A blend that did not check the sign would
      // sweep 190 degrees to reach it.
      final far = Quaternion.euler(170 * degrees2Radians, 0, 0);
      final half =
          evaluate('rotation.slerp', {
                'a': a,
                'b': Quaternion(-far.x, -far.y, -far.z, -far.w),
                't': 0.5,
              })!
              as Quaternion;
      final direct =
          evaluate('rotation.slerp', {'a': a, 'b': far, 't': 0.5})!
              as Quaternion;
      // Same rotation either way, up to the sign that names it.
      expect(half.x.abs(), closeTo(direct.x.abs(), 1e-6));
    });

    test('combining rotations applies A and then B', () {
      final turn = Quaternion.euler(90 * degrees2Radians, 0, 0);
      final twice =
          evaluate('rotation.combine', {'a': turn, 'b': turn})! as Quaternion;
      final pointed = rotateVectorBy(twice, Vector3(0, 0, 1));
      // Two 90-degree yaws face the opposite way.
      expect(pointed.z, closeTo(-1, 1e-6));
    });
  });

  group('maths that could divide by zero', () {
    test('normalizing a zero vector gives it back rather than NaN', () {
      final result =
          evaluate('vector.normalize', {'a': Vector3.zero()})! as Vector3;
      expect(result.x, 0);
      expect(result.x.isNaN, isFalse);
    });

    test('a modulo by zero is zero', () {
      expect(evaluate('math.modulo', {'a': 5.0, 'b': 0.0}), 0.0);
    });

    test('a square root of a negative number is zero', () {
      expect(evaluate('math.sqrt', {'a': -4.0}), 0.0);
    });

    test('remapping from a range of no width gives the target start', () {
      expect(
        evaluate('math.remap', {
          'input': 5.0,
          'fromMin': 2.0,
          'fromMax': 2.0,
          'toMin': 7.0,
          'toMax': 9.0,
        }),
        7.0,
      );
    });

    test('the angle between a vector and nothing is zero, not NaN', () {
      expect(
        evaluate('vector.angle', {'a': Vector3(1, 0, 0), 'b': Vector3.zero()}),
        0.0,
      );
    });

    test('projecting onto nothing gives nothing', () {
      final result =
          evaluate('vector.project', {
                'a': Vector3(1, 2, 3),
                'b': Vector3.zero(),
              })!
              as Vector3;
      expect(result, Vector3.zero());
    });
  });

  group('maths that arrives', () {
    test('Move Towards does not overshoot', () {
      expect(
        evaluate('math.moveTowards', {
          'current': 0.0,
          'target': 1.0,
          'maxDelta': 5.0,
        }),
        1.0,
      );
    });

    test('Move Towards steps by the delta when it is further', () {
      expect(
        evaluate('math.moveTowards', {
          'current': 0.0,
          'target': 10.0,
          'maxDelta': 2.0,
        }),
        2.0,
      );
    });

    test('Remap clamps by default and can be told not to', () {
      expect(
        evaluate('math.remap', {'input': 20.0, 'fromMax': 10.0}),
        1.0,
        reason: 'clamped',
      );
      expect(
        evaluate('math.remap', {
          'input': 20.0,
          'fromMax': 10.0,
          'clamp': false,
        }),
        2.0,
      );
    });
  });

  group('text', () {
    test('Format Text fills the slots it was given and leaves the rest', () {
      expect(
        evaluate('text.format', {
          'template': '{0} of {1}, and {2}',
          '0': 3,
          '1': 'five',
        }),
        '3 of five, and {2}',
      );
    });

    test('Replace with an empty needle leaves the text alone', () {
      expect(
        evaluate('text.replace', {'a': 'abc', 'find': '', 'replace': 'X'}),
        'abc',
      );
    });

    test('Split with an empty separator gives the whole text', () {
      expect(evaluate('text.split', {'a': 'abc', 'separator': ''}), ['abc']);
    });

    test('Text To Number says whether it managed', () {
      expect(evaluate('text.toNumber', {'a': ' 2.5 '}), 2.5);
      expect(evaluate('text.toNumber', {'a': 'x'}, 'ok'), isFalse);
      expect(evaluate('text.toNumber', {'a': 'x', 'fallback': 9.0}), 9.0);
    });
  });

  group('collections', () {
    test('an index outside a list gives nothing and says so', () {
      expect(
        evaluate('list.get', {
          'list': <Object?>['a'],
          'index': 4,
        }, 'found'),
        isFalse,
      );
      expect(
        evaluate('list.get', {
          'list': <Object?>['a'],
          'index': 4,
        }),
        isNull,
      );
    });

    test('Reverse leaves the original alone', () {
      final original = <Object?>[1, 2, 3];
      expect(evaluate('list.reverse', {'list': original}), [3, 2, 1]);
      expect(original, [1, 2, 3]);
    });

    test('a dictionary distinguishes a missing key from a null value', () {
      expect(
        evaluate('dict.get', {
          'dictionary': <String, Object?>{'a': null},
          'key': 'a',
        }, 'found'),
        isTrue,
      );
      expect(
        evaluate('dict.get', {
          'dictionary': <String, Object?>{'a': null},
          'key': 'b',
        }, 'found'),
        isFalse,
      );
    });
  });
}
