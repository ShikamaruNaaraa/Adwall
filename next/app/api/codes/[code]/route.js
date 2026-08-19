import { NextResponse } from "next/server";
import { deleteTv, getEntry } from "../../../../lib/store";
import { verifyAdminSession } from "../../../../lib/db";

// DELETE /api/codes/{code} - remove a TV entirely: closes its live SSE
// connection if it has one open and deletes the pairing (in memory and in
// the database). Used by the admin app's "remove TV" action.
// Requires a valid admin session; an admin cannot delete another admin's
// TV even if they know its code.
export async function DELETE(request, { params }) {
  const { code } = await params;
  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : null;
  const sessionUsername = await verifyAdminSession(token);
  if (!sessionUsername) {
    return NextResponse.json({ detail: "Not authenticated." }, { status: 401 });
  }

  const entry = getEntry(code);
  if (!entry) {
    return NextResponse.json({ detail: "Unknown TV code" }, { status: 404 });
  }
  if ((entry.adminUsername || null) !== sessionUsername) {
    return NextResponse.json({ detail: "Unknown TV code" }, { status: 404 });
  }

  const removed = deleteTv(code);
  if (!removed) {
    return NextResponse.json({ detail: "Unknown TV code" }, { status: 404 });
  }
  return NextResponse.json({ ok: true });
}
