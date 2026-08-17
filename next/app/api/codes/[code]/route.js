import { NextResponse } from "next/server";
import { deleteTv, getEntry } from "../../../../lib/store";

// DELETE /api/codes/{code} - remove a TV entirely: closes its live SSE
// connection if it has one open and deletes the pairing (in memory and in
// the database). Used by the admin app's "remove TV" action.
// Query param admin_username scopes this to TVs the caller owns - an admin
// cannot delete another admin's TV even if they know its code.
export async function DELETE(request, { params }) {
  const { code } = await params;
  const adminUsername = new URL(request.url).searchParams.get("admin_username");

  const entry = getEntry(code);
  if (!entry) {
    return NextResponse.json({ detail: "Unknown TV code" }, { status: 404 });
  }
  if ((entry.adminUsername || null) !== (adminUsername || null)) {
    return NextResponse.json({ detail: "Unknown TV code" }, { status: 404 });
  }

  const removed = deleteTv(code);
  if (!removed) {
    return NextResponse.json({ detail: "Unknown TV code" }, { status: 404 });
  }
  return NextResponse.json({ ok: true });
}

