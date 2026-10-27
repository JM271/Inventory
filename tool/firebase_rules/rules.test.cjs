const { before, after, beforeEach, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc, runTransaction, writeBatch, serverTimestamp } = require('firebase/firestore');

let env;
const root = 'workshops/molenstraat';
const part = { id: 'chain', name: 'Chain', category: 'Drivetrain', sku: 'CHAIN', imageAsset: '', location: '', quantity: 1, minimum: 2, carQuantity: 0, carMinimum: 0 };
const client = (uid) => env.authenticatedContext(uid, { email: `${uid}@example.com` }).firestore();
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-inventory',
    firestore: { host: '127.0.0.1', port: 8085, rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8') },
  });
});
after(async () => { if (env) await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `${root}/members/admin`), { role: 'admin' });
    await setDoc(doc(db, `${root}/members/editor`), { role: 'editor' });
    await setDoc(doc(db, root), { initialized: true });
    await setDoc(doc(db, `${root}/parts/chain`), part);
  });
});

test('anonymous and pending accounts cannot read stock', async () => {
  await assertFails(getDocs(collection(env.unauthenticatedContext().firestore(), `${root}/parts`)));
  await assertFails(getDocs(collection(client('pending'), `${root}/parts`)));
  await assertSucceeds(getDoc(doc(client('pending'), `${root}/members/pending`)));
});

test('profiles cannot grant roles or impersonate another account', async () => {
  const db = client('pending');
  await assertSucceeds(setDoc(doc(db, 'users/pending'), { email: 'pending@example.com' }));
  await assertFails(setDoc(doc(db, 'users/other'), { email: 'pending@example.com' }));
  await assertFails(setDoc(doc(db, 'users/pending'), { email: 'admin@example.com' }));
  await assertFails(setDoc(doc(db, 'users/pending'), { email: 'pending@example.com', role: 'admin' }));
  await assertFails(getDocs(collection(db, 'users')));
  await assertFails(setDoc(doc(db, `${root}/members/pending`), { role: 'admin' }));
});

test('members edit valid stock but cannot grant membership', async () => {
  const db = client('editor');
  await assertSucceeds(getDocs(collection(db, `${root}/parts`)));
  await assertSucceeds(updateDoc(doc(db, `${root}/parts/chain`), { quantity: 2 }));
  await assertSucceeds(updateDoc(doc(db, `${root}/parts/chain`), { orderNumber: '000987' }));
  await assertFails(updateDoc(doc(db, `${root}/parts/chain`), { orderNumber: 987 }));
  await assertSucceeds(updateDoc(doc(db, `${root}/parts/chain`), { productNumber: '00123' }));
  await assertFails(updateDoc(doc(db, `${root}/parts/chain`), { productNumber: 123 }));
  await assertFails(updateDoc(doc(db, `${root}/parts/chain`), { quantity: -1 }));
  await assertFails(updateDoc(doc(db, `${root}/parts/chain`), { carQuantity: 1.5 }));
  await assertFails(updateDoc(doc(db, `${root}/parts/chain`), { id: 'different' }));
  await assertFails(setDoc(doc(db, `${root}/members/pending`), { role: 'editor' }));
  await assertFails(getDocs(collection(db, `${root}/members`)));
});

test('admins manage others but cannot remove their own membership', async () => {
  const db = client('admin');
  await assertSucceeds(getDocs(collection(db, 'users')));
  await assertSucceeds(setDoc(doc(db, `${root}/members/pending`), { role: 'editor' }));
  await assertSucceeds(getDocs(collection(client('pending'), `${root}/parts`)));
  await assertFails(deleteDoc(doc(db, `${root}/members/admin`)));
  await assertFails(updateDoc(doc(db, `${root}/members/admin`), { role: 'editor' }));
  await assertFails(setDoc(doc(db, `${root}/members/pending`), { role: 'superuser' }));
  await assertSucceeds(deleteDoc(doc(db, `${root}/members/pending`)));
  await assertFails(getDocs(collection(client('pending'), `${root}/parts`)));
});

test('new stock requires atomic initialization and marker cannot be reset', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => deleteDoc(doc(ctx.firestore(), root)));
  const db = client('editor');
  await assertFails(setDoc(doc(db, `${root}/parts/new`), { ...part, id: 'new' }));
  const batch = writeBatch(db);
  batch.set(doc(db, root), { initialized: true });
  batch.set(doc(db, `${root}/parts/new`), { ...part, id: 'new' });
  await assertSucceeds(batch.commit());
  await assertFails(setDoc(doc(db, root), { initialized: false }));
  await assertFails(deleteDoc(doc(db, root)));
});

test('custom catalog is shared and cannot be overwritten', async () => {
  const db = client('editor');
  await assertSucceeds(setDoc(doc(db, `${root}/catalog/new`), { ...part, id: 'custom', sku: 'CUSTOM' }));
  await assertSucceeds(getDocs(collection(client('admin'), `${root}/catalog`)));
  await assertFails(updateDoc(doc(db, `${root}/catalog/new`), { name: 'Replacement' }));
  await assertFails(getDocs(collection(client('pending'), `${root}/catalog`)));
});

test('simultaneous transactions cannot remove more than available stock', async () => {
  const book = (db) => runTransaction(db, async (tx) => {
    const ref = doc(db, `${root}/parts/chain`);
    const current = (await tx.get(ref)).data();
    if (current.quantity < 1) throw new Error('Insufficient stock');
    tx.update(ref, { quantity: current.quantity - 1 });
  });
  const results = await Promise.allSettled([book(client('admin')), book(client('editor'))]);
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  assert.equal((await getDoc(doc(client('admin'), `${root}/parts/chain`))).data().quantity, 0);
});


test('stock history is member-only, attributed and immutable', async () => {
  const db = client('editor');
  const ref = doc(db, `${root}/stockChanges/change`);
  const change = { partId: 'chain', name: 'Chain', productNumber: 'CHAIN', action: 'Adjusted', beforeWorkshop: 1, afterWorkshop: 2, beforeCar: 0, afterCar: 0, uid: 'editor', createdAt: serverTimestamp() };
  await assertFails(setDoc(ref, { ...change, uid: 'admin' }));
  await assertSucceeds(setDoc(ref, change));
  await assertSucceeds(getDocs(collection(db, `${root}/stockChanges`)));
  await assertFails(getDocs(collection(client('pending'), `${root}/stockChanges`)));
  await assertFails(updateDoc(ref, { afterWorkshop: 99 }));
  await assertFails(deleteDoc(ref));
});
