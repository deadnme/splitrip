import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../db.dart';
import '../format.dart';

class TripSettingsScreen extends StatefulWidget {
  final Trip trip;
  final bool hasExpenses;
  const TripSettingsScreen({super.key, required this.trip, required this.hasExpenses});

  @override
  State<TripSettingsScreen> createState() => _TripSettingsScreenState();
}

class _TripSettingsScreenState extends State<TripSettingsScreen> {
  late final name = TextEditingController(text: widget.trip.name);
  late String currency = widget.trip.currency;

  @override
  Widget build(BuildContext context) {
    final t = widget.trip;
    final last = t.memberUids.length <= 1;
    return Scaffold(
      appBar: AppBar(title: const Text('Trip settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Invite code', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Anyone with this code can join. Keep it: it is also how you get back in after reinstalling.'),
          const SizedBox(height: 12),
          Center(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(data: inviteLink(t.inviteCode), size: 220, backgroundColor: Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: SelectableText(t.inviteCode,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 28, letterSpacing: 6, fontWeight: FontWeight.bold)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: t.inviteCode));
                  messengerKey.currentState?.showSnackBar(const SnackBar(content: Text('Copied')));
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.share),
                label: const Text('Share'),
                onPressed: () => SharePlus.instance.share(ShareParams(
                  text: 'Join "${t.name}" on SpliTrip: ${inviteLink(t.inviteCode)}\n(invite code ${t.inviteCode})',
                )),
              ),
            ],
          ),
          const Divider(height: 32),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Trip name')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: currency,
            decoration: InputDecoration(
              labelText: 'Currency',
              helperText: widget.hasExpenses ? 'Locked once the trip has expenses.' : null,
            ),
            items: [for (final c in currencies) DropdownMenuItem(value: c, child: Text('$c ${currencySymbol(c)}'))],
            onChanged: widget.hasExpenses ? null : (v) => setState(() => currency = v!),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final n = name.text.trim();
              if (n.isEmpty) return;
              fire(tripRef(t.id).update({'name': n, 'currency': currency}));
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
          const Divider(height: 48),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            icon: Icon(last ? Icons.delete_forever : Icons.logout),
            label: Text(last ? 'Delete trip' : 'Leave trip'),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  content: Text(last
                      ? 'You are the last member. Leaving deletes "${t.name}" for good.'
                      : 'Leave "${t.name}"? You can rejoin with the invite code ${t.inviteCode}.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(last ? 'Delete' : 'Leave')),
                  ],
                ),
              );
              if (ok != true || !context.mounted) return;
              leaveTrip(t);
              Navigator.popUntil(context, (r) => r.isFirst);
            },
          ),
        ],
      ),
    );
  }
}
