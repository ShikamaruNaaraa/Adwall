// Data layer for pairing codes / TVs / media.
//
// Backed by an in-memory Map so the API works out of the box, with every
// pairing/claim/playlist event also written to the tv_connections table in
// MySQL (see lib/db.js) so a TV stays paired forever, even across server
// restarts. On first use, the in-memory Map is hydrated from that table
// (see ensureHydrated below). DB writes/reads are best-effort: if the
// database is unreachable, the in-memory store keeps the app working for
// the current process and a warning is logged instead of throwing.

import {
  recordCodeCreated,
  recordCodeClaimed,
  recordPlaylistUpdated,
  recordOrientationUpdated,
  loadAllPairings,
  deleteTvConnection,
} from "./db";


// code -> { code, nickname, status: 'pending' | 'paired', tvDeviceId,
//           playlist: [{ mediaType, mediaUrl, durationSeconds }],
//           orientation: 'landscape' | 'portrait',
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

// id -> { id, name, tvCodes: [code, ...], animationMediaUrl, animationMediaType }
//
// A "group" is an ordered list of TV codes used for the group animation
// feature: the admin attaches one video to the group, and playing it
// broadcasts that video + a shared start timestamp to every connected TV
// in the group at once, so they play their own slice of the frame roughly
// in sync (see playGroupAnimation below). In-memory only (not persisted to
// MySQL) - groups are cheap to recreate and don't need to survive a server
// restart. Stored on globalThis for the same HMR reason as
// `codes`/`serviceAds` above.
const groups = globalThis.__adwallGroups ?? new Map();
globalThis.__adwallGroups = groups;

async function hydrateFromDatabase() {
  const rows = await loadAllPairings();
  for (const row of rows) {
    if (codes.has(row.code)) continue;
    codes.set(row.code, {
      code: row.code,
      nickname: row.nickname,
      status: row.status,
      tvDeviceId: row.tvDeviceId,
      playlist: row.playlist,
      adminUsername: row.adminUsername || null,
      orientation: row.orientation || "landscape",
      subscribers: new Set(),
    });
  }
}

// Restores previously paired TVs from the database the first time the
// store is used in this process, so a TV stays paired across server
// restarts. Shared on globalThis for the same HMR reason as `codes`.
export function ensureHydrated() {
  if (!globalThis.__adwallHydration) {
    globalThis.__adwallHydration = hydrateFromDatabase().catch((err) => {
      console.warn("[store] failed to hydrate from database:", err.message);
    });
  }
  return globalThis.__adwallHydration;
}

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

export function createPairingCode(nickname, adminUsername) {
  const code = generateCode();
  codes.set(code, {
    code,
    nickname,
    status: "pending",
    tvDeviceId: null,
    playlist: [],
    adminUsername: adminUsername || null,
    orientation: "landscape",
    subscribers: new Set(),
  });
  // Best-effort, fire-and-forget: don't block/await, and never let a DB
  // hiccup break code creation for callers.
  recordCodeCreated(code, nickname, adminUsername).catch(() => {});
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
  entry.disconnected = false;
  notify(entry);
  recordCodeClaimed(code, tvDeviceId).catch(() => {});
  return entry;
}

// Marks a paired TV as disconnected without unpairing it (used when the TV
// app's own "Disconnect" button is pressed). The code/pairing stays valid
// so the admin can still manage it, but the admin list should show it as
// disconnected rather than connected.
export function markDisconnected(code) {
  const entry = codes.get(code);
  if (!entry) return null;
  entry.disconnected = true;
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
  recordPlaylistUpdated(code, entry.playlist).catch(() => {});
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
  recordPlaylistUpdated(code, entry.playlist).catch(() => {});
  return entry.playlist;
}

// Removes a single ad already on a TV's playlist (identified by its
// position) without re-uploading it.
export function removePlaylistItem(code, index) {
  const entry = codes.get(code);
  if (!entry) return null;
  if (!entry.playlist[index]) return null;
  entry.playlist.splice(index, 1);
  notify(entry);
  recordPlaylistUpdated(code, entry.playlist).catch(() => {});
  return entry.playlist;
}

export function clearPlaylist(code) {
  return setPlaylist(code, []);
}

export function getPlaylist(code) {
  const entry = codes.get(code);
  return entry ? entry.playlist : null;
}

// Sets a TV's display orientation ('landscape' or 'portrait'). The TV app
// reads this from its live SSE stream and rotates its playback layout to
// match.
export function setOrientation(code, orientation) {
  const entry = codes.get(code);
  if (!entry) return null;
  entry.orientation = orientation === "portrait" ? "portrait" : "landscape";
  notify(entry);
  recordOrientationUpdated(code, entry.orientation).catch(() => {});
  return entry;
}

export function listPairedTvs() {
  return Array.from(codes.values()).filter((e) => e.status === "paired");
}

// Every TV (pending or paired), with its owning admin and effective
// playlist (regular + interleaved service ads) - used by the master admin
// dashboard to show each admin's TVs and the ads playing on them.
export function listAllTvs() {
  return Array.from(codes.values()).map((e) => ({
    code: e.code,
    nickname: e.nickname,
    status: e.status,
    adminUsername: e.adminUsername || null,
    orientation: e.orientation || "landscape",
    connected: e.status === "paired" && !e.disconnected,
    playlist: getEffectivePlaylist(e),
  }));
}


// Removes a TV entirely: tells any live SSE connection it has open that
// it's been removed (so the TV app can clear its saved pairing and show
// the pairing screen again) before closing the stream, then drops it from
// the in-memory map and the database. The TV's pairing code is freed for
// reuse.
export function deleteTv(code) {
  const entry = codes.get(code);
  if (!entry) return false;
  const payload = `data: ${JSON.stringify({ status: "removed" })}\n\n`;
  for (const controller of entry.subscribers) {
    try {
      controller.enqueue(payload);
      controller.close();
    } catch {
      // Already closed/errored - nothing to do.
    }
  }
  codes.delete(code);
  deleteTvConnection(code).catch(() => {});
  return true;
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

// --- TV groups & group animation ----------------------------------------
//
// A group is an ordered list of TV codes plus one attached video. Playing
// the group animation broadcasts the same video + a shared start timestamp
// to every connected TV in the group at once; each TV renders only its own
// vertical slice of the frame (index/total), stretched to fill its own
// screen, so the TVs together form one continuous wide video.

function generateGroupId() {
  return `grp_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

export function createGroup(name, tvCodes) {
  const group = {
    id: generateGroupId(),
    name,
    tvCodes: Array.isArray(tvCodes) ? tvCodes.map(String) : [],
    animationMediaUrl: null,
    animationMediaType: null, // 'image' | 'video'
  };
  groups.set(group.id, group);
  return group;
}

export function listGroups() {
  return Array.from(groups.values());
}

export function getGroup(id) {
  return groups.get(id) || null;
}

export function updateGroup(id, { name, tvCodes }) {
  const group = groups.get(id);
  if (!group) return null;
  if (name !== undefined) group.name = name;
  if (tvCodes !== undefined) {
    group.tvCodes = Array.isArray(tvCodes) ? tvCodes.map(String) : [];
  }
  return group;
}

// Attaches (or replaces) the one video that plays stretched across this
// group's TVs, split into `tvCodes.length` equal vertical slices.
export function setGroupAnimationMedia(id, { mediaUrl, mediaType }) {
  const group = groups.get(id);
  if (!group) return null;
  group.animationMediaUrl = mediaUrl;
  group.animationMediaType = mediaType;
  return group;
}

export function deleteGroup(id) {
  return groups.delete(id);
}

// Broadcasts a one-off SSE frame that is NOT the regular playlist/status
// state (see publicView/notify below) - the TV app tells the two apart by
// checking for `type === 'group_animation'` before treating a frame as a
// playlist/orientation update.
function notifyAnimation(entry, payload) {
  const frame = `data: ${JSON.stringify(payload)}\n\n`;
  for (const controller of entry.subscribers) {
    try {
      controller.enqueue(frame);
    } catch {
      entry.subscribers.delete(controller);
    }
  }
}

// Sends the group's video to every currently-connected TV in the group at
// once, each stamped with its own index + the group size + a shared start
// timestamp (a few hundred ms in the future, to give every device time to
// receive the frame before it needs to start rendering) so playback stays
// roughly in sync across screens.
export function playGroupAnimation(id) {
  const group = groups.get(id);
  if (!group) return null;
  if (!group.animationMediaUrl) {
    return { error: "no_media" };
  }
  const startAt = Date.now() + 600;
  let sentTo = 0;
  group.tvCodes.forEach((code, index) => {
    const entry = codes.get(code);
    if (!entry || entry.subscribers.size === 0) return;
    notifyAnimation(entry, {
      type: "group_animation",
      groupId: group.id,
      index,
      total: group.tvCodes.length,
      mediaUrl: group.animationMediaUrl,
      mediaType: group.animationMediaType,
      startAt,
    });
    sentTo += 1;
  });
  return { groupId: group.id, total: group.tvCodes.length, sentTo, startAt };
}

// --- SSE plumbing -----------------------------------------------------

function publicView(entry) {
  return {
    status: entry.status,
    nickname: entry.nickname,
    orientation: entry.orientation || "landscape",
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
