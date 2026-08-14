import { NextResponse } from "next/server";
import { listPairedTvs } from "../../../lib/store";

export async function GET() {
  const tvs = listPairedTvs().map((e) => ({
    code: e.code,
    nickname: e.nickname,
    media_type: e.mediaType,
    media_url: e.mediaUrl,
  }));
  return NextResponse.json(tvs);
}
