import 'package:flutter/material.dart';

import '../db.dart';
import 'loading.dart';
import 'trip_screen.dart';

/// "Which person are you?" Shown after joining, and from the People tab.
class PersonPickerScreen extends StatefulWidget {
  final String tripId;
  final bool openTripAfter;
  const PersonPickerScreen({super.key, required this.tripId, this.openTripAfter = false});

  @override
  State<PersonPickerScreen> createState() => _PersonPickerScreenState();
}

class _PersonPickerScreenState extends State<PersonPickerScreen> {
  final _name = TextEditingController();
  bool _done = false;

  void _finish(void Function() write) {
    if (_done) return;
    _done = true;
    write();
    if (widget.openTripAfter) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TripScreen(tripId: widget.tripId)));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Which person are you?')),
      body: StreamBuilder(
        stream: people(widget.tripId).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Could not load people.\n${snap.error}'));
          if (!snap.hasData) return const Loading('Loading people…');
          final list = snap.data!.docs.map(Person.new).toList()..sort((a, b) => a.name.compareTo(b.name));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Pick yourself so your expenses and balance show as yours.'),
              const SizedBox(height: 8),
              for (final p in list)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(p.name),
                  onTap: () => _finish(() => setMyPerson(widget.tripId, p.id)),
                ),
              const Divider(height: 32),
              const Text("Not in the list? Add yourself:"),
              Row(
                children: [
                  Expanded(child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Your name'))),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final n = _name.text.trim();
                      if (n.isNotEmpty) _finish(() => addMyself(widget.tripId, n));
                    },
                    child: const Text('Add me'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
