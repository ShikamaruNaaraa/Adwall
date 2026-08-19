import { NextResponse } from "next/server";
import { deleteMasterAdminSession } from "../../../../lib/db";

// POST /api/master-admin/logout - invalidates the bearer token in the
// Authorization header, if any. Always succeeds.
export async function POST(request) {
  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : null;
  try {
    await deleteMasterAdminSession(token);
  } catch (err) {
    console.warn("[master-admin logout] failed:", err.message);
  }
  return NextResponse.json({ ok: true });
}
