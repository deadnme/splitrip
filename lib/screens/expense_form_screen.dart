import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../format.dart';
import '../money.dart';
import 'amount.dart';
import 'random_pay.dart';

const categories = {
  'food': 'Food',
  'transportation': 'Transportation',
  'accommodation': 'Accommodation',
  'activities': 'Activities',
  'other': 'Other',
};
const splitTypes = {'equal': 'Equal', 'exact': 'Exact', 'percent': 'Percent', 'shares': 'Shares'};

/// Add / edit an expense. All inputs are read from the constructor once, in
/// initState, so live Firestore updates never reset what you are typing.
class ExpenseFormScreen extends StatefulWidget {
  final String tripId, currency;
  final List<Person> people;
  final String? myPersonId;
  final ExpenseDoc? expense;
  const ExpenseFormScreen({
    super.key,
    required this.tripId,
    required this.currency,
    required this.people,
    this.myPersonId,
    this.expense,
  });

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  late final int digits = currencyDigits(widget.currency);
  final title = TextEditingController();
  final amount = TextEditingController();
  late String date, category, splitType;
  String? paidBy;
  late Set<String> selected;
  final per = <String, TextEditingController>{}; // exact amount / percent / shares per person
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    final ids = widget.people.map((p) => p.id).toSet();
    title.text = e?.title ?? '';
    amount.text = e == null ? '' : formatPlain(e.amount, digits, grouping: false);
    date = e?.date ?? todayLocal();
    category = e?.category ?? 'other';
    splitType = e?.splitType ?? 'equal';
    paidBy = e?.paidBy ?? (ids.contains(widget.myPersonId) ? widget.myPersonId : widget.people.first.id);
    selected = e == null ? ids : e.splits.keys.where(ids.contains).toSet();
    for (final p in widget.people) {
      String text = '';
      if (e != null && e.splits.containsKey(p.id)) {
        text = switch (splitType) {
          'exact' => formatPlain(e.splits[p.id]!, digits, grouping: false),
          'percent' => e.weights[p.id] == null ? '' : formatPlain(e.weights[p.id]!, 2, grouping: false),
          'shares' => '${e.weights[p.id] ?? ''}',
          _ => '',
        };
      }
      per[p.id] = TextEditingController(text: text);
    }
  }

  int? get _amount => parseMinor(amount.text, digits);

  /// Weights for percent (hundredths of a percent) or shares (whole numbers).
  Map<String, int>? get _weights {
    final w = <String, int>{};
    for (final id in selected) {
      final v = splitType == 'percent' ? parseMinor(per[id]!.text, 2) : int.tryParse(per[id]!.text.trim());
      if (v == null || v < 0) return null;
      w[id] = v;
    }
    return w;
  }

  /// Resolved splits in minor units, or an error message.
  (Map<String, int>?, String?) _splits() {
    final a = _amount;
    if (a == null || a <= 0) return (null, 'Enter an amount.');
    if (selected.isEmpty) return (null, 'Pick at least one person.');
    switch (splitType) {
      case 'equal':
        return (splitEqual(a, selected.toList()), null);
      case 'exact':
        final parts = <String, int>{};
        for (final id in selected) {
          final v = parseMinor(per[id]!.text, digits);
          if (v == null) return (null, 'Enter an amount for everyone selected.');
          parts[id] = v;
        }
        final sum = parts.values.fold<int>(0, (s, v) => s + v);
        if (!exactSplitValid(a, parts)) {
          return (null, 'Shares add up to ${formatMoney(sum, widget.currency)}, need ${formatMoney(a, widget.currency)}.');
        }
        return (parts, null);
      default:
        final w = _weights;
        if (w == null) return (null, 'Enter a number for everyone selected.');
        final sum = w.values.fold<int>(0, (s, v) => s + v);
        if (splitType == 'percent' && sum != 10000) {
          return (null, 'Percentages add up to ${formatPlain(sum, 2)}%, need 100%.');
        }
        if (sum == 0) return (null, 'Give at least one person a share.');
        return (splitWeighted(a, w), null);
    }
  }

  /// "₱134 (133.34)": a share is owed, so it rounds up.
  String _owesText(int minor) => isWhole(minor, widget.currency)
      ? formatWhole(minor, widget.currency, Rounding.up)
      : '${formatWhole(minor, widget.currency, Rounding.up)} (${formatPlain(minor, digits)})';

  void _save() {
    final (splits, err) = _splits();
    if (_saved || splits == null || title.text.trim().isEmpty || paidBy == null) return;
    _saved = true;
    final ref = widget.expense == null ? expenses(widget.tripId).doc() : expenses(widget.tripId).doc(widget.expense!.id);
    fire(ref.set({
      'title': title.text.trim(),
      'amount': _amount!,
      'paidBy': paidBy,
      'date': date,
      'category': category,
      'splitType': splitType,
      'splits': splits,
      if (splitType == 'percent' || splitType == 'shares') 'weights': _weights,
      'createdBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }));
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text('Delete this expense?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted || _saved) return;
    _saved = true;
    fire(expenses(widget.tripId).doc(widget.expense!.id).delete());
    Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(date) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => date = DateFormat('yyyy-MM-dd').format(picked));
  }

  @override
  Widget build(BuildContext context) {
    final (splits, err) = _splits();
    final canSave = splits != null && title.text.trim().isNotEmpty && paidBy != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.expense == null ? 'Add expense' : 'Edit expense'),
        actions: [
          if (widget.expense != null)
            IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Title', hintText: 'What was this expense for?'),
            onChanged: (_) => setState(() {}),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Amount', prefixText: currencySymbol(widget.currency)),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(onPressed: _pickDate, icon: const Icon(Icons.event), label: Text(date)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(paidBy), // re-read initialValue when Random Pay picks the payer
                  initialValue: paidBy,
                  decoration: const InputDecoration(labelText: 'Paid by'),
                  items: [
                    for (final p in widget.people)
                      DropdownMenuItem(value: p.id, child: Text(p.name + (p.id == widget.myPersonId ? ' (you)' : ''))),
                  ],
                  onChanged: (v) => setState(() => paidBy = v),
                ),
              ),
              IconButton(
                tooltip: widget.people.length < 2 ? 'Add at least 2 people to use Random Pay' : 'Random Pay',
                icon: const Icon(Icons.casino_outlined),
                onPressed: widget.people.length < 2
                    ? null
                    : () async {
                        final i = await showRandomPayer(context, [for (final p in widget.people) p.name]);
                        if (i != null) setState(() => paidBy = widget.people[i].id);
                      },
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [for (final c in categories.entries) DropdownMenuItem(value: c.key, child: Text(c.value))],
            onChanged: (v) => setState(() => category = v!),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            showSelectedIcon: false, // the check mark wrapped "Equal" onto two lines on phones
            segments: [for (final s in splitTypes.entries) ButtonSegment(value: s.key, label: Text(s.value))],
            selected: {splitType},
            onSelectionChanged: (s) => setState(() => splitType = s.first),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('Split among')),
              TextButton(
                onPressed: () => setState(() => selected = selected.length == widget.people.length
                    ? <String>{}
                    : widget.people.map((p) => p.id).toSet()),
                child: Text(selected.length == widget.people.length ? 'Deselect all' : 'Select all'),
              ),
            ],
          ),
          for (final p in widget.people)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: selected.contains(p.id),
              onChanged: (v) => setState(() => v! ? selected.add(p.id) : selected.remove(p.id)),
              title: Text(p.name),
              secondary: !selected.contains(p.id)
                  ? null
                  : splitType == 'equal'
                      // Each person's share is what they owe: rounded up, exact value underneath.
                      ? (splits == null ? const Text('') : AmountText(splits[p.id] ?? 0, widget.currency, Rounding.up))
                      : SizedBox(
                          width: 110,
                          child: TextField(
                            controller: per[p.id],
                            textAlign: TextAlign.end,
                            keyboardType: TextInputType.numberWithOptions(decimal: splitType != 'shares'),
                            decoration: InputDecoration(
                              isDense: true,
                              suffixText: splitType == 'percent' ? '%' : splitType == 'shares' ? 'x' : null,
                              helperText: splitType != 'exact' && splits != null
                                  ? _owesText(splits[p.id] ?? 0)
                                  : null,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
            ),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 24),
          FilledButton(onPressed: canSave ? _save : null, child: const Text('Save')),
        ],
      ),
    );
  }
}
