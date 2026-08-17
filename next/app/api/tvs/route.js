import { NextResponse } from "next/server";
import { listPairedTvs } from "../../../lib/store";

export async function GET() {
  // Raw per-TV playlist (regular ads only) - this is what the admin edits.
  // The TV itself receives the merged playlist (regular ads + interleaved
  // service ads) separately, over the SSE events endpoint.
  //
  // `connected` reflects whether the TV currently has a live SSE connection
  // open (see /api/codes/[code]/events) - i.e. whether it's reachable right
  // now, as opposed to `code`, which stays valid indefinitely so a
  // disconnected TV can always reconnect with the same code.
  const tvs = listPairedTvs().map((e) => ({
    code: e.code,
    nickname: e.nickname,
    playlist: e.playlist,
    connected: e.subscribers.size > 0,
  }));
  return NextResponse.json(tvs);
}
