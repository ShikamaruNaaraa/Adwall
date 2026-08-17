import { NextResponse } from "next/server";
import { createAdmin, listAdmins } from "../../../lib/db";

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

// GET /api/admins - list every admin username (master dashboard).
export async function GET() {
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
