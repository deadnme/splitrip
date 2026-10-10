import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../wheel_physics.dart';

const _colors = [
  Color(0xFF4F46E5), Color(0xFFEC4899), Color(0xFF22C55E), Color(0xFFF97316),
  Color(0xFF06B6D4), Color(0xFFA855F7), Color(0xFFEAB308), Color(0xFFEF4444),
];

/// Wheel of names driven by [WheelSim]: a random push, friction, pegs and a
/// spring flapper decide who pays. The result is wherever it physically stops.
class RandomPayWheel extends StatefulWidget {
  final List<String> names;
  final ValueChanged<int> onWinner;
  final VoidCallback? onSpin;
  const RandomPayWheel({super.key, required this.names, required this.onWinner, this.onSpin});

  @override
  State<RandomPayWheel> createState() => _RandomPayWheelState();
}

class _RandomPayWheelState extends State<RandomPayWheel> with TickerProviderStateMixin {
  late final _sim = WheelSim(widget.names.length);
  late final Ticker _ticker = createTicker(_onTick);
  // Highlight animation for the winner. preserve: keep it even when the phone
  // has system animations off (Flutter would otherwise cut it to 5%).
  late final _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    animationBehavior: AnimationBehavior.preserve,
  );
  final _rng = Random.secure();
  Duration _last = Duration.zero;
  double _pending = 0; // unsimulated time, s
  int _clicks = 0;
  int? _winner;
  bool _busy = false;

  @override
  void dispose() {
    _ticker.dispose();
    _reveal.dispose();
    super.dispose();
  }

  void _spin() {
    widget.onSpin?.call();
    setState(() {
      _busy = true;
      _winner = null;
      _reveal.value = 0;
    });
    // Random push; the spread is many turns wide, so every name is equally likely
    // (checked by test/wheel_test.dart).
    _sim.omega = 26 + 12 * _rng.nextDouble();
    _last = Duration.zero;
    _pending = 0;
    _ticker.start();
  }

  void _onTick(Duration now) {
    // Real time drives fixed physics steps, so it looks the same on any frame rate.
    _pending += min((now - _last).inMicroseconds / 1e6, 0.05);
    _last = now;
    while (_pending >= WheelSim.dt) {
      _sim.step();
      _pending -= WheelSim.dt;
    }
    if (_sim.clicks != _clicks) {
      _clicks = _sim.clicks;
      HapticFeedback.selectionClick();
    }
    if (_sim.resting) {
      _ticker.stop();
      _finish();
    }
    setState(() {});
  }

  Future<void> _finish() async {
    await Future.delayed(const Duration(milliseconds: 350)); // let it settle
    if (!mounted) return;
    final w = _sim.reading;
    setState(() {
      _busy = false;
      _winner = w;
    });
    HapticFeedback.mediumImpact();
    _reveal.forward(from: 0);
    widget.onWinner(w);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.names.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _reveal,
          builder: (context, _) => CustomPaint(
            size: const Size(2 * WheelSim.radius, 2 * WheelSim.radius + _WheelPainter.top),
            painter: _WheelPainter(
              names: widget.names,
              theta: _sim.theta,
              phi: _sim.phi,
              winner: _winner,
              reveal: Curves.easeOutBack.transform(_reveal.value),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 28,
          child: _winner == null
              ? null
              : FadeTransition(
                  opacity: _reveal,
                  child: Text('${widget.names[_winner!]} pays this round!', style: Theme.of(context).textTheme.titleMedium),
                ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: n < 2 || _busy ? null : _spin,
          icon: const Icon(Icons.casino),
          label: Text(_busy ? 'Spinning…' : 'Spin the wheel'),
        ),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  static const top = 20.0; // room above the wheel for the flapper pivot

  final List<String> names;
  final double theta, phi, reveal;
  final int? winner;
  _WheelPainter({required this.names, required this.theta, required this.phi, required this.winner, required this.reveal});

  @override
  void paint(Canvas canvas, Size size) {
    final n = names.length;
    if (n == 0) return;
    const r = WheelSim.radius;
    final c = Offset(size.width / 2, top + r);
    final sweep = 2 * pi / n;
    final t = winner == null ? 0.0 : reveal; // 0..~1.1 (easeOutBack overshoots a little)

    void slice(int i, double radius) {
      // Canvas angle 0 is 3 o'clock; -pi/2 is 12 o'clock.
      final start = -pi / 2 + i * sweep + theta;
      final rect = Rect.fromCircle(center: c, radius: radius);
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(rect, start, sweep, false)
        ..close();
      final isWinner = i == winner;
      if (isWinner && t > 0) canvas.drawShadow(path, Colors.black, 10 * t, false);
      canvas.drawPath(path, Paint()..color = _colors[i % _colors.length]);
      if (!isWinner && t > 0) {
        // Everyone else fades into the dark.
        canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: (0.65 * t).clamp(0, 0.65)));
      }
      final label = names[i].length > 12 ? '${names[i].substring(0, 11)}…' : names[i];
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: isWinner || t == 0 ? 1 : (1 - 0.55 * t).clamp(0.3, 1)),
            fontSize: isWinner ? 14 + 5 * t : 14,
            fontWeight: isWinner && t > 0 ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(start + sweep / 2);
      tp.paint(canvas, Offset(radius - tp.width - 22, -tp.height / 2));
      canvas.restore();
    }

    for (var i = 0; i < n; i++) {
      if (i != winner) slice(i, r);
    }
    // The payer's slice last, so it sits on top, grown and lifted forward.
    if (winner != null) slice(winner!, r * (1 + 0.07 * t));

    // Pegs on every segment boundary: they catch the flapper.
    final peg = Paint()..color = Colors.white;
    final rim = Paint()
      ..color = Colors.black38
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < n; i++) {
      final a = -pi / 2 + i * sweep + theta;
      final p = c + Offset(cos(a), sin(a)) * WheelSim.pegRing;
      canvas.drawCircle(p, WheelSim.pegRadius, peg);
      canvas.drawCircle(p, WheelSim.pegRadius, rim);
    }

    // Flapper: hangs from its pivot above the rim, swung by phi.
    final pivot = Offset(c.dx, top + WheelSim.pivotY);
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(-phi); // +phi = tip pushed clockwise (right); canvas +rotation turns a down-pointing tip left
    final flap = Path()
      ..moveTo(-WheelSim.flapHalfWidth, 0)
      ..lineTo(WheelSim.flapHalfWidth, 0)
      ..lineTo(0, WheelSim.flapLen)
      ..close();
    canvas.drawShadow(flap, Colors.black, 3, false);
    canvas.drawPath(flap, Paint()..color = const Color(0xFFF43F5E));
    canvas.drawCircle(Offset.zero, 7, Paint()..color = Colors.white);
    canvas.drawCircle(Offset.zero, 3.5, Paint()..color = const Color(0xFFF43F5E));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WheelPainter old) => true; // redrawn every physics frame anyway
}

/// Bottom sheet: spin among the trip's people; "Use as payer" returns the winner's index.
Future<int?> showRandomPayer(BuildContext context, List<String> names) {
  int? winner;
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Random Pay', style: Theme.of(context).textTheme.titleLarge),
              const Text('Spin to pick who pays. Everyone has an equal chance.'),
              const SizedBox(height: 16),
              RandomPayWheel(
                names: names,
                onSpin: () => setState(() => winner = null),
                onWinner: (i) => setState(() => winner = i),
              ),
              const SizedBox(height: 8),
              // The payer only changes when you confirm (old app bug B-21 changed it on spin).
              TextButton(
                onPressed: winner == null ? null : () => Navigator.pop(context, winner),
                child: Text(winner == null ? 'Use as payer' : 'Use ${names[winner!]} as payer'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Standalone wheel: type any names, no trip needed.
class QuickRandomScreen extends StatefulWidget {
  const QuickRandomScreen({super.key});

  @override
  State<QuickRandomScreen> createState() => _QuickRandomScreenState();
}

class _QuickRandomScreenState extends State<QuickRandomScreen> {
  final _names = <String>[];
  final _input = TextEditingController();

  void _add() {
    final n = _input.text.trim();
    if (n.isEmpty) return;
    setState(() => _names.add(n));
    _input.clear();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Quick Random Pay')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Enter any names and spin the wheel to pick who pays. No trip or expense needed.'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  decoration: const InputDecoration(labelText: 'Add names to the wheel', hintText: 'Type a name and press Enter'),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(onPressed: _add, child: const Text('Add')),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (var i = 0; i < _names.length; i++)
                InputChip(
                  label: Text(_names[i]),
                  backgroundColor: _colors[i % _colors.length].withValues(alpha: 0.25),
                  onDeleted: () => setState(() => _names.removeAt(i)),
                ),
            ]),
            const SizedBox(height: 16),
            if (_names.length < 2)
              const Text('Add at least two names to enable the Random Pay wheel.', textAlign: TextAlign.center)
            else
              // Key on the names so editing the list resets the wheel.
              RandomPayWheel(key: ValueKey(_names.join('\u0000')), names: List.of(_names), onWinner: (_) {}),
          ],
        ),
      );
}
