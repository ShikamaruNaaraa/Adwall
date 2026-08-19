import { NextResponse } from "next/server";
import { createMasterAdmin } from "../../../../lib/db";

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

// POST /api/master-admin/signup - creates the one and only master admin
// account. Rejected with 409 if one already exists - use
// /api/master-admin/login instead.
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

  if (!username) {
    return NextResponse.json({ detail: "Username is required." }, { status: 400 });
  }
  if (!isValidPassword(password)) {
    return NextResponse.json({ detail: PASSWORD_RULE_MESSAGE }, { status: 400 });
  }

  try {
    const session = await createMasterAdmin(username, password);
    return NextResponse.json(session);
  } catch (err) {
    if (err.code === "MASTER_ADMIN_EXISTS") {
      return NextResponse.json(
        { detail: "A master admin account already exists. Please log in instead." },
        { status: 409 }
      );
    }
    return NextResponse.json(
      { detail: "Failed to create master admin: " + err.message },
      { status: 500 }
    );
  }
}
