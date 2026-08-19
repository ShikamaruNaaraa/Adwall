import { NextResponse } from "next/server";
import { createPairingCode, ensureHydrated, nicknameExists } from "../../../lib/store";
import { verifyAdminSession } from "../../../lib/db";

export async function POST(request) {
  await ensureHydrated();
  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : null;
  const sessionUsername = await verifyAdminSession(token);
  if (!sessionUsername) {
    return NextResponse.json({ detail: "Not authenticated." }, { status: 401 });
  }

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
  if (nicknameExists(nickname, sessionUsername)) {
    return NextResponse.json(
      { detail: "A TV with that name already exists. Please choose a different name." },
      { status: 409 }
    );
  }

  const code = createPairingCode(nickname, sessionUsername);
  return NextResponse.json({ code });
}
