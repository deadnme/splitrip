import 'package:cloud_firestore/cloud_firestore.dart' show GetOptions, Query, Source;
import 'package:flutter/material.dart';

import '../db.dart';
import '../platform/browser.dart';
import '../format.dart';
import '../theme.dart';
import 'join_screen.dart';
import 'loading.dart';
import 'random_pay.dart';
import 'trip_screen.dart';

class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Image.asset('assets/logo.png', height: 36, semanticLabel: 'SpliTrip'),
        actions: [
          const ThemeToggle(),
          IconButton(
            tooltip: 'Quick Random Pay',
            icon: const Icon(Icons.casino_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuickRandomScreen())),
          ),
          IconButton(
            tooltip: 'Join trip',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JoinScreen())),
          ),
        ],
      ),
      body: Column(children: [
        if (isIosBrowserTab)
          const Card(
            margin: EdgeInsets.all(12),
            child: ListTile(
              leading: Icon(Icons.ios_share),
              title: Text('Add SpliTrip to your Home Screen'),
              subtitle: Text('Tap Share, then "Add to Home Screen", and use it from there. '
                  "Trips in Safari don't carry over to the Home Screen app."),
            ),
          ),
        const Expanded(child: _TripList()),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New trip'),
        onPressed: () => _createTrip(context),
      ),
    );
  }

  Future<void> _createTrip(BuildContext context) async {
    final name = TextEditingController();
    final me = TextEditingController();
    var currency = 'PHP';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New trip'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Trip name')),
              TextField(controller: me, decoration: const InputDecoration(labelText: 'Your name')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: currency,
                decoration: const InputDecoration(labelText: 'Currency'),
                items: [for (final c in currencies) DropdownMenuItem(value: c, child: Text('$c ${currencySymbol(c)}'))],
                onChanged: (v) => setState(() => currency = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    if (name.text.trim().isEmpty || me.text.trim().isEmpty) {
      showError('Enter a trip name and your name.');
      return;
    }
    final id = createTrip(name.text.trim(), currency, me.text.trim());
    Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(tripId: id)));
  }
}

/// My trips, live. Pull down to restart the listener and re-read the server.
class _TripList extends StatefulWidget {
  const _TripList();

  @override
  State<_TripList> createState() => _TripListState();
}

class _TripListState extends State<_TripList> {
  Query<Map<String, dynamic>> get _query => trips.where('memberUids', arrayContains: uid);
  late var _stream = _query.snapshots();

  Future<void> _refresh() async {
    setState(() => _stream = _query.snapshots());
    try {
      await _query.get(const GetOptions(source: Source.server));
    } catch (e) {
      showError('Could not refresh. Check your connection.\n$e');
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ScrollableEmpty(Center(child: Text('Could not load trips. Pull down to retry.\n${snap.error}'))),
            );
          }
          if (!snap.hasData) return const Loading('Loading your trips…');
          final list = snap.data!.docs.map(Trip.new).toList()
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          return RefreshIndicator(
            onRefresh: _refresh,
            child: list.isEmpty
                ? const ScrollableEmpty(EmptyState(
                    icon: Icons.luggage_outlined,
                    title: 'No trips yet',
                    body: 'Create one, or join with an invite code.',
                  ))
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      for (final t in list)
                        ListTile(
                          leading: CircleAvatar(child: Text(t.name.isEmpty ? '?' : t.name[0].toUpperCase())),
                          title: Text(t.name),
                          // Not memberUids.length: that counts devices that joined (every
                          // reinstall or browser adds one), not the people in the trip.
                          subtitle: Text(t.currency),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(tripId: t.id))),
                        ),
                    ],
                  ),
          );
        },
      );
}
