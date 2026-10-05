import 'dart:math';

/// Random Pay wheel physics: a wheel with friction, pegs on every segment
/// boundary, and a spring-loaded flapper at 12 o'clock that the pegs push.
///
/// Fixed-step and deterministic. Units: pixels and radians. Screen angles are
/// clockwise from 12 o'clock; the wheel spins clockwise (theta grows).
/// Segment i covers wheel angles [i, i+1) * 2π/n, matching the painter.
class WheelSim {
  WheelSim(this.n, {this.theta = 0});
  final int n;

  static const dt = 1 / 2000; // s per step

  // Geometry (px). The painter draws with the same numbers.
  static const radius = 140.0; // wheel
  static const pegRing = radius - 9; // peg centres
  static const pegRadius = 5.0;
  static const pivotY = -14.0; // flapper pivot, measured from the wheel's top edge
  static const flapLen = 40.0; // pivot to tip
  static const flapHalfWidth = 7.0; // at the pivot, tapering to 0 at the tip
  static const contactLever = 9 - pivotY; // pivot down to the peg ring
  static const contactGap = pegRadius + flapHalfWidth * (1 - contactLever / flapLen);
  static const maxFlap = 0.65; // rad; past this the peg slips by

  // Tuning.
  static const bearing = 0.25; // rad/s², constant friction: sets the slow crawl at the end
  static const drag = 0.3; // 1/s, speed-proportional friction: sets the fast phase
  static const springK = 3600.0; // flapper spring, 1/s² (~10 Hz)
  static const springDamp = 28.0; // 1/s
  // Flapper push on the wheel = spring torque / wheel inertia. A heavy (weighted)
  // wheel: the flapper can brake it and finally stop it on a peg, but never throw
  // it backwards (see _contact).
  static const coupling = 0.006;
  static const flapStop = 0.85; // rad; hard stops either side of the flapper

  double theta; // wheel rotation
  double omega = 0; // wheel speed, rad/s
  double phi = 0; // flapper angle; + = tip pushed clockwise
  double phiVel = 0;
  int clicks = 0; // pegs that slipped past the flapper (for haptics)

  int? _peg; // peg currently near the flapper
  int _side = -1; // -1: that peg is left of the flapper, +1: right of it
  bool _armed = true; // false right after a slip, until the peg is clear

  // Wheel stopped and the flapper settled (either centred, or leaning on a peg).
  bool get resting => omega == 0 && phiVel.abs() < 0.3 && _still > 0.25;
  double _still = 0; // seconds the wheel has been stopped

  void step() {
    // Flapper: damped spring back to centre.
    phiVel += (-springK * phi - springDamp * phiVel) * dt;
    phi += phiVel * dt;
    if (phi.abs() > flapStop) {
      // Bounces off its stop.
      phi = flapStop * phi.sign;
      phiVel = -0.3 * phiVel;
    }
    // Wheel: friction slows it and can stop it, but never reverses it.
    final slow = (bearing + drag * omega.abs()) * dt;
    omega = omega.abs() <= slow ? 0 : omega - slow * omega.sign;
    theta += omega * dt;
    _contact();
    _still = omega == 0 ? _still + dt : 0;
  }

  void _contact() {
    // Nearest peg to 12 o'clock, and its screen angle in (-π, π].
    final seg = 2 * pi / n;
    final i = ((-theta / seg).round()) % n;
    var a = (i * seg + theta) % (2 * pi);
    if (a > pi) a -= 2 * pi;
    if (a.abs() > 0.6) {
      _peg = null;
      return;
    }
    final xPeg = pegRing * sin(a); // sideways offset from the pivot line
    final xFlap = contactLever * sin(phi);
    if (_peg != i) {
      _peg = i;
      _side = xPeg < xFlap ? -1 : 1;
      _armed = true;
    }
    // The flapper must stay contactGap clear of the peg, on the peg's side.
    final need = xPeg - _side * contactGap;
    final violated = _side < 0 ? xFlap < need : xFlap > need;
    if (!violated) {
      _armed = true;
      return;
    }
    if (!_armed) return; // still sliding over the peg it just slipped past
    if (need.abs() > contactLever * sin(maxFlap)) {
      // Can't bend any further: the peg snaps past and the flapper springs back.
      _side = -_side;
      _armed = false;
      clicks++;
      phiVel *= 0.3; // the snap loses most of the flapper's speed
      return;
    }
    // The peg drags the flapper along, and the bent flapper pushes back on the wheel.
    final newPhi = asin(need / contactLever);
    phiVel = omega * pegRing * cos(a) / (contactLever * cos(newPhi));
    phi = newPhi;
    // The bent flapper acts as a brake: it can slow the wheel to a stop, never
    // reverse it. If stopped, the flapper stays leaning on the peg.
    final braked = omega - coupling * springK * phi * dt;
    omega = braked.sign == omega.sign ? braked : 0;
    if (omega == 0) phiVel = 0;
  }

  /// Index of the name the flapper tip points at.
  int get reading {
    final tipX = flapLen * sin(phi);
    final tipR = radius - (pivotY + flapLen * cos(phi)); // tip distance from wheel centre
    final s = atan2(tipX, tipR); // screen angle of the tip
    final w = ((s - theta) / (2 * pi)) % 1; // wheel angle under the tip, in turns
    return (w * n).floor() % n;
  }

  /// Runs to rest without drawing. Returns seconds taken.
  double runToRest({double maxSeconds = 60}) {
    var t = 0.0;
    do {
      step();
      t += dt;
    } while (!resting && t < maxSeconds);
    return t;
  }
}
