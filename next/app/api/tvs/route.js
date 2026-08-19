import { NextResponse } from "next/server";
import { listPairedTvs, ensureHydrated } from "../../../lib/store";
import { verifyAdminSession } from "../../../lib/db";

export async function GET(request) {
  await ensureHydrated();
  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : null;
  const sessionUsername = await verifyAdminSession(token);
  if (!sessionUsername) {
    return NextResponse.json({ detail: "Not authenticated." }, { status: 401 });
  }
  // Raw per-TV playlist (regular ads only) - this is what the admin edits.
  // The TV itself receives the merged playlist (regular ads + interleaved
  // service ads) separately, over the SSE events endpoint.
  //
  // `connected` reflects whether the TV is currently paired and has not hit
  // its own "Disconnect" button - i.e. whether it's actively displaying ads
  // right now, as opposed to `code`, which stays valid indefinitely so a
  // disconnected TV can always reconnect with the same code.
  //
  // Scoped to the session's own admin - the session itself is authoritative,
  // not any admin_username the caller might send.
  const tvs = listPairedTvs()
    .filter((e) => (e.adminUsername || null) === sessionUsername)
    .map((e) => ({
      code: e.code,
      nickname: e.nickname,
      playlist: e.playlist,
      orientation: e.orientation || "landscape",
      transition: e.transition || "none",

      connected: e.status === "paired" && !e.disconnected,
    }));
  return NextResponse.json(tvs);
}
