import { NextResponse } from "next/server";
import { verifyMasterAdminLogin } from "../../../../lib/db";

// POST /api/master-admin/login - master admin dashboard login.
// JSON body: { username, password }. Returns { username, token } on success.
export async function POST(request) {
  let body;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ detail: "Invalid JSON body" }, { status: 400 });
  }

  const username = (body?.username || "").trim();
  const password = body?.password || "";
  if (!username || !password) {
    return NextResponse.json(
      { detail: "Username and password are required." },
      { status: 400 }
    );
  }

  try {
    const session = await verifyMasterAdminLogin(username, password);
    if (!session) {
      return NextResponse.json(
        { detail: "Incorrect username or password." },
        { status: 401 }
      );
    }
    return NextResponse.json(session);
  } catch (err) {
    return NextResponse.json(
      { detail: "Login failed: " + err.message },
      { status: 500 }
    );
  }
}
