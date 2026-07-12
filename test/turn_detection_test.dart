import 'package:cylan/services/turn_detection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectTurns', () {
    test('returns nothing for a straight line', () {
      final turns = detectTurns(
        [0.0, 0.0, 0.0],
        [0.0, 0.01, 0.02],
        [0.0, 1.0, 2.0],
      );
      expect(turns, isEmpty);
    });

    test('detects a left turn (heading east, then north)', () {
      // East along the equator, then north — a ~90° left turn.
      final turns = detectTurns(
        [0.0, 0.0, 0.01],
        [0.0, 0.01, 0.01],
        [0.0, 1.0, 2.0],
      );
      expect(turns, hasLength(1));
      expect(turns.first.direction, 'left');
      expect(turns.first.kind, 'turn'); // ~90° -> 45..100
      expect(turns.first.angleDeg, closeTo(90, 2));
    });

    test('detects a right turn (heading east, then south)', () {
      final turns = detectTurns(
        [0.0, 0.0, -0.01],
        [0.0, 0.01, 0.01],
        [0.0, 1.0, 2.0],
      );
      expect(turns, hasLength(1));
      expect(turns.first.direction, 'right');
    });

    test('needs at least 3 points', () {
      expect(detectTurns([0, 0], [0, 1], [0, 1]), isEmpty);
    });
  });
}
