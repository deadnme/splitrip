import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:splitrip/wheel_physics.dart';

void main() {
  test('every name has a fair chance, and spins end smoothly in a sane time', () {
    final rng = Random(42);
    for (final n in [2, 4, 7]) {
      final counts = List.filled(n, 0);
      final sim = WheelSim(n);
      const spins = 400;
      for (var s = 0; s < spins; s++) {
        sim.omega = 26 + 12 * rng.nextDouble(); // same range the UI uses
        final secs = sim.runToRest();
        expect(secs, inInclusiveRange(5, 25), reason: 'n=$n spin $s took ${secs}s');
        counts[sim.reading]++;
      }
      final expected = spins / n;
      for (var i = 0; i < n; i++) {
        // Loose bound: ~4 standard deviations for a fair wheel.
        expect(counts[i], inInclusiveRange(expected * 0.7, expected * 1.3), reason: 'n=$n counts=$counts');
      }
    }
  });

  test('the weighted wheel never bounces backwards, and sometimes stops on a peg', () {
    final rng = Random(7);
    final sim = WheelSim(5);
    var heldByPeg = 0;
    for (var s = 0; s < 200; s++) {
      sim.omega = 26 + 12 * rng.nextDouble();
      do {
        sim.step();
        expect(sim.omega, greaterThanOrEqualTo(0), reason: 'spin $s went backwards');
      } while (!sim.resting);
      if (sim.phi.abs() > 0.05) heldByPeg++; // came to rest with the flapper leaning on a peg
    }
    expect(heldByPeg, greaterThan(5));
  });

  test('pegs push the flapper even at full speed', () {
    final sim = WheelSim(4)..omega = 38;
    var maxFlap = 0.0;
    for (var i = 0; i < 2000; i++) {
      sim.step(); // first second only: still very fast
      maxFlap = max(maxFlap, sim.phi.abs());
    }
    expect(sim.clicks, greaterThan(15));
    expect(maxFlap, greaterThan(0.3));
  });
}
