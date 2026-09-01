#!/usr/bin/env node
// Fetches the current markdown vault from the obsidian-sync Edge
// Function and writes it into obsidian-vault/, replacing whatever was
// there before -- this is a full-state sync (handles deletions, e.g.
// a task removed in LOVA disappears here too), not an incremental
// patch. The commit + push itself happens in the GitHub Actions step
// that runs this script, not here.
//
// Required env vars: SUPABASE_SYNC_URL, SUPABASE_SYNC_SECRET

const fs = require('fs');
const path = require('path');

const VAULT_DIR = path.join(__dirname, '..', 'obsidian-vault');
const SYNCED_FOLDERS = ['Team', 'Projects', 'Tasks'];

async function main() {
  const url = process.env.SUPABASE_SYNC_URL;
  const secret = process.env.SUPABASE_SYNC_SECRET;
  if (!url || !secret) {
    console.error('Missing SUPABASE_SYNC_URL or SUPABASE_SYNC_SECRET env vars.');
    process.exit(1);
  }

  console.log('Fetching vault from', url);
  const resp = await fetch(url, {
    method: 'POST',
    headers: { 'x-sync-secret': secret, 'Content-Type': 'application/json' },
  });
  const body = await resp.json();
  if (!resp.ok) {
    console.error('Sync function returned an error:', body.error || body);
    process.exit(1);
  }

  const files = body.files || {};
  const fileCount = Object.keys(files).length;
  console.log(`Received ${fileCount} files. Counts:`, body.counts);

  // Clear out the folders we manage before rewriting, so deleted
  // LOVA records don't leave stale notes behind.
  for (const folder of SYNCED_FOLDERS) {
    const dir = path.join(VAULT_DIR, folder);
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true });
  }

  for (const [relPath, content] of Object.entries(files)) {
    const fullPath = path.join(VAULT_DIR, relPath);
    fs.mkdirSync(path.dirname(fullPath), { recursive: true });
    fs.writeFileSync(fullPath, content, 'utf8');
  }

  console.log(`Wrote ${fileCount} files to ${VAULT_DIR}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
