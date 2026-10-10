// Firestore rules check. Run from the project root:
//   firebase emulators:exec --only firestore --project demo-splitrip "node tools/rules-test/test.mjs"
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, collection, query, where, limit, writeBatch, runTransaction, setDoc, arrayUnion, arrayRemove, deleteDoc } from 'firebase/firestore';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Run only against a local Firestore emulator.');

const env = await initializeTestEnvironment({
  projectId: 'demo-splitrip',
  firestore: { rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8') },
});
await env.clearFirestore();
const db = uid => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();
const T = 'trip1', CODE = 'ABCD2345';

async function createTrip(uid, tripId = T, code = CODE) {
  const d = db(uid), b = writeBatch(d);
  b.set(doc(d, 'trips', tripId), { name: 'Bali', currency: 'USD', createdBy: uid, inviteCode: code, createdAt: 1, memberUids: [uid] });
  b.set(doc(d, 'trips', tripId, 'members', uid), { personId: 'p1', joinedAt: 1 });
  b.set(doc(d, 'trips', tripId, 'people', 'p1'), { name: 'Alice' });
  b.set(doc(d, 'invites', code), { tripId });
  return b.commit();
}
function join(uid, code, tripId = T) {
  const d = db(uid), b = writeBatch(d);
  b.set(doc(d, 'trips', tripId, 'members', uid), { code, joinedAt: 2 });
  b.update(doc(d, 'trips', tripId), { memberUids: arrayUnion(uid) });
  return b.commit();
}

// Same transaction and cleanup stages as db.dart. Keep these checks at the
// authorization boundary: no administrator writes are used for deletion.
async function leaveOrDelete(uid, tripId = T) {
  // Like db.dart: a concurrent final leave is denied by rules, so retry once.
  try { return await depart(uid, tripId); }
  catch (e) { if (e.code !== 'permission-denied') throw e; return depart(uid, tripId); }
}
function depart(uid, tripId) {
  const d = db(uid), ref = doc(d, 'trips', tripId);
  return runTransaction(d, async tx => {
    const data = (await tx.get(ref)).data();
    if (data.deleted) return true;
    tx.delete(doc(d, 'trips', tripId, 'members', uid));
    if (data.memberUids.length > 1) {
      tx.update(ref, {memberUids: arrayRemove(uid)});
      return false;
    }
    tx.set(ref, {deleted:true, deletingBy:uid, memberUids:[]});
    tx.delete(doc(d, 'invites', data.inviteCode));
    return true;
  });
}

async function finishDeletion(uid, tripId = T) {
  const d = db(uid);
  for (const sub of ['expenses', 'payments', 'people', 'members']) {
    while (true) {
      const page = await getDocs(query(collection(d, 'trips', tripId, sub), limit(400)));
      if (page.empty) break;
      const b = writeBatch(d);
      page.docs.forEach(s => b.delete(s.ref));
      await assertSucceeds(b.commit());
    }
  }
  await assertSucceeds(setDoc(doc(d, 'trips', tripId), {deleted:true, memberUids:[]}));
}

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

test('create batch succeeds', () => assertSucceeds(createTrip('alice')));
test('currency is immutable even before first expense', () => assertFails(setDoc(doc(db('alice'), 'trips', T), {currency:'JPY'}, {merge:true})));
test('same-currency old-client name save succeeds', () => assertSucceeds(setDoc(doc(db('alice'), 'trips', T), {name:'Bali renamed',currency:'USD'}, {merge:true})));
test('unauthenticated cannot read invite', () => assertFails(getDoc(doc(db(null), 'invites', CODE))));
test('outsider cannot get trip', () => assertFails(getDoc(doc(db('eve'), 'trips', T))));
test('outsider cannot list all trips', () => assertFails(getDocs(collection(db('eve'), 'trips'))));
test('outsider own-trips query returns 0', async () => {
  const s = await assertSucceeds(getDocs(query(collection(db('eve'), 'trips'), where('memberUids', 'array-contains', 'eve'))));
  if (s.size !== 0) throw new Error(`expected 0, got ${s.size}`);
});
test('outsider cannot read expenses', () => assertFails(getDocs(collection(db('eve'), 'trips', T, 'expenses'))));
test('outsider cannot list invites', () => assertFails(getDocs(collection(db('eve'), 'invites'))));
test('join without code fails', () => {
  const d = db('eve'), b = writeBatch(d);
  b.set(doc(d, 'trips', T, 'members', 'eve'), { joinedAt: 2 });
  b.update(doc(d, 'trips', T), { memberUids: arrayUnion('eve') });
  return assertFails(b.commit());
});
test('join with wrong code fails', () => assertFails(join('eve', 'WRONG999')));
test('join with code succeeds', () => assertSucceeds(join('bob', CODE)));
test('member can read trip after join', () => assertSucceeds(getDoc(doc(db('bob'), 'trips', T))));
test('member own-trips query returns 1', async () => {
  const s = await getDocs(query(collection(db('bob'), 'trips'), where('memberUids', 'array-contains', 'bob')));
  if (s.size !== 1) throw new Error(`expected 1, got ${s.size}`);
});
test('member cannot add someone else', () => assertFails(setDoc(doc(db('bob'), 'trips', T), { memberUids: arrayUnion('eve') }, { merge: true })));
test('member cannot change createdBy', () => assertFails(setDoc(doc(db('bob'), 'trips', T), { createdBy: 'bob' }, { merge: true })));
test('member can rename trip', () => assertSucceeds(setDoc(doc(db('bob'), 'trips', T), { name: 'Bali 2026' }, { merge: true })));
test('member can add int expense', () => assertSucceeds(setDoc(doc(db('bob'), 'trips', T, 'expenses', 'e1'), { title: 'Dinner', amount: 1000, paidBy: 'p1', splits: { p1: 1000 } })));
test('float expense rejected', () => assertFails(setDoc(doc(db('bob'), 'trips', T, 'expenses', 'e2'), { title: 'x', amount: 10.5, paidBy: 'p1', splits: {} })));
test('member cannot write another member doc', () => assertFails(setDoc(doc(db('bob'), 'trips', T, 'members', 'alice'), { personId: 'p9' }, { merge: true })));
test('cannot hijack an invite code', () => assertFails(setDoc(doc(db('eve'), 'invites', CODE), { tripId: 'evil' })));
test('non-last member cannot delete trip', () => assertFails(deleteDoc(doc(db('bob'), 'trips', T))));
test('leave removes only self', () => {
  const d = db('bob'), b = writeBatch(d);
  b.update(doc(d, 'trips', T), { memberUids: arrayRemove('bob') });
  b.delete(doc(d, 'trips', T, 'members', 'bob'));
  return assertSucceeds(b.commit());
});
test('after leaving, no access', () => assertFails(getDoc(doc(db('bob'), 'trips', T))));
test('last member cannot hard-delete parent and expose orphaned records', () => assertFails(deleteDoc(doc(db('alice'), 'trips', T))));
test('last member cannot leave an empty active trip', () => assertFails(setDoc(doc(db('alice'), 'trips', T), {memberUids:[]}, {merge:true})));
test('last-member deletion must invalidate invite atomically', () => {
  const d = db('alice'), b = writeBatch(d);
  b.set(doc(d, 'trips', T), {deleted:true, deletingBy:'alice', memberUids:[]});
  b.delete(doc(d, 'trips', T, 'members', 'alice'));
  return assertFails(b.commit());
});
test('large-trip cleanup fixture can span multiple batches', async () => {
  const d = db('alice');
  for (let start = 0; start < 401; start += 400) {
    const b = writeBatch(d);
    for (let i = start; i < Math.min(start + 400, 401); i++) {
      b.set(doc(d,'trips',T,'expenses',`bulk${i}`), {title:'Synthetic expense',amount:100,paidBy:'p1',splits:{p1:100}});
    }
    await assertSucceeds(b.commit());
  }
});
test('last-member deletion locks trip and invalidates invite', async () => {
  if (!await assertSucceeds(leaveOrDelete('alice'))) throw new Error('Expected deletion');
  if ((await getDoc(doc(db('eve'),'invites',CODE))).exists()) throw new Error('Invite remains');
});
test('former member cannot read retained expenses during cleanup', () => assertFails(getDoc(doc(db('bob'),'trips',T,'expenses','e1'))));
test('old invite cannot join a deleting trip', () => assertFails(join('bob',CODE)));
test('deleted trip cannot be recreated with old invite', () => assertFails(createTrip('eve')));
test('deleted trip cannot be recreated with a fresh invite', () => assertFails(createTrip('eve',T,'FRESH234')));
test('deleter cannot modify or create financial records after lock', () => assertFails(setDoc(doc(db('alice'),'trips',T,'expenses','new'),{amount:100,splits:{}})));
test('outsider cannot finalize someone else\'s tombstone', () => assertFails(setDoc(doc(db('eve'),'trips',T),{deleted:true,memberUids:[]})));
test('interrupted cleanup can resume from its tombstone', () => assertSucceeds(leaveOrDelete('alice')));
test('cleanup removes all child records and identifying parent fields', async () => {
  await finishDeletion('alice');
  await env.withSecurityRulesDisabled(async c => {
    const d = c.firestore(), data = (await getDoc(doc(d,'trips',T))).data();
    if (JSON.stringify(Object.keys(data).sort()) !== JSON.stringify(['deleted','memberUids'])) throw new Error('Tombstone retains identifying fields');
    for (const sub of ['people','expenses','payments','members']) {
      if (!(await getDocs(collection(d,'trips',T,sub))).empty) throw new Error(`Retained ${sub}`);
    }
  });
});
test('finished tombstone cannot be deleted or resurrected', async () => {
  await assertFails(deleteDoc(doc(db('alice'),'trips',T)));
  await assertFails(createTrip('alice',T,'NEWC2345'));
});
// People: only the member who is a person may rename or remove them.
const P = 'ptrip', PCODE = 'PEOP2345';
const person = (uid, pid) => doc(db(uid), 'trips', P, 'people', pid);
test('people: setup trip with owner claim and a joined member', async () => {
  await createTrip('carol', P, PCODE);
  await assertSucceeds(setDoc(person('carol','p1'), {claimedBy:'carol'}, {merge:true}));
  await join('dave', PCODE, P);
  const d = db('dave'), b = writeBatch(d);
  b.set(doc(d, 'trips', P, 'people', 'p2'), {name:'Dave', claimedBy:'dave'});
  b.update(doc(d, 'trips', P, 'members', 'dave'), {personId:'p2'});
  await assertSucceeds(b.commit());
});
test('people: other member cannot rename a claimed person', () => assertFails(setDoc(person('dave','p1'), {name:'Hacked'}, {merge:true})));
test('people: other member cannot remove a claimed person', () => assertFails(deleteDoc(person('dave','p1'))));
test('people: cannot steal a claim', () => assertFails(setDoc(person('dave','p1'), {claimedBy:'dave'}, {merge:true})));
test('people: cannot create a person claimed by someone else', () => assertFails(setDoc(person('dave','px'), {name:'X', claimedBy:'carol'})));
test('people: owner can rename themselves', () => assertSucceeds(setDoc(person('carol','p1'), {name:'Carol'}, {merge:true})));
test('people: anyone can rename an unclaimed person', async () => {
  await assertSucceeds(setDoc(person('carol','p3'), {name:'Eve (no app)'}));
  await assertSucceeds(setDoc(person('dave','p3'), {name:'Eve'}, {merge:true}));
});
test('people: switching person frees the old one', async () => {
  const d = db('carol'), b = writeBatch(d);
  b.update(doc(d, 'trips', P, 'members', 'carol'), {personId:'p3'});
  b.update(doc(d, 'trips', P, 'people', 'p3'), {claimedBy:'carol'});
  await assertSucceeds(b.commit());
  await assertFails(setDoc(person('dave','p3'), {name:'Nope'}, {merge:true}));
  await assertSucceeds(setDoc(person('dave','p1'), {name:'Old me'}, {merge:true}));
});
test('people: leaving frees your person', async () => {
  await assertFails(setDoc(person('carol','p2'), {name:'Before leave'}, {merge:true}));
  await leaveOrDelete('dave', P);
  await assertSucceeds(setDoc(person('carol','p2'), {name:'Dave (left)'}, {merge:true}));
});

test('simultaneous final departures leave a protected tombstone', async () => {
  const id = 'concurrent-leave', code = 'RACE2345';
  await createTrip('carol',id,code).catch(e => {throw new Error(`create: ${e.message}`);});
  await join('dave',code,id).catch(e => {throw new Error(`join: ${e.message}`);});
  const deleted = await Promise.all([leaveOrDelete('carol',id),leaveOrDelete('dave',id)]).catch(e => {throw new Error(`depart: ${e.message}`);});
  if (deleted.filter(Boolean).length !== 1) throw new Error('Exactly the last departure must delete');
  await finishDeletion(deleted[0] ? 'carol' : 'dave',id);
  await assertFails(createTrip('eve',id,'RACE9999'));
});

let failed = 0;
for (const [name, fn] of cases) {
  try { await fn(); console.log(`ok   ${name}`); }
  catch (e) { failed++; console.log(`FAIL ${name}: ${e.message.split('\n')[0]}`); }
}
await env.cleanup();
console.log(failed ? `${failed} failed` : `all ${cases.length} passed`);
process.exit(failed ? 1 : 0);
