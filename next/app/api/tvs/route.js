import { NextResponse } from "next/server";
import { listPairedTvs } from "../../../lib/store";

export async function GET() {
  const tvs = listPairedTvs().map((e) => ({
    code: e.code,
    nickname: e.nickname,
    playlist: e.playlist,
  }));
  return NextResponse.json(tvs);
}
