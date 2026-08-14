import { NextResponse } from "next/server";
import { createPairingCode } from "../../../lib/store";

export async function POST(request) {
  let body;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ detail: "Invalid JSON body" }, { status: 400 });
  }

  const nickname = (body?.nickname || "").trim();
  if (!nickname) {
    return NextResponse.json({ detail: "nickname is required" }, { status: 400 });
  }

  const code = createPairingCode(nickname);
  return NextResponse.json({ code });
}
