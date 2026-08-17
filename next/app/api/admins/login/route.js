import { NextResponse } from "next/server";
import { verifyAdminLogin } from "../../../../lib/db";

// POST /api/admins/login - admin app login.
// JSON body: { username, password }.
// Returns { username, mustChangePassword } on success - mustChangePassword
// is true for a freshly created account and tells the app to prompt for a
// new password before continuing.
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
      { detail: "username and password are required" },
      { status: 400 }
    );
  }

  try {
    const result = await verifyAdminLogin(username, password);
    if (!result) {
      return NextResponse.json(
        { detail: "Incorrect username or password." },
        { status: 401 }
      );
    }
    return NextResponse.json(result);
  } catch (err) {
    return NextResponse.json(
      { detail: "Login failed: " + err.message },
      { status: 500 }
    );
  }
}
