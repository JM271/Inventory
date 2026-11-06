const { before, after, beforeEach, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc, runTransaction, writeBatch, serverTimestamp } = require('firebase/firestore');

let env;
const root = 'workshops/molenstraat';
const part = { id: 'chain', name: 'Chain', category: 'Drivetrain', sku: 'CHAIN', imageAsset: '', location: '', quantity: 1, minimum: 2, carQuantity: 0, carMinimum: 0, garageQuantity: 0, garageMinimum: 0 };
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
  await assertSucceeds(updateDoc(doc(db, `${root}/parts/chain`), { garageQuantity: 3, garageMinimum: 1 }));
  await assertFails(updateDoc(doc(db, `${root}/parts/chain`), { garageQuantity: -1 }));
  // Older app versions write parts without garage stock; that would erase it.
  const { garageQuantity, garageMinimum, ...withoutGarage } = part;
  await assertFails(setDoc(doc(db, `${root}/parts/chain`), withoutGarage));
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
  await assertSucceeds(setDoc(doc(db, `${root}/stockChanges/garage`), { ...change, beforeGarage: 0, afterGarage: 2 }));
  await assertFails(setDoc(doc(db, `${root}/stockChanges/bad`), { ...change, afterGarage: -1 }));
  await assertSucceeds(getDocs(collection(db, `${root}/stockChanges`)));
  await assertFails(getDocs(collection(client('pending'), `${root}/stockChanges`)));
  await assertFails(updateDoc(ref, { afterWorkshop: 99 }));
  await assertFails(deleteDoc(ref));
});

const offer = (uid, extra = {}) => ({
  id: 'o1', number: 'A-2026-001', createdAt: '2026-11-04T10:00:00.000', validUntil: '2026-12-04T00:00:00.000',
  status: 'draft', customerName: 'Anna Muster', customerPhone: '', customerEmail: '', bikeModel: 'V8',
  frameNumber: '', problem: '', notes: '',
  lines: [{ kind: 'part', description: 'Chain', quantity: 1, unitPriceCents: 2490, sku: 'OXV8-30' }],
  updatedAt: serverTimestamp(), updatedBy: uid, ...extra,
});

test('offers are member-only and attributed to the writer', async () => {
  const db = client('editor');
  const ref = doc(db, `${root}/offers/o1`);
  await assertFails(setDoc(doc(client('pending'), `${root}/offers/o1`), offer('pending')));
  await assertFails(setDoc(ref, offer('admin')));
  await assertFails(setDoc(ref, { ...offer('editor'), updatedAt: '2026-11-04' }));
  await assertFails(setDoc(doc(db, `${root}/offers/other`), offer('editor')));
  await assertFails(setDoc(ref, offer('editor', { status: 'paid' })));
  await assertFails(setDoc(ref, offer('editor', { number: 'X-1' })));
  await assertFails(setDoc(ref, offer('editor', { role: 'admin' })));
  await assertSucceeds(setDoc(ref, offer('editor')));
  await assertSucceeds(setDoc(doc(client('admin'), `${root}/offers/o1`), offer('admin', { status: 'sent' })));
  await assertSucceeds(getDocs(collection(db, `${root}/offers`)));
  await assertFails(getDocs(collection(client('pending'), `${root}/offers`)));
  await assertSucceeds(deleteDoc(ref));
});

test('offer numbers only increase', async () => {
  const db = client('editor');
  const ref = doc(db, `${root}/offerCounters/2026`);
  await assertFails(setDoc(doc(db, `${root}/offerCounters/abc`), { last: 1 }));
  await assertFails(setDoc(doc(client('pending'), `${root}/offerCounters/2026`), { last: 1 }));
  await assertSucceeds(setDoc(ref, { last: 1 }));
  await assertSucceeds(setDoc(ref, { last: 2 }));
  await assertFails(setDoc(ref, { last: 1 }));
  await assertFails(setDoc(ref, { last: 3, reset: true }));
  await assertFails(deleteDoc(ref));
});

test('offer settings, price list and part prices are validated', async () => {
  const db = client('editor');
  const settings = doc(db, `${root}/offerConfig/settings`);
  await assertSucceeds(setDoc(settings, { companyName: 'Molenstraat Fatbikes', hourlyRateCents: 9000, vatRate: 8.1, pricesIncludeVat: true, validityDays: 30, currency: 'CHF' }));
  await assertSucceeds(setDoc(settings, { vatRate: 8 }));
  await assertFails(setDoc(settings, { hourlyRateCents: -1 }));
  await assertFails(setDoc(settings, { hourlyRateCents: 90.5 }));
  await assertFails(setDoc(settings, { admin: true }));
  await assertFails(setDoc(doc(db, `${root}/offerConfig/other`), { items: [] }));
  await assertFails(getDoc(doc(client('pending'), `${root}/offerConfig/settings`)));
  await assertSucceeds(setDoc(doc(db, `${root}/offerConfig/presets`), { items: [{ id: 'p', name: 'Service' }] }));
  await assertFails(setDoc(doc(db, `${root}/offerConfig/presets`), { items: 'none' }));
  const price = doc(db, `${root}/partPrices/T1hWOC0zMA`);
  await assertSucceeds(setDoc(price, { sku: 'OXV8-30', priceCents: 1990 }));
  await assertFails(setDoc(price, { sku: 'OXV8-30', priceCents: 0 }));
  await assertFails(setDoc(price, { sku: 'OXV8-30', priceCents: 19.9 }));
  await assertFails(getDocs(collection(client('pending'), `${root}/partPrices`)));
  await assertSucceeds(deleteDoc(price));
});

test('the shared product catalogue is validated and seeded once', async () => {
  const db = client('editor');
  const product = doc(db, `${root}/products/TVMtU1AtMzAwOQ`);
  await assertSucceeds(setDoc(product, { sku: 'MS-SP-3009', name: '3 in 1 switch', category: 'Spare Parts', supplierSku: 'OXV8-05', imageAsset: 'assets/products/oxv8-05.png', priceCents: 4500 }));
  await assertSucceeds(updateDoc(product, { priceCents: 4900 }));
  await assertSucceeds(setDoc(doc(db, `${root}/products/new`), { sku: 'MS-SP-9001', name: 'New part', category: 'Spare Parts' }));
  await assertFails(updateDoc(product, { priceCents: -1 }));
  await assertFails(updateDoc(product, { priceCents: 45.5 }));
  await assertFails(updateDoc(product, { sku: '' }));
  await assertFails(updateDoc(product, { stock: 3 }));
  await assertFails(setDoc(doc(db, `${root}/products/bad`), { sku: 'X', category: 'Spare Parts' }));
  await assertFails(getDocs(collection(client('pending'), `${root}/products`)));
  await assertFails(deleteDoc(product));
  await assertSucceeds(deleteDoc(doc(client('admin'), `${root}/products/new`)));
  const state = doc(db, `${root}/catalogConfig/state`);
  await assertFails(setDoc(state, { seeded: false }));
  await assertSucceeds(setDoc(state, { seeded: true }));
  await assertFails(setDoc(state, { seeded: true }));
  await assertFails(deleteDoc(state));
  await assertFails(setDoc(doc(db, `${root}/catalogConfig/other`), { seeded: true }));
});
