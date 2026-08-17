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

// id -> { id, mediaUrl, mediaType, durationSeconds, interval }
//
// Service ads are admin-wide (not tied to one TV): every registered/paired
// TV plays them automatically, inserted into its own ad sequence after
// every `interval` regular ads. Stored on globalThis for the same HMR
// reason as `codes` above.
const serviceAds = globalThis.__adwallServiceAds ?? new Map();
globalThis.__adwallServiceAds = serviceAds;

function generateCode() {
  let code;
  do {
    code = String(Math.floor(100000 + Math.random() * 900000));
  } while (codes.has(code));
  return code;
}

function generateServiceAdId() {
  return `svc_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
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

// Edits a single ad already on a TV's playlist (by its position) - used to
// change how long that ad plays for without re-uploading it.
export function updatePlaylistItem(code, index, { durationSeconds }) {
  const entry = codes.get(code);
  if (!entry) return null;
  const item = entry.playlist[index];
  if (!item) return null;
  if (durationSeconds !== undefined) {
    item.durationSeconds = Math.max(1, Number(durationSeconds) || 1);
  }
  notify(entry);
  return entry.playlist;
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

// --- Service ads --------------------------------------------------------
//
// Admin-wide ads with a play `interval`: after every N regular ads shown on
// a TV, the next service ad is due. If a TV has fewer regular ads than N,
// the interval is clamped down to that TV's ad count (so e.g. a TV with a
// single ad still gets the service ad, after that 1 ad).

export function createServiceAd({ mediaUrl, mediaType, durationSeconds, interval, targetTvCodes }) {
  const ad = {
    id: generateServiceAdId(),
    mediaUrl,
    mediaType: mediaType || "image",
    durationSeconds: Math.max(1, Number(durationSeconds) || 1),
    interval: Math.max(1, Number(interval) || 1),
    // null/undefined = play on every TV. A non-empty array restricts the ad
    // to just those TV codes.
    targetTvCodes:
      Array.isArray(targetTvCodes) && targetTvCodes.length > 0
        ? targetTvCodes.map(String)
        : null,
  };
  serviceAds.set(ad.id, ad);
  notifyAll();
  return ad;
}

export function listServiceAds() {
  return Array.from(serviceAds.values());
}

// Edits an existing service ad's duration and/or play interval (how many
// regular ads must play before this one is shown again).
export function updateServiceAd(id, { durationSeconds, interval, targetTvCodes }) {
  const ad = serviceAds.get(id);
  if (!ad) return null;
  if (durationSeconds !== undefined) {
    ad.durationSeconds = Math.max(1, Number(durationSeconds) || 1);
  }
  if (interval !== undefined) {
    ad.interval = Math.max(1, Number(interval) || 1);
  }
  if (targetTvCodes !== undefined) {
    ad.targetTvCodes =
      Array.isArray(targetTvCodes) && targetTvCodes.length > 0
        ? targetTvCodes.map(String)
        : null;
  }
  notifyAll();
  return ad;
}

export function deleteServiceAd(id) {
  const removed = serviceAds.delete(id);
  if (removed) notifyAll();
  return removed;
}


// Interleaves the admin-wide service ads into one TV's own playlist. The
// regular playlist order is preserved; a service ad is inserted right after
// every `interval`-th regular ad (interval clamped to the playlist length
// so short playlists still get service ads instead of never reaching N).
function mergeServiceAds(regularPlaylist, ads, code) {
  // A null/empty targetTvCodes means the ad plays on every TV; otherwise it
  // only applies to the TV codes explicitly selected for it.
  const applicable = ads.filter(
    (ad) => !ad.targetTvCodes || ad.targetTvCodes.includes(code)
  );
  if (applicable.length === 0) return regularPlaylist;
  if (regularPlaylist.length === 0) {
    return applicable.map((ad) => ({
      mediaType: ad.mediaType,
      mediaUrl: ad.mediaUrl,
      durationSeconds: ad.durationSeconds,
    }));
  }

  const result = [];
  for (let i = 0; i < regularPlaylist.length; i++) {
    result.push(regularPlaylist[i]);
    const position = i + 1; // count of regular ads shown so far, 1-based
    for (const ad of applicable) {
      const effectiveInterval = Math.min(ad.interval, regularPlaylist.length);
      if (position % effectiveInterval === 0) {
        result.push({
          mediaType: ad.mediaType,
          mediaUrl: ad.mediaUrl,
          durationSeconds: ad.durationSeconds,
        });
      }
    }
  }
  return result;
}

export function getEffectivePlaylist(entry) {
  return mergeServiceAds(entry.playlist, listServiceAds(), entry.code);
}

// --- SSE plumbing -----------------------------------------------------

function publicView(entry) {
  return {
    status: entry.status,
    nickname: entry.nickname,
    playlist: getEffectivePlaylist(entry),
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

// Called whenever the admin-wide service ads change, since that changes
// every paired TV's effective playlist even though entry.playlist itself
// (the regular per-TV ads) did not change.
function notifyAll() {
  for (const entry of codes.values()) {
    notify(entry);
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
