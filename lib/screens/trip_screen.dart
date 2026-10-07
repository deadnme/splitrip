import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';

import '../db.dart';
import '../format.dart';
import '../money.dart' as money;
import '../pdf_export.dart';
import '../theme.dart';
import 'amount.dart';
import 'expense_form_screen.dart';
import 'loading.dart';
import 'person_picker_screen.dart';
import 'trip_settings_screen.dart';

/// Everything one trip screen shows, kept live by Firestore listeners.
class TripData {
  Trip? trip;
  String? myPersonId;
  List<Person> people = [];
  List<ExpenseDoc> expenses = [];
  List<PaymentDoc> payments = [];

  String name(String personId) =>
      people.where((p) => p.id == personId).firstOrNull?.name ?? '(removed)';

  /// Balances are always derived from expenses + payments; nothing is stored.
  Map<String, int> get balances => money.balances(
        people.map((p) => p.id),
        expenses.map((e) => money.Expense(e.paidBy, e.amount, e.splits)),
        payments.map((p) => money.Payment(p.from, p.to, p.amount)),
      );

  /// Exact balances, but under one whole unit counts as settled: people pay
  /// rounded-up amounts, which leaves a few cents behind.
  Map<String, int> get shownBalances {
    final u = wholeUnit(trip!.currency);
    return balances.map((k, v) => MapEntry(k, v.abs() < u ? 0 : v));
  }

  /// Suggested transfers, skipping leftovers under one whole unit.
  List<money.Payment> get transfers {
    final u = wholeUnit(trip!.currency);
    return money.settleUp(balances).where((t) => t.amount >= u).toList();
  }
}

class TripScreen extends StatefulWidget {
  final String tripId;
  const TripScreen({super.key, required this.tripId});

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  final d = TripData();
  final _subs = <StreamSubscription>[];
  bool _tripLoaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final id = widget.tripId;
    // A trip created a moment ago (writes aren't awaited) can reach the server
    // after its listeners do; the server then denies the listens because the
    // trip doesn't exist there yet. Listen errors are final, so re-listen with
    // backoff (~15s total) before showing an error.
    void listen<T>(Stream<T> Function() s, void Function(T) onData, [int attempt = 0]) {
      late final StreamSubscription<T> sub;
      sub = s().listen(
        (v) => setState(() => onData(v)),
        onError: (Object e) {
          _subs.remove(sub);
          if (attempt < 5 && e is FirebaseException && e.code == 'permission-denied') {
            Future.delayed(Duration(milliseconds: 500 << attempt), () {
              if (mounted) listen(s, onData, attempt + 1);
            });
          } else if (mounted) {
            setState(() => _error = e);
          }
        },
      );
      _subs.add(sub);
    }

    listen(() => tripRef(id).snapshots(), (s) {
      _tripLoaded = true;
      d.trip = s.exists ? Trip(s) : null;
    });
    listen(() => myMember(id).snapshots(), (s) => d.myPersonId = s.data()?['personId'] as String?);
    listen(() => people(id).snapshots(), (s) => d.people = s.docs.map(Person.new).toList()..sort((a, b) => a.name.compareTo(b.name)));
    listen(() => expenses(id).snapshots(), (s) => d.expenses = s.docs.map(ExpenseDoc.new).toList()
      ..sort((a, b) => b.date != a.date ? b.date.compareTo(a.date) : a.title.compareTo(b.title)));
    listen(() => payments(id).snapshots(), (s) => d.payments = s.docs.map(PaymentDoc.new).toList()..sort((a, b) => b.date.compareTo(a.date)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _openExpense([ExpenseDoc? e]) {
    if (d.people.isEmpty) {
      showError('Add people first.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseFormScreen(
          tripId: widget.tripId,
          currency: d.trip!.currency,
          people: d.people,
          myPersonId: d.myPersonId,
          expense: e,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trip = d.trip;
    if (trip == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _error != null || _tripLoaded
              ? const Text('This trip is no longer available.')
              : const Loading('Loading trip…'),
        ),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(trip.name),
          actions: [
            IconButton(tooltip: 'Export PDF', icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: () => exportPdf(d)),
            IconButton(
              tooltip: 'Trip settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TripSettingsScreen(trip: trip, hasExpenses: d.expenses.isNotEmpty)),
              ),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Expenses'), Tab(text: 'Balances'), Tab(text: 'People')]),
        ),
        body: Column(
          children: [
            if (d.myPersonId == null || !d.people.any((p) => p.id == d.myPersonId))
              MaterialBanner(
                content: const Text('Tell SpliTrip which person you are.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => PersonPickerScreen(tripId: widget.tripId))),
                    child: const Text('Choose'),
                  ),
                ],
              ),
            Expanded(
              child: TabBarView(children: [
                _ExpensesTab(d: d, onOpen: _openExpense),
                _BalancesTab(d: d),
                _PeopleTab(d: d),
              ]),
            ),
          ],
        ),
        floatingActionButton: Builder(
          builder: (context) => FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('Expense'),
            onPressed: () => _openExpense(),
          ),
        ),
      ),
    );
  }
}

class _ExpensesTab extends StatelessWidget {
  final TripData d;
  final void Function([ExpenseDoc? e]) onOpen;
  const _ExpensesTab({required this.d, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final cur = d.trip!.currency;
    if (d.expenses.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No expenses yet',
        body: d.people.isEmpty ? 'Add people in the People tab first.' : 'Tap Expense to add the first one.',
      );
    }
    final total = d.expenses.fold<int>(0, (s, e) => s + e.amount);
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        ListTile(
          title: const Text('Total spent'),
          trailing: AmountText(total, cur, Rounding.nearest, style: Theme.of(context).textTheme.titleMedium),
        ),
        const Divider(height: 1),
        for (final e in d.expenses)
          ListTile(
            title: Text(e.title),
            subtitle: Text('${e.date} · ${categories[e.category] ?? e.category} · paid by ${d.name(e.paidBy)}'),
            trailing: AmountText(e.amount, cur, Rounding.nearest),
            onTap: () => onOpen(e),
          ),
      ],
    );
  }
}

class _BalancesTab extends StatelessWidget {
  final TripData d;
  const _BalancesTab({required this.d});

  @override
  Widget build(BuildContext context) {
    final cur = d.trip!.currency;
    final bal = d.shownBalances;
    final transfers = d.transfers;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Balances', style: text.titleMedium),
        for (final e in bal.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(d.name(e.key) + (e.key == d.myPersonId ? ' (you)' : '')),
            trailing: e.value == 0
                ? Text('settled', style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant))
                : AmountText(
                    e.value.abs(),
                    cur,
                    // Owes rounds up, gets back rounds down: nobody comes up short.
                    e.value > 0 ? Rounding.down : Rounding.up,
                    prefix: e.value > 0 ? 'gets back ' : 'owes ',
                    style: TextStyle(color: e.value > 0 ? gainColor(context) : scheme.error, fontWeight: FontWeight.w600),
                  ),
          ),
        const SizedBox(height: 16),
        Text('Suggested transfers', style: text.titleMedium),
        if (transfers.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Everyone is settled up.')),
        for (final t in transfers)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${d.name(t.from)} → ${d.name(t.to)}'),
            subtitle: AmountText(t.amount, cur, Rounding.up, alignEnd: false),
            trailing: FilledButton.tonal(onPressed: () => _settle(context, t), child: const Text('Settle')),
          ),
        if (d.payments.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Payments made', style: text.titleMedium),
          for (final p in d.payments)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${d.name(p.from)} paid ${d.name(p.to)}'),
              subtitle: Text('${formatWhole(p.amount, cur, Rounding.nearest)} · ${p.date}'
                  '${isWhole(p.amount, cur) ? '' : '  (${formatMoney(p.amount, cur)})'}'),
              trailing: IconButton(
                tooltip: 'Undo payment',
                icon: const Icon(Icons.undo),
                onPressed: () async {
                  final ok = await _confirm(context, 'Undo this payment?');
                  if (ok) fire(payments(d.trip!.id).doc(p.id).delete());
                },
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _settle(BuildContext context, money.Payment t) async {
    final cur = d.trip!.currency;
    final digits = currencyDigits(cur);
    // Prefilled with the rounded-up whole amount (what the payer actually hands over).
    final amount = TextEditingController(
      text: formatPlain(roundWhole(t.amount, cur, Rounding.up) ~/ wholeUnit(cur), 0, grouping: false),
    );
    var done = false; // double-tap guard: only the first tap records a payment
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${d.name(t.from)} pays ${d.name(t.to)}', style: Theme.of(context).textTheme.titleMedium),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Amount', prefixText: currencySymbol(cur)),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final v = parseMinor(amount.text, digits);
                if (done || v == null || v <= 0) return;
                done = true;
                fire(payments(d.trip!.id).doc().set({
                  'from': t.from,
                  'to': t.to,
                  'amount': v,
                  'date': todayLocal(),
                  'createdBy': uid,
                }));
                Navigator.pop(context);
              },
              child: const Text('Record payment'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeopleTab extends StatelessWidget {
  final TripData d;
  const _PeopleTab({required this.d});

  @override
  Widget build(BuildContext context) {
    final tripId = d.trip!.id;
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final p in d.people)
          ListTile(
            leading: CircleAvatar(child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase())),
            title: Text(p.name + (p.id == d.myPersonId ? ' (you)' : '')),
            onTap: () async {
              final n = await _prompt(context, 'Rename', p.name);
              if (n != null && n.isNotEmpty) fire(people(tripId).doc(p.id).update({'name': n}));
            },
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final used = d.expenses.any((e) => e.paidBy == p.id || e.splits.containsKey(p.id)) ||
                    d.payments.any((x) => x.from == p.id || x.to == p.id);
                if (used) {
                  showError('${p.name} is in expenses or payments. Remove those first.');
                  return;
                }
                if (await _confirm(context, 'Remove ${p.name}?')) fire(people(tripId).doc(p.id).delete());
              },
            ),
          ),
        ListTile(
          leading: const Icon(Icons.person_add_alt),
          title: const Text('Add person'),
          onTap: () async {
            final n = await _prompt(context, 'Add person', '');
            if (n != null && n.isNotEmpty) fire(people(tripId).doc().set({'name': n}));
          },
        ),
        ListTile(
          leading: const Icon(Icons.how_to_reg_outlined),
          title: const Text('Change which person I am'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PersonPickerScreen(tripId: tripId))),
        ),
      ],
    );
  }
}

Future<bool> _confirm(BuildContext context, String msg) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('OK')),
        ],
      ),
    ) ??
    false;

Future<String?> _prompt(BuildContext context, String title, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}
