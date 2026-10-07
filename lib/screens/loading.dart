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

/// Centered icon, title and hint for a list with nothing in it yet.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, body;
  const EmptyState({super.key, required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 96), // sits a little above center, clear of the FAB
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text(title, style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
