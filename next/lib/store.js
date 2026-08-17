// Data layer for pairing codes / TVs / media.
//
// Backed by an in-memory Map so the API works out of the box, with every
// pairing/claim event also written to the tv_connections table in Postgres
// (see lib/db.js) so the connection status between a TV and an admin is
// recorded durably. DB writes are best-effort: if the database is
// unreachable, the in-memory store keeps the app fully working and a
// warning is logged instead of throwing.

import { recordCodeCreated, recordCodeClaimed } from "./db";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://dummy:dummy@localhost:5432/adwall";

if (!process.env.DATABASE_URL) {
  console.warn(
    "[store] DATABASE_URL not set, using dummy placeholder:",
    DATABASE_URL
  );
}
// code -> { code, nickname, status: 'pending' | 'paired', tvDeviceId,
//           playlist: [{ mediaType, mediaUrl, durationSeconds }],
//           subscribers: Set<controller> }
//
// Stored on globalThis rather than as a plain module-scope variable: in
// Next.js dev mode each API route can be compiled/HMR-reloaded as its own
// bundle, which would otherwise give every route its own empty Map instead
// of sharing one across requests.
const codes = globalThis.__adwallPairingCodes ?? new Map();
globalThis.__adwallPairingCodes = codes;

function generateCode() {
  let code;
  do {
    code = String(Math.floor(100000 + Math.random() * 900000));
  } while (codes.has(code));
  return code;
}

export function createPairingCode(nickname) {
  const code = generateCode();
  codes.set(code, {
    code,
    nickname,
    status: "pending",
    tvDeviceId: null,
    playlist: [],
    subscribers: new Set(),
  });
  // Best-effort, fire-and-forget: don't block/await, and never let a DB
  // hiccup break code creation for callers.
  recordCodeCreated(code, nickname).catch(() => {});
  return code;
}

export function getEntry(code) {
  return codes.get(code) || null;
}

export function claimCode(code, tvDeviceId) {
  const entry = codes.get(code);
  if (!entry) return null;
  entry.status = "paired";
  entry.tvDeviceId = tvDeviceId;
  notify(entry);
  recordCodeClaimed(code, tvDeviceId).catch(() => {});
  return entry;
}

export function setPlaylist(code, playlist) {
  const entry = codes.get(code);
  if (!entry) return null;
  entry.playlist = playlist.map((item) => ({
    mediaType: item.mediaType,
    mediaUrl: item.mediaUrl,
    durationSeconds: Math.max(1, Number(item.durationSeconds) || 1),
  }));
  notify(entry);
  return entry;
}

export function clearPlaylist(code) {
  return setPlaylist(code, []);
}

export function getPlaylist(code) {
  const entry = codes.get(code);
  return entry ? entry.playlist : null;
}

export function listPairedTvs() {
  return Array.from(codes.values()).filter((e) => e.status === "paired");
}

// --- SSE plumbing -----------------------------------------------------

function publicView(entry) {
  return {
    status: entry.status,
    nickname: entry.nickname,
    playlist: entry.playlist,
  };
}
function notify(entry) {
  const payload = `data: ${JSON.stringify(publicView(entry))}\n\n`;
  for (const controller of entry.subscribers) {
    try {
      controller.enqueue(payload);
    } catch {
      entry.subscribers.delete(controller);
    }
  }
}

export function subscribe(code, controller) {
  const entry = codes.get(code);
  if (!entry) return false;
  entry.subscribers.add(controller);
  // Push current state immediately so a late subscriber isn't stuck waiting.
  controller.enqueue(`data: ${JSON.stringify(publicView(entry))}\n\n`);
  return true;
}

export function unsubscribe(code, controller) {
  const entry = codes.get(code);
  entry?.subscribers.delete(controller);
}
