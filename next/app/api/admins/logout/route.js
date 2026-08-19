import { NextResponse } from "next/server";
import { deleteAdminSession } from "../../../../lib/db";

// POST /api/admins/logout - invalidates the bearer token in the
// Authorization header, if any. Always succeeds.
export async function POST(request) {
  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : null;
  try {
    await deleteAdminSession(token);
  } catch (err) {
    console.warn("[admin logout] failed:", err.message);
  }
  return NextResponse.json({ ok: true });
}
