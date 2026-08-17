import { NextResponse } from "next/server";
import { changeAdminPassword } from "../../../../../lib/db";

const PASSWORD_RULE_MESSAGE =
  "Password must be at least 8 characters and include at least 1 letter and 1 number.";

function isValidPassword(password) {
  return (
    typeof password === "string" &&
    password.length >= 8 &&
    /[A-Za-z]/.test(password) &&
    /[0-9]/.test(password)
  );
}

// POST /api/admins/{username}/password - change an admin's own password.
// JSON body: { current_password, new_password }. Requires the current
// password to match (this is not a master-admin reset endpoint).
export async function POST(request, { params }) {
  const { username } = await params;

  let body;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ detail: "Invalid JSON body" }, { status: 400 });
  }

  const currentPassword = body?.current_password || "";
  const newPassword = body?.new_password || "";

  if (!currentPassword || !newPassword) {
    return NextResponse.json(
      { detail: "current_password and new_password are required" },
      { status: 400 }
    );
  }
  if (!isValidPassword(newPassword)) {
    return NextResponse.json({ detail: PASSWORD_RULE_MESSAGE }, { status: 400 });
  }

  try {
    const ok = await changeAdminPassword(username, currentPassword, newPassword);
    if (!ok) {
      return NextResponse.json(
        { detail: "Current password is incorrect." },
        { status: 401 }
      );
    }
    return NextResponse.json({ ok: true });
  } catch (err) {
    return NextResponse.json(
      { detail: "Failed to change password: " + err.message },
      { status: 500 }
    );
  }
}
