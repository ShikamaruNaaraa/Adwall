import { NextResponse } from "next/server";
import { createPairingCode, ensureHydrated } from "../../../lib/store";

export async function POST(request) {
  await ensureHydrated();
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
  const adminUsername = (body?.admin_username || "").trim() || null;

  const code = createPairingCode(nickname, adminUsername);
  return NextResponse.json({ code });
}
