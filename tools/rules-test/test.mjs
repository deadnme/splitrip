// Firestore rules check. Run from the project root:
//   firebase emulators:exec --only firestore --project demo-splitrip "node tools/rules-test/test.mjs"
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, collection, query, where, writeBatch, setDoc, arrayUnion, arrayRemove, deleteDoc } from 'firebase/firestore';

const env = await initializeTestEnvironment({
  projectId: 'demo-splitrip',
  firestore: { rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8') },
});
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

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

test('create batch succeeds', () => assertSucceeds(createTrip('alice')));
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
test('last member can delete trip', () => assertSucceeds(deleteDoc(doc(db('alice'), 'trips', T))));

let failed = 0;
for (const [name, fn] of cases) {
  try { await fn(); console.log(`ok   ${name}`); }
  catch (e) { failed++; console.log(`FAIL ${name}: ${e.message.split('\n')[0]}`); }
}
await env.cleanup();
console.log(failed ? `${failed} failed` : `all ${cases.length} passed`);
process.exit(failed ? 1 : 0);
