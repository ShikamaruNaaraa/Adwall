import { NextResponse } from "next/server";
import { deleteAdmin, verifyMasterAdminSession } from "../../../../lib/db";
import { deleteAdminTvs, ensureHydrated } from "../../../../lib/store";

// DELETE /api/admins/{username} - master admin permanently deletes an admin
// account. First removes every TV that admin owns (each TV's live SSE
// connection is told it's been removed, then it's dropped from memory and
// the database - see store.deleteAdminTvs), then deletes the admin account
// and its login sessions. Requires a valid master-admin session.
export async function DELETE(request, { params }) {
  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : null;
  if (!(await verifyMasterAdminSession(token))) {
    return NextResponse.json({ detail: "Not authenticated." }, { status: 401 });
  }

  const { username } = await params;
  if (!username) {
    return NextResponse.json({ detail: "username is required" }, { status: 400 });
  }

  try {
    await ensureHydrated();
    const removedTvs = deleteAdminTvs(username);
    const deleted = await deleteAdmin(username);

    if (!deleted) {
      return NextResponse.json({ detail: "Admin not found." }, { status: 404 });
    }

    return NextResponse.json({ username, removedTvs });
  } catch (err) {
    return NextResponse.json(
      { detail: "Failed to delete admin: " + err.message },
      { status: 500 }
    );
  }
}
