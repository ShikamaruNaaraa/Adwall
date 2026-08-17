import { NextResponse } from "next/server";
import { markDisconnected } from "../../../../../lib/store";

// POST /api/codes/{code}/disconnect - the TV app calls this when the user
// taps "Disconnect" on the TV itself. Keeps the pairing/code valid but
// marks the TV as disconnected so the admin app shows it as such instead
// of connected, until the TV claims the code again.
export async function POST(request, { params }) {
  const { code } = await params;
  const entry = markDisconnected(code);
  if (!entry) {
    return NextResponse.json({ detail: "Unknown TV code" }, { status: 404 });
  }
  return NextResponse.json({ ok: true });
}
