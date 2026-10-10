// Firestore access. Firestore (with its built-in offline cache) is the only
// store; every write shape here matches firestore.rules.
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final db = FirebaseFirestore.instance;
String get uid => FirebaseAuth.instance.currentUser!.uid;

final messengerKey = GlobalKey<ScaffoldMessengerState>();

void showError(Object e) =>
    messengerKey.currentState?.showSnackBar(SnackBar(content: Text('$e')));

/// Writes apply to the local cache at once, but their futures only finish
/// when the server acknowledges them. Don't await them in the UI (offline the
/// screen would hang). Just report failures.
void fire(Future<void> write) => write.catchError(showError);

CollectionReference<Map<String, dynamic>> get trips => db.collection('trips');
DocumentReference<Map<String, dynamic>> tripRef(String id) => trips.doc(id);
CollectionReference<Map<String, dynamic>> people(String t) => tripRef(t).collection('people');
CollectionReference<Map<String, dynamic>> expenses(String t) => tripRef(t).collection('expenses');
CollectionReference<Map<String, dynamic>> payments(String t) => tripRef(t).collection('payments');
CollectionReference<Map<String, dynamic>> members(String t) => tripRef(t).collection('members');
DocumentReference<Map<String, dynamic>> myMember(String t) => members(t).doc(uid);

// No 0/O/1/I/L.
const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

String newInviteCode() {
  final r = Random.secure();
  return List.generate(8, (_) => _alphabet[r.nextInt(_alphabet.length)]).join();
}

String normalizeCode(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Invite link shown as the trip QR code. Opens the app if installed
/// (Android App Link), otherwise the web app, straight into joining.
const appUrl = 'https://splitrip-5fde9.web.app';
String inviteLink(String code) => '$appUrl/join/$code';

/// Code from a scanned/pasted invite: a full link, or just the code.
String codeFromInvite(String s) => normalizeCode(RegExp(r'/join/([A-Za-z0-9-]+)').firstMatch(s)?.group(1) ?? s);

Map<String, dynamic> _m(DocumentSnapshot<Map<String, dynamic>> d) => d.data() ?? const {};
int _int(Object? v) => (v as num?)?.toInt() ?? 0;

class Trip {
  final String id, name, currency, inviteCode;
  final List<String> memberUids;
  Trip(DocumentSnapshot<Map<String, dynamic>> d)
      : id = d.id,
        name = _m(d)['name'] ?? '',
        currency = _m(d)['currency'] ?? 'PHP',
        inviteCode = _m(d)['inviteCode'] ?? '',
        memberUids = List<String>.from(_m(d)['memberUids'] ?? const []);
}

class Person {
  final String id, name;
  /// The member who claimed this person. Only valid while that member's
  /// doc still points here; see [personOwner].
  final String? claimedBy;
  Person(DocumentSnapshot<Map<String, dynamic>> d)
      : id = d.id,
        name = _m(d)['name'] ?? '',
        claimedBy = _m(d)['claimedBy'] as String?;
}

/// The member (uid) who is this person, or null if nobody in the trip is.
/// [memberPerson] maps each member's uid to their chosen personId. Mirrors
/// firestore.rules; the fallback covers people created before claims existed.
String? personOwner(Person p, Map<String, String> memberPerson) {
  final c = p.claimedBy;
  if (c != null && memberPerson[c] == p.id) return c;
  for (final e in memberPerson.entries) {
    if (e.value == p.id) return e.key;
  }
  return null;
}

class ExpenseDoc {
  final String id, title, paidBy, date, category, splitType;
  final int amount;
  final Map<String, int> splits, weights;
  ExpenseDoc(DocumentSnapshot<Map<String, dynamic>> d)
      : id = d.id,
        title = _m(d)['title'] ?? '',
        paidBy = _m(d)['paidBy'] ?? '',
        date = _m(d)['date'] ?? '',
        category = _m(d)['category'] ?? 'other',
        splitType = _m(d)['splitType'] ?? 'equal',
        amount = _int(_m(d)['amount']),
        splits = (_m(d)['splits'] as Map? ?? {}).map((k, v) => MapEntry('$k', _int(v))),
        weights = ((_m(d)['weights'] as Map?) ?? {}).map((k, v) => MapEntry('$k', _int(v)));
}

class PaymentDoc {
  final String id, from, to, date;
  final int amount;
  PaymentDoc(DocumentSnapshot<Map<String, dynamic>> d)
      : id = d.id,
        from = _m(d)['from'] ?? '',
        to = _m(d)['to'] ?? '',
        date = _m(d)['date'] ?? '',
        amount = _int(_m(d)['amount']);
}

/// One batch: trip + my member doc + my person + invite. Returns the trip id.
String createTrip(String name, String currency, String myName) {
  final trip = trips.doc();
  final person = people(trip.id).doc();
  final code = newInviteCode();
  // ponytail: no pre-check for code collisions (31^8 codes). The rules reject
  // overwriting an existing invite, so a collision fails the batch instead of hijacking.
  final b = db.batch()
    ..set(trip, {
      'name': name,
      'currency': currency,
      'createdBy': uid,
      'inviteCode': code,
      'createdAt': FieldValue.serverTimestamp(),
      'memberUids': [uid],
    })
    ..set(myMember(trip.id), {'personId': person.id, 'joinedAt': FieldValue.serverTimestamp()})
    ..set(person, {'name': myName, 'claimedBy': uid})
    ..set(db.collection('invites').doc(code), {'tripId': trip.id});
  fire(b.commit());
  return trip.id;
}

/// Local cache first, then the server. Null when the cache doesn't have it.
Future<DocumentSnapshot<Map<String, dynamic>>?> _cached(DocumentReference<Map<String, dynamic>> ref) async {
  try {
    final s = await ref.get(const GetOptions(source: Source.cache));
    return s.exists ? s : null;
  } catch (_) {
    return null; // not cached
  }
}

/// Joins by invite code, or just opens the trip if already a member.
/// Already-joined trips are recognised from the local cache, so the iPhone Home
/// Screen app (which reopens its invite link on every launch) opens them fast.
/// Returns (tripId, alreadyMember).
Future<(String, bool)> joinTrip(String rawCode, {void Function(String step)? onStep}) async {
  final code = codeFromInvite(rawCode);
  if (code.length != 8) throw 'Invite codes have 8 characters.';
  onStep?.call('Finding the trip…');
  final inviteRef = db.collection('invites').doc(code);
  final invite = await _cached(inviteRef) ?? await inviteRef.get(const GetOptions(source: Source.server));
  if (!invite.exists) throw 'No trip found for code $code.';
  final tripId = invite['tripId'] as String;
  final cachedTrip = await _cached(tripRef(tripId));
  if (cachedTrip != null && Trip(cachedTrip).memberUids.contains(uid)) return (tripId, true);
  onStep?.call('Joining…');
  try {
    final t = await tripRef(tripId).get(const GetOptions(source: Source.server));
    if (t.exists && Trip(t).memberUids.contains(uid)) return (tripId, true);
  } on FirebaseException catch (e) {
    if (e.code != 'permission-denied') rethrow;
  }
  await (db.batch()
        ..set(myMember(tripId), {'code': code, 'joinedAt': FieldValue.serverTimestamp()})
        ..update(tripRef(tripId), {'memberUids': FieldValue.arrayUnion([uid])}))
      .commit();
  return (tripId, false);
}

/// Recheck membership on the server: another device may have joined or left
/// since the settings screen opened. Deletion needs a connection and is awaited.
Future<void> leaveTrip(Trip t) => _leaveTrip(t.id);

Future<void> _leaveTrip(String tripId) async {
  final userId = uid;
  final ref = tripRef(tripId);
  bool deleting;
  try {
    deleting = await _depart(ref, userId);
  } on FirebaseException catch (e) {
    // Rules run before the transaction's version check, so when the last two
    // members leave at once the loser gets permission-denied, not a retried
    // conflict. One retry on fresh data takes the delete path instead.
    if (e.code != 'permission-denied') rethrow;
    deleting = await _depart(ref, userId);
  }
  if (!deleting) return;
  // Queue only once the trip is locked, so a failed tap never leaves later.
  final prefs = await SharedPreferences.getInstance();
  final key = 'pending_trip_deletions_$userId';
  await prefs.setStringList(key, {...?prefs.getStringList(key), tripId}.toList());
  for (final sub in ['expenses', 'payments', 'people', 'members']) {
    while (true) {
      final page = await ref.collection(sub).limit(400).get(const GetOptions(source: Source.server));
      if (page.docs.isEmpty) break;
      final batch = db.batch();
      for (final document in page.docs) {
        batch.delete(document.reference);
      }
      await batch.commit();
    }
  }
  // Finished tombstones retain no names, invite codes, or user identifiers.
  await ref.set({'deleted': true, 'memberUids': <String>[]});
  final remaining = {...?prefs.getStringList(key)}..remove(tripId);
  await prefs.setStringList(key, remaining.toList());
}

/// Leaves, or locks the trip for deletion if [userId] is the last member.
/// Returns true when the trip is locked and its records need cleanup.
Future<bool> _depart(DocumentReference<Map<String, dynamic>> ref, String userId) =>
    db.runTransaction<bool>((transaction) async {
    final snapshot = await transaction.get(ref);
    final data = snapshot.data();
    if (data == null) return false;
    if (data['deleted'] == true) {
      if (data['deletingBy'] != userId) throw 'This trip is already deleted.';
      return true; // Resume an interrupted cleanup.
    }
    final members = List<String>.from(data['memberUids']);
    if (!members.contains(userId)) throw 'You have already left this trip.';
    transaction.delete(ref.collection('members').doc(userId));
    if (members.length > 1) {
      transaction.update(ref, {'memberUids': FieldValue.arrayRemove([userId])});
      return false;
    }
    // Never remove this parent ID: otherwise a new trip can expose orphaned
    // subcollections. Lock all financial writes before deleting them in chunks.
    transaction.set(ref, {'deleted': true, 'deletingBy': userId, 'memberUids': <String>[]});
    transaction.delete(db.collection('invites').doc(data['inviteCode'] as String));
    return true;
  });

/// Called after sign-in without blocking startup. A killed/offline cleanup is
/// resumed with the same authenticated identity; errors leave it queued.
Future<void> resumePendingDeletions() async {
  final prefs = await SharedPreferences.getInstance();
  final key = 'pending_trip_deletions_$uid';
  for (final tripId in List<String>.from(prefs.getStringList(key) ?? const [])) {
    try {
      await _leaveTrip(tripId);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        // A prior leave/final cleanup may have reached the server just before
        // the app was killed, before its local queue entry could be removed.
        final remaining = {...?prefs.getStringList(key)}..remove(tripId);
        await prefs.setStringList(key, remaining.toList());
      } else {
        showError('Trip deletion will retry when you reopen SpliTrip: $e');
      }
    } catch (e) {
      showError('Trip deletion will retry when you reopen SpliTrip: $e');
    }
  }
}

void setMyPerson(String tripId, String personId) => fire((db.batch()
      ..update(myMember(tripId), {'personId': personId})
      ..update(people(tripId).doc(personId), {'claimedBy': uid}))
    .commit());

/// People created before claims existed: claim my own on trip open, quietly.
void claimMyPerson(String tripId, String personId) =>
    people(tripId).doc(personId).update({'claimedBy': uid}).catchError((_) {});

void addMyself(String tripId, String name) {
  final p = people(tripId).doc();
  fire((db.batch()
        ..set(p, {'name': name, 'claimedBy': uid})
        ..update(myMember(tripId), {'personId': p.id}))
      .commit());
}
