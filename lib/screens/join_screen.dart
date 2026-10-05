import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../db.dart';
import '../platform/browser.dart';
import 'loading.dart';
import 'person_picker_screen.dart';
import 'trip_screen.dart';

class JoinScreen extends StatefulWidget {
  /// From an invite link: fill it in and join right away.
  final String? initialCode;
  const JoinScreen({super.key, this.initialCode});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String _step = 'Joining…';
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.initialCode;
    if (c != null) {
      _code.text = c;
      WidgetsBinding.instance.addPostFrameCallback((_) => _join(c));
    }
  }

  Future<void> _join(String code) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (tripId, already) = await joinTrip(code, onStep: (s) => setState(() => _step = s));
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => already ? TripScreen(tripId: tripId) : PersonPickerScreen(tripId: tripId, openTripAfter: true),
        ),
      );
    } catch (e) {
      setState(() => _error = e is String ? e : 'Could not join. Check the code and your connection.\n$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const _ScanScreen()));
    if (code != null) {
      _code.text = codeFromInvite(code);
      _join(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join trip')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('Ask someone in the trip for its invite code, or scan the QR code in their trip settings.'),
          if (isIosBrowserTab) ...[
            const SizedBox(height: 12),
            // iOS keeps Safari and Home Screen web apps' data separate, so joining in
            // Safari wouldn't carry over to the Home Screen app.
            const Text(
              'On iPhone: first add SpliTrip to your Home Screen (Share → Add to Home Screen), '
              'open it from there, then join. Safari and the Home Screen app don\'t share trips.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR code'),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            // Normalize before the length cap, so a pasted "rz6n-gdyz", "RZ6N GDYZ" or
            // full invite link isn't cut short.
            inputFormatters: [
              TextInputFormatter.withFunction((_, v) {
                final t = codeFromInvite(v.text);
                return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
              }),
            ],
            maxLength: 8,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 20, letterSpacing: 4),
            decoration: const InputDecoration(labelText: 'Invite code', hintText: 'e.g. K7PQ2MXA', border: OutlineInputBorder()),
            onSubmitted: _join,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _join(_code.text),
            child: _busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Join'),
          ),
          if (_busy) ...[
            const SizedBox(height: 24),
            Loading(_step),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

class _ScanScreen extends StatefulWidget {
  const _ScanScreen();

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // Web: always decode with zxing-wasm (verified with a fake camera). The default
    // prefers the browser's native BarcodeDetector where one exists, and on an
    // iPhone the camera opened but never read a code. No-op on Android.
    MobileScannerPlatform.instance.setWebBarcodeReader(WebBarcodeReader.zxingWasm);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan invite QR')),
      body: MobileScanner(
        // No camera, permission denied, or unsupported browser: fall back to typing.
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not open the camera. Type the invite code instead.', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Type the code')),
              ],
            ),
          ),
        ),
        onDetect: (capture) {
          final v = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
          if (_done || v == null || codeFromInvite(v).length != 8) return;
          _done = true;
          Navigator.pop(context, v);
        },
      ),
    );
  }
}
