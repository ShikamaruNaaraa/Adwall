import { NextResponse } from "next/server";
import { listPairedTvs, ensureHydrated } from "../../../lib/store";

export async function GET(request) {
  await ensureHydrated();
  const adminUsername = new URL(request.url).searchParams.get("admin_username");
  // Raw per-TV playlist (regular ads only) - this is what the admin edits.
  // The TV itself receives the merged playlist (regular ads + interleaved
  // service ads) separately, over the SSE events endpoint.
  //
  // `connected` reflects whether the TV is currently paired and has not hit
  // its own "Disconnect" button - i.e. whether it's actively displaying ads
  // right now, as opposed to `code`, which stays valid indefinitely so a
  // disconnected TV can always reconnect with the same code.
  //
  // Scoped to the requesting admin: each admin only sees the TVs they
  // themselves registered, never other admins' TVs.
  const tvs = listPairedTvs()
    .filter((e) => (e.adminUsername || null) === (adminUsername || null))
    .map((e) => ({
      code: e.code,
      nickname: e.nickname,
      playlist: e.playlist,
      orientation: e.orientation || "landscape",
      connected: e.status === "paired" && !e.disconnected,
    }));
  return NextResponse.json(tvs);
}

