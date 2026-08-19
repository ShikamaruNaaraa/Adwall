import { NextResponse } from "next/server";
import { masterAdminExists } from "../../../lib/db";

// GET /api/master-admin - whether a master admin account already exists.
// The dashboard uses this to decide whether to show "Sign up" (none yet)
// or only "Log in" (one already created).
export async function GET() {
  try {
    const exists = await masterAdminExists();
    return NextResponse.json({ exists });
  } catch (err) {
    return NextResponse.json(
      { detail: "Failed to check master admin status: " + err.message },
      { status: 500 }
    );
  }
}
