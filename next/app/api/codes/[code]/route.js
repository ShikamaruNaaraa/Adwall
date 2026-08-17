import { NextResponse } from "next/server";
import { deleteTv } from "../../../../lib/store";

// DELETE /api/codes/{code} - remove a TV entirely: closes its live SSE
// connection if it has one open and deletes the pairing (in memory and in
// the database). Used by the admin app's "remove TV" action.
export async function DELETE(request, { params }) {
  const { code } = await params;
  const removed = deleteTv(code);
  if (!removed) {
    return NextResponse.json({ detail: "Unknown TV code" }, { status: 404 });
  }
  return NextResponse.json({ ok: true });
}
