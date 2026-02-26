// ================================================================
// THE CULTIVAR — Drop Machine Server
// Node.js + SQLite backend for the in-world DropMachine LSL terminal.
//
// DEPLOYMENT NOTE:
//   This server speaks plain HTTP on PORT (default 3000).
//   Put it behind nginx (or similar) with a valid TLS certificate
//   so that SecondLife's HTTP_VERIFY_CERT passes. SL requires HTTPS.
//   Example nginx location block:
//     location /drops/ { proxy_pass http://127.0.0.1:3000; }
//
// ENVIRONMENT VARIABLES:
//   PORT       — listening port (default: 3000)
//   TC_API_KEY — secret key for admin endpoints (default: changeme)
//   DB_PATH    — path to SQLite file (default: ./drops.db)
//
// ENDPOINTS:
//   GET  /drops/current        — current drop status (polled by in-world machine)
//   POST /drops/claim          — claim a seed pack (called by in-world machine)
//   POST /drops/create         — create a new drop      [requires X-Api-Key header]
//   POST /drops/end            — force-end active drop  [requires X-Api-Key header]
//   GET  /drops/stats          — recent drops + claims  [requires X-Api-Key header]
// ================================================================

'use strict';

const express  = require('express');
const Database = require('better-sqlite3');
const crypto   = require('crypto');
const path     = require('path');

const PORT    = process.env.PORT    || 3000;
const API_KEY = process.env.TC_API_KEY || 'changeme';
const DB_PATH = process.env.DB_PATH  || path.join(__dirname, 'drops.db');

// ── Database setup ─────────────────────────────────────────────────

const db = new Database(DB_PATH);

// Enable WAL mode for better concurrent read performance
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

db.exec(`
  CREATE TABLE IF NOT EXISTS drops (
    id         TEXT PRIMARY KEY,
    strain     TEXT    NOT NULL,
    quality    TEXT    NOT NULL CHECK(quality IN ('reggie','mids','loud','exotic')),
    remaining  INTEGER NOT NULL DEFAULT 0,
    ends_at    INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    active     INTEGER NOT NULL DEFAULT 1
  );

  CREATE TABLE IF NOT EXISTS claims (
    id          TEXT PRIMARY KEY,
    drop_id     TEXT    NOT NULL REFERENCES drops(id),
    avatar_key  TEXT    NOT NULL,
    avatar_name TEXT    NOT NULL,
    region      TEXT    NOT NULL DEFAULT '',
    timestamp   INTEGER NOT NULL,
    claimed_at  INTEGER NOT NULL
  );

  CREATE INDEX IF NOT EXISTS idx_claims_drop_avatar
    ON claims(drop_id, avatar_key);
`);

// Prepared statements
const stmts = {
  currentDrop: db.prepare(`
    SELECT * FROM drops
    WHERE active = 1 AND ends_at > ? AND remaining > 0
    ORDER BY created_at DESC
    LIMIT 1
  `),
  getDrop: db.prepare('SELECT * FROM drops WHERE id = ?'),
  alreadyClaimed: db.prepare(
    'SELECT id FROM claims WHERE drop_id = ? AND avatar_key = ?'
  ),
  decrementRemaining: db.prepare(
    'UPDATE drops SET remaining = remaining - 1 WHERE id = ? AND remaining > 0'
  ),
  insertClaim: db.prepare(`
    INSERT INTO claims (id, drop_id, avatar_key, avatar_name, region, timestamp, claimed_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `),
  deactivateIfEmpty: db.prepare(
    'UPDATE drops SET active = 0 WHERE id = ? AND remaining <= 0'
  ),
  deactivateAll: db.prepare('UPDATE drops SET active = 0 WHERE active = 1'),
  insertDrop: db.prepare(`
    INSERT INTO drops (id, strain, quality, remaining, ends_at, created_at, active)
    VALUES (?, ?, ?, ?, ?, ?, 1)
  `),
  recentDrops: db.prepare('SELECT * FROM drops ORDER BY created_at DESC LIMIT 20'),
  recentClaims: db.prepare('SELECT * FROM claims ORDER BY claimed_at DESC LIMIT 100'),
};

// ── Helpers ────────────────────────────────────────────────────────

const now = () => Math.floor(Date.now() / 1000);

function requireApiKey(req, res, next) {
  const key = req.headers['x-api-key'] || req.query.api_key;
  if (!key || key !== API_KEY) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
}

// Atomic claim transaction — returns true on success, false if sold out/race
const claimTransaction = db.transaction((dropId, claimId, avatarKey, avatarName, region, ts) => {
  const updated = stmts.decrementRemaining.run(dropId);
  if (updated.changes === 0) return false; // sold out in race
  stmts.insertClaim.run(claimId, dropId, avatarKey, avatarName, region, ts, now());
  return true;
});

// ── Express app ────────────────────────────────────────────────────

const app = express();
app.use(express.json());

// ── GET /drops/current ─────────────────────────────────────────────
// Polled every POLL_INTERVAL seconds by the in-world LSL terminal.
// Response shape matches what jsonGet() parses in TheCultivar_DropMachine.lsl.
app.get('/drops/current', (req, res) => {
  const drop = stmts.currentDrop.get(now());

  if (!drop) {
    return res.json({ active: false });
  }

  res.json({
    active:    true,
    strain:    drop.strain,
    quality:   drop.quality,
    remaining: drop.remaining,
    endsAt:    drop.ends_at,
    dropId:    drop.id,
  });
});

// ── POST /drops/claim ─────────────────────────────────────────────
// Called by the in-world terminal when a player confirms a claim.
// Body: { dropId, avatarKey, avatarName, region, timestamp }
app.post('/drops/claim', (req, res) => {
  const { dropId, avatarKey, avatarName, region, timestamp } = req.body || {};

  if (!dropId || !avatarKey || !avatarName) {
    return res.status(400).json({ success: false, reason: 'missing_fields' });
  }

  const drop = stmts.getDrop.get(dropId);
  if (!drop) {
    return res.status(400).json({ success: false, reason: 'drop_not_found' });
  }

  if (!drop.active || drop.ends_at <= now()) {
    return res.json({ success: false, reason: 'drop_ended' });
  }

  if (drop.remaining <= 0) {
    return res.json({ success: false, reason: 'sold_out' });
  }

  // Check for duplicate claim
  if (stmts.alreadyClaimed.get(dropId, avatarKey)) {
    return res.json({ success: false, reason: 'already_claimed' });
  }

  // Atomic decrement + record
  const claimId = crypto.randomUUID();
  const ts      = typeof timestamp === 'number' ? timestamp : now();
  const ok      = claimTransaction(dropId, claimId, avatarKey, avatarName, region || '', ts);

  if (!ok) {
    return res.json({ success: false, reason: 'sold_out' });
  }

  // Deactivate drop if now depleted
  stmts.deactivateIfEmpty.run(dropId);

  res.json({ success: true, reason: 'claimed' });
});

// ── POST /drops/create ─────────────────────────────────────────────
// Admin endpoint — create a new active drop.
// Body: { strain, quality, remaining, duration }
//   strain    — strain name matching the seed object in the machine
//   quality   — reggie | mids | loud | exotic
//   remaining — number of seed packs available (default: 10)
//   duration  — seconds until drop expires (default: 3600)
app.post('/drops/create', requireApiKey, (req, res) => {
  const { strain, quality, remaining, duration } = req.body || {};

  const validQualities = ['reggie', 'mids', 'loud', 'exotic'];
  if (!strain || !validQualities.includes(quality)) {
    return res.status(400).json({
      error: 'Required: strain (string), quality (reggie|mids|loud|exotic)',
    });
  }

  const count  = Math.max(1, parseInt(remaining, 10) || 10);
  const dur    = Math.max(60, parseInt(duration, 10)  || 3600);
  const endsAt = now() + dur;
  const dropId = crypto.randomUUID();

  // Deactivate any currently running drops
  stmts.deactivateAll.run();

  stmts.insertDrop.run(dropId, strain, quality, count, endsAt, now());

  res.json({
    success:   true,
    dropId,
    strain,
    quality,
    remaining: count,
    endsAt,
    message:   `Drop created — ${count}x ${quality} ${strain}, expires in ${dur}s`,
  });
});

// ── POST /drops/end ────────────────────────────────────────────────
// Admin endpoint — immediately end the current active drop.
app.post('/drops/end', requireApiKey, (req, res) => {
  const result = stmts.deactivateAll.run();
  res.json({
    success:  true,
    affected: result.changes,
    message:  result.changes > 0 ? 'Active drop ended.' : 'No active drop.',
  });
});

// ── GET /drops/stats ───────────────────────────────────────────────
// Admin endpoint — recent drop history and claim log.
app.get('/drops/stats', requireApiKey, (req, res) => {
  res.json({
    drops:  stmts.recentDrops.all(),
    claims: stmts.recentClaims.all(),
  });
});

// ── Start ──────────────────────────────────────────────────────────

app.listen(PORT, () => {
  console.log(`[The Cultivar] Drop Machine server listening on port ${PORT}`);
  if (API_KEY === 'changeme') {
    console.warn('[WARNING] TC_API_KEY is using the default value. Set it via environment variable.');
  }
});
