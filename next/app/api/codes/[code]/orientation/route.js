import { NextResponse } from "next/server";
import { getEntry, setOrientation } from "../../../../../lib/store";

// PATCH /api/codes/{code}/orientation - admin sets a TV's display
// orientation. JSON body: { orientation: 'landscape' | 'portrait',
// admin_username }. admin_username scopes this to TVs the caller owns.
export async function PATCH(request, { params }) {
  const { code } = await params;

  let body;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ detail: "Invalid JSON body" }, { status: 400 });
  }

  const orientation = body?.orientation;
  if (orientation !== "landscape" && orientation !== "portrait") {
    return NextResponse.json(
      { detail: "orientation must be 'landscape' or 'portrait'" },
      { status: 400 }
    );
  }

  const adminUsername = (body?.admin_username || "").trim() || null;
  const existing = getEntry(code);
  if (!existing || (existing.adminUsername || null) !== adminUsername) {
    return NextResponse.json({ detail: "Unknown TV code" }, { status: 404 });
  }

  const entry = setOrientation(code, orientation);
  if (!entry) {
    return NextResponse.json({ detail: "Unknown TV code" }, { status: 404 });
  }
  return NextResponse.json({ code, orientation: entry.orientation });
}

