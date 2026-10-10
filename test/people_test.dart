import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitrip/db.dart';
import 'package:splitrip/screens/loading.dart';
import 'package:splitrip/screens/trip_screen.dart';

// ignore: subtype_of_sealed_class
class _Doc extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  final String id;
  final Map<String, dynamic> values;
  _Doc(this.id, this.values);
  @override
  Map<String, dynamic> data() => values;
}

Person person(String id, [String? claimedBy]) => Person(_Doc(id, {'name': id, 'claimedBy': ?claimedBy}));

void main() {
  test('a person is owned only while their claimer still points at them', () {
    final d = TripData()..memberPerson = {'u1': 'p1', 'u2': 'p2'};
    expect(d.ownerOf(person('p1', 'u1')), 'u1');
    expect(d.canEdit(person('p1', 'u1'), 'u2'), isFalse, reason: 'others cannot rename');
    expect(d.canEdit(person('p1', 'u1'), 'u1'), isTrue, reason: 'owner can rename');
    expect(d.canEdit(person('p3'), 'u2'), isTrue, reason: 'unclaimed people stay editable');
    // u1 left: the claim is stale, so the person is free again.
    d.memberPerson = {'u2': 'p2'};
    expect(d.ownerOf(person('p1', 'u1')), isNull);
    expect(d.canEdit(person('p1', 'u1'), 'u2'), isTrue);
    // Legacy person without a claim still belongs to the member who chose them.
    expect(d.ownerOf(person('p2')), 'u2');
  });

  testWidgets('an empty list can still be pulled down to refresh', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RefreshIndicator(
          onRefresh: () async => refreshed++,
          child: const ScrollableEmpty(EmptyState(icon: Icons.luggage_outlined, title: 'No trips yet', body: '')),
        ),
      ),
    ));
    await tester.fling(find.text('No trips yet'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(refreshed, 1);
  });
}
