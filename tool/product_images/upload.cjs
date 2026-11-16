#!/usr/bin/env node
// Saves the product pictures in the shared database
// (workshops/molenstraat/productImages), where the app reads them. A
// picture changed here shows up in the app without a new release.
//
//   node tool/product_images/upload.cjs                 dry run
//   node tool/product_images/upload.cjs --write         write
//   node tool/product_images/upload.cjs <folder> …      another folder
//
// Reads assets/products by default. Each picture is one document, named
// like the file: a product's imageAsset "assets/products/oxv8-13.png" finds
// the document "oxv8-13.png". The dry run lists new, changed and unchanged
// pictures; --write saves the new and changed ones. Nothing is deleted.
//
// Uses the login of the Firebase CLI (`firebase login`) and the
// firebase-tools installed for tool/bexio_sync (`npm install` there once).

'use strict';
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const PROJECT = 'inventory-molenstraat';
const ROOT = `projects/${PROJECT}/databases/(default)/documents/workshops/molenstraat/`;
const REPO = path.join(__dirname, '../..');
const TYPES = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp' };
// A Firestore document holds at most 1 MiB.
const MAX_BYTES = 900 * 1024;

async function firestore() {
  let lib;
  try {
    lib = require.resolve('firebase-tools/package.json', { paths: [path.join(REPO, 'tool/bexio_sync')] })
      .replace(/package\.json$/, 'lib/');
  } catch {
    throw new Error('firebase-tools is missing. Run once: cd tool/bexio_sync && npm install');
  }
  const auth = require(lib + 'auth');
  const { requireAuth } = require(lib + 'requireAuth');
  const { Client } = require(lib + 'apiv2');
  const api = require(lib + 'api');
  const options = { project: PROJECT };
  // Same account selection as the CLI's own commands.
  const account = auth.selectAccount(undefined, REPO);
  if (account) auth.setActiveAccount(options, account);
  await requireAuth(options);
  return new Client({ urlPrefix: api.firestoreOrigin(), apiVersion: 'v1', auth: true });
}

function localPictures(folder) {
  const pictures = new Map();
  for (const file of fs.readdirSync(folder).sort()) {
    const contentType = TYPES[path.extname(file).toLowerCase()];
    if (!contentType) continue;
    const bytes = fs.readFileSync(path.join(folder, file));
    if (bytes.length > MAX_BYTES) {
      throw new Error(`${file} is ${Math.round(bytes.length / 1024)} KB; a picture may be at most ${MAX_BYTES / 1024} KB.`);
    }
    const name = file.toLowerCase();
    if (pictures.has(name)) throw new Error(`${file} exists twice (upper and lower case).`);
    pictures.set(name, { name, contentType, bytes, sha256: crypto.createHash('sha256').update(bytes).digest('hex') });
  }
  return pictures;
}

// Only the checksums: the pictures themselves are not downloaded.
async function savedChecksums(client) {
  const saved = new Map();
  let pageToken;
  do {
    const r = await client.get(ROOT + 'productImages', {
      queryParams: { pageSize: 300, 'mask.fieldPaths': 'sha256', ...(pageToken ? { pageToken } : {}) },
    });
    for (const d of r.body.documents ?? []) {
      saved.set(d.name.split('/').pop(), d.fields?.sha256?.stringValue ?? '');
    }
    pageToken = r.body.nextPageToken;
  } while (pageToken);
  return saved;
}

async function main() {
  const args = process.argv.slice(2);
  const write = args.includes('--write');
  const folder = path.resolve(args.find((a) => !a.startsWith('--')) ?? path.join(REPO, 'assets/products'));
  const local = localPictures(folder);
  const client = await firestore();
  const saved = await savedChecksums(client);

  const added = [...local.values()].filter((p) => !saved.has(p.name));
  const changed = [...local.values()].filter((p) => saved.has(p.name) && saved.get(p.name) !== p.sha256);
  const others = [...saved.keys()].filter((name) => !local.has(name));
  const kb = (list) => `${Math.round(list.reduce((sum, p) => sum + p.bytes.length, 0) / 1024)} KB`;

  console.log(`${folder}: ${local.size} pictures · database: ${saved.size} pictures\n`);
  console.log(`New (${added.length}, ${kb(added)}): ${added.map((p) => p.name).join(' ')}`);
  console.log(`\nChanged (${changed.length}, ${kb(changed)}): ${changed.map((p) => p.name).join(' ')}`);
  console.log(`\nUnchanged: ${local.size - added.length - changed.length}`);
  console.log(`\nIn the database, not in the folder (left alone) (${others.length}): ${others.join(' ')}`);

  if (!write) {
    console.log('\nDry run: nothing written. Add --write to apply.');
    return;
  }
  for (const p of [...added, ...changed]) {
    await client.patch(`${ROOT}productImages/${encodeURIComponent(p.name)}`, {
      fields: {
        bytes: { bytesValue: p.bytes.toString('base64') },
        contentType: { stringValue: p.contentType },
        sha256: { stringValue: p.sha256 },
      },
    });
  }
  console.log(`\nWritten: ${added.length} new, ${changed.length} changed.`);
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
