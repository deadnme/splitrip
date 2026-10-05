import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'join_screen.dart';

/// iPhone Safari, opened from an invite link: install first, then join inside
/// the Home Screen app (Safari tabs and Home Screen apps don't share data on iOS).
class InstallFirstScreen extends StatelessWidget {
  final String code;
  const InstallFirstScreen({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget step(int n, IconData icon, String text) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(child: Text('$n')),
          title: Text(text),
          trailing: Icon(icon),
        );
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(child: Image.asset('assets/logo.png', height: 56)),
            const SizedBox(height: 24),
            Text('Add SpliTrip to your Home Screen first', style: t.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              "On iPhone, trips you join in Safari don't carry over to the Home Screen app, so join from the app.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            step(1, Icons.ios_share, 'Tap the Share button in Safari\'s toolbar'),
            step(2, Icons.add_box_outlined, 'Choose "Add to Home Screen", then Add'),
            step(3, Icons.home_outlined, 'Open SpliTrip from your Home Screen. It opens straight into this trip.'),
            const SizedBox(height: 12),
            const Text("If it doesn't, tap the join button in the app and enter this code:", textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Center(
              child: SelectableText(code, style: t.headlineMedium?.copyWith(fontFamily: 'monospace', letterSpacing: 6)),
            ),
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy code'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
                },
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => JoinScreen(initialCode: code)),
              ),
              child: const Text('Just use it in Safari'),
            ),
          ],
        ),
      ),
    );
  }
}
