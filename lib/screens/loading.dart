import 'dart:async';

import 'package:flutter/material.dart';

/// Spinner with what it's waiting for, plus a seconds counter once it's slow,
/// so a stuck step is visible ("Joining… 12s") instead of an endless spinner.
class Loading extends StatefulWidget {
  final String label;
  const Loading(this.label, {super.key});

  @override
  State<Loading> createState() => _LoadingState();
}

class _LoadingState extends State<Loading> {
  final _watch = Stopwatch()..start();
  late final Timer _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => setState(() {}));

  @override
  void didUpdateWidget(Loading old) {
    super.didUpdateWidget(old);
    if (old.label != widget.label) _watch.reset(); // time each step separately
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _watch.elapsed.inSeconds;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(s >= 2 ? '${widget.label} ${s}s' : widget.label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
