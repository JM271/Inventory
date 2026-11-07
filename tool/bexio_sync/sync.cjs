#!/usr/bin/env node
// Brings a bexio product export into the shared catalogue in Firestore
// (workshops/molenstraat/products), which both the Inventory and the
// offers app read. Nothing is bundled in the apps any more.
//
//   cd tool/bexio_sync && npm install          (once)
//   node tool/bexio_sync/sync.cjs <export.xlsx>               dry run
//   node tool/bexio_sync/sync.cjs <export.xlsx> --write       write
//   node tool/bexio_sync/sync.cjs <export.xlsx> --write --all
//
// Only products with an MS- code are read. The dry run lists new products,
// price changes, other differences and products missing in bexio.
// --write adds new products and updates prices. Names, categories and
// supplier numbers were partly tidied in the app (e.g. the two Mini MS
// models), so they are only overwritten with --all. Nothing is deleted.
//
// Uses the login of the Firebase CLI (`firebase login`).

'use strict';
const fs = require('fs');
const zlib = require('zlib');

const PROJECT = 'inventory-molenstraat';
const ROOT = `projects/${PROJECT}/databases/(default)/documents/workshops/molenstraat/`;

// Supplier codes in bexio that mean "none".
const NO_SUPPLIER = new Set(['', 'N/A', 'NA', '-', '4']);

// Column headers of the bexio product export (French and German UI).
const HEADERS = {
  sku: ['Code produit', 'Produktcode', 'Artikelnummer'],
  name: ['Désignation produit', 'Produktbezeichnung', 'Artikelbezeichnung'],
  category: ['Groupe principal', 'Hauptgruppe'],
  price: ['Prix de vente', 'Verkaufspreis'],
  supplierSku: ['Code produit (fournisseur)', 'Produktcode (Lieferant)', 'Artikelnummer (Lieferant)'],
};

// ---- xlsx (zip + XML), enough for a bexio export ----------------------

function unzip(buffer) {
  // End of central directory record.
  let eocd = buffer.length - 22;
  while (eocd >= 0 && buffer.readUInt32LE(eocd) !== 0x06054b50) eocd--;
  if (eocd < 0) throw new Error('Not an xlsx file');
  const count = buffer.readUInt16LE(eocd + 10);
  let p = buffer.readUInt32LE(eocd + 16);
  const files = {};
  for (let i = 0; i < count; i++) {
    const method = buffer.readUInt16LE(p + 10);
    const size = buffer.readUInt32LE(p + 20);
    const nameLength = buffer.readUInt16LE(p + 28);
    const extra = buffer.readUInt16LE(p + 30);
    const comment = buffer.readUInt16LE(p + 32);
    const local = buffer.readUInt32LE(p + 42);
    const name = buffer.toString('utf8', p + 46, p + 46 + nameLength);
    const start = local + 30 + buffer.readUInt16LE(local + 26) + buffer.readUInt16LE(local + 28);
    const data = buffer.subarray(start, start + size);
    files[name] = method === 8 ? zlib.inflateRawSync(data) : data;
    p += 46 + nameLength + extra + comment;
  }
  return files;
}

const xmlText = (s) =>
  s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'").replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n))
    .replace(/&amp;/g, '&');

function readSheet(path) {
  const files = unzip(fs.readFileSync(path));
  const shared = [];
  const sst = files['xl/sharedStrings.xml']?.toString('utf8') ?? '';
  for (const si of sst.matchAll(/<si>([\s\S]*?)<\/si>/g)) {
    shared.push(xmlText([...si[1].matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)].map((t) => t[1]).join('')));
  }
  const sheet = files['xl/worksheets/sheet1.xml'].toString('utf8');
  const rows = [];
  for (const row of sheet.matchAll(/<row[^>]*>([\s\S]*?)<\/row>/g)) {
    const cells = {};
    for (const c of row[1].matchAll(/<c r="([A-Z]+)\d+"([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
      const [, col, attrs, body = ''] = c;
      const type = /t="(\w+)"/.exec(attrs)?.[1];
      const v = /<v>([\s\S]*?)<\/v>/.exec(body)?.[1];
      cells[col] = type === 's' ? shared[+v]
        : type === 'inlineStr' ? xmlText([...body.matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)].map((t) => t[1]).join(''))
        : v == null ? '' : xmlText(v);
    }
    rows.push(cells);
  }
  return rows;
}

function bexioProducts(path) {
  const [header, ...rows] = readSheet(path);
  const column = {};
  for (const [field, names] of Object.entries(HEADERS)) {
    column[field] = Object.keys(header).find((col) => names.includes((header[col] ?? '').trim()));
    if (!column[field]) {
      throw new Error(`Column for ${field} not found. Headers: ${Object.values(header).join(' | ')}`);
    }
  }
  const products = new Map();
  for (const row of rows) {
    const sku = (row[column.sku] ?? '').trim().toUpperCase();
    if (!sku.startsWith('MS-')) continue;
    const supplier = (row[column.supplierSku] ?? '').trim();
    const price = Number.parseFloat(row[column.price] ?? '');
    products.set(sku, {
      sku,
      name: (row[column.name] ?? '').trim(),
      category: (row[column.category] ?? '').trim(),
      supplierSku: NO_SUPPLIER.has(supplier.toUpperCase()) ? '' : supplier,
      priceCents: Number.isFinite(price) ? Math.round(price * 100) : 0,
    });
  }
  return products;
}

// ---- Firestore via the Firebase CLI's login ---------------------------

async function firestore() {
  const lib = require.resolve('firebase-tools/package.json').replace(/package\.json$/, 'lib/');
  const auth = require(lib + 'auth');
  const { requireAuth } = require(lib + 'requireAuth');
  const { Client } = require(lib + 'apiv2');
  const api = require(lib + 'api');
  const options = { project: PROJECT };
  // Same account selection as the CLI's own commands.
  const account = auth.selectAccount(undefined, `${__dirname}/../..`);
  if (account) auth.setActiveAccount(options, account);
  await requireAuth(options);
  return new Client({ urlPrefix: api.firestoreOrigin(), apiVersion: 'v1', auth: true });
}

const docId = (sku) => Buffer.from(sku.toUpperCase(), 'utf8').toString('base64url').replace(/=/g, '');
const value = (f) => f?.stringValue ?? (f?.integerValue != null ? Number(f.integerValue) : undefined);
const toFields = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) =>
  [k, typeof v === 'number' ? { integerValue: String(v) } : { stringValue: v }]));

async function liveProducts(client) {
  const docs = [];
  let pageToken;
  do {
    const r = await client.get(ROOT + 'products', { queryParams: { pageSize: 300, ...(pageToken ? { pageToken } : {}) } });
    docs.push(...(r.body.documents ?? []));
    pageToken = r.body.nextPageToken;
  } while (pageToken);
  return new Map(docs.map((d) => {
    const p = Object.fromEntries(Object.entries(d.fields ?? {}).map(([k, f]) => [k, value(f)]));
    return [String(p.sku ?? '').toUpperCase(), p];
  }));
}

// ---- Compare and write ------------------------------------------------

const chf = (cents) => `CHF ${(cents / 100).toFixed(2)}`;

async function main() {
  const args = process.argv.slice(2);
  const file = args.find((a) => !a.startsWith('--'));
  const write = args.includes('--write');
  const all = args.includes('--all');
  if (!file) {
    console.error('Usage: node tool/bexio_sync/sync.cjs <bexio export.xlsx> [--write [--all]]');
    process.exit(2);
  }
  const bexio = bexioProducts(file);
  const client = await firestore();
  const live = await liveProducts(client);
  console.log(`bexio: ${bexio.size} MS- products · database: ${live.size} products\n`);

  const added = [...bexio.values()].filter((b) => !live.has(b.sku));
  const prices = [];
  const others = [];
  for (const b of bexio.values()) {
    const p = live.get(b.sku);
    if (!p) continue;
    if ((p.priceCents ?? 0) !== b.priceCents) prices.push(b);
    const fields = {};
    if (b.name && b.name !== p.name) fields.name = b.name;
    // An empty bexio value never clears what the database has.
    if (b.category && b.category !== p.category) fields.category = b.category;
    if (b.supplierSku && b.supplierSku !== (p.supplierSku ?? '')) fields.supplierSku = b.supplierSku;
    if (Object.keys(fields).length) others.push({ sku: b.sku, fields, live: p });
  }
  const missing = [...live.keys()].filter((sku) => !bexio.has(sku));

  console.log(`New products (${added.length}):`);
  for (const b of added) console.log(`  + ${b.sku}  ${b.name}  ${chf(b.priceCents)}`);
  console.log(`\nPrice changes (${prices.length}):`);
  for (const b of prices) console.log(`  ${b.sku}  ${chf(live.get(b.sku).priceCents ?? 0)} → ${chf(b.priceCents)}  ${b.name}`);
  console.log(`\nOther differences, written only with --all (${others.length}):`);
  for (const o of others) {
    for (const [k, v] of Object.entries(o.fields)) console.log(`  ${o.sku}  ${k}: "${o.live[k] ?? ''}" → "${v}"`);
  }
  console.log(`\nIn the database, not in bexio (left alone) (${missing.length}):`);
  for (const sku of missing) console.log(`  ${sku}  ${live.get(sku).name}`);

  if (!write) {
    console.log('\nDry run: nothing written. Add --write to apply.');
    return;
  }
  const doc = ROOT + 'products/';
  for (const b of added) {
    // A product ordered under the same supplier number shares its photo.
    const sibling = b.supplierSku &&
      [...live.values()].find((p) => p.supplierSku === b.supplierSku && p.imageAsset);
    const fields = { ...b, category: b.category || 'Other', imageAsset: sibling ? sibling.imageAsset : '' };
    await client.patch(`${doc}${docId(b.sku)}?currentDocument.exists=false`, { fields: toFields(fields) });
  }
  for (const b of prices) {
    await client.patch(`${doc}${docId(b.sku)}?updateMask.fieldPaths=priceCents&currentDocument.exists=true`,
      { fields: toFields({ priceCents: b.priceCents }) });
  }
  if (all) {
    for (const o of others) {
      const mask = Object.keys(o.fields).map((k) => `updateMask.fieldPaths=${k}`).join('&');
      await client.patch(`${doc}${docId(o.sku)}?${mask}&currentDocument.exists=true`, { fields: toFields(o.fields) });
    }
  }
  console.log(`\nWritten: ${added.length} new, ${prices.length} prices` +
    (all ? `, ${others.length} other updates.` : '. Other differences left as they are.'));
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
