import { NextResponse } from "next/server";
import { createAdmin, listAdmins, verifyMasterAdminSession } from "../../../lib/db";

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

// Both handlers below require a valid master-admin session: this route
// creates/lists the admin accounts that manage TVs, so it must only be
// reachable by the logged-in master admin, not just gated in the UI.
async function requireMasterAdmin(request) {
  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : null;
  const username = await verifyMasterAdminSession(token);
  return username;
}

// GET /api/admins - list every admin username (master dashboard).
export async function GET(request) {
  if (!(await requireMasterAdmin(request))) {
    return NextResponse.json({ detail: "Not authenticated." }, { status: 401 });
  }
  try {
    const admins = await listAdmins();
    return NextResponse.json(admins);
  } catch (err) {
    return NextResponse.json(
      { detail: "Failed to load admins: " + err.message },
      { status: 500 }
    );
  }
}

// POST /api/admins - master admin creates a new admin account.
// JSON body: { username, password }. Rejects a duplicate username with 409.
export async function POST(request) {
  if (!(await requireMasterAdmin(request))) {
    return NextResponse.json({ detail: "Not authenticated." }, { status: 401 });
  }
  let body;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ detail: "Invalid JSON body" }, { status: 400 });
  }

  const username = (body?.username || "").trim();
  const password = body?.password || "";

  if (!username) {
    return NextResponse.json({ detail: "username is required" }, { status: 400 });
  }
  if (!isValidPassword(password)) {
    return NextResponse.json({ detail: PASSWORD_RULE_MESSAGE }, { status: 400 });
  }

  try {
    await createAdmin(username, password);
    return NextResponse.json({ username });
  } catch (err) {
    if (err.code === "DUPLICATE_USERNAME") {
      return NextResponse.json(
        { detail: "That username is already taken." },
        { status: 409 }
      );
    }
    return NextResponse.json(
      { detail: "Failed to create admin: " + err.message },
      { status: 500 }
    );
  }
}
