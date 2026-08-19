import { NextResponse } from "next/server";
import { getEntry, setTransition } from "../../../../../lib/store";
import { verifyAdminSession } from "../../../../../lib/db";

const VALID_TRANSITIONS = new Set([
  "none",
  "slide_left_to_right",
  "slide_right_to_left",
  "slide_top_to_bottom",
  "slide_bottom_to_top",
  "fade",
  "blur",
]);

// PATCH /api/codes/{code}/transition - admin sets the transition used when
// this TV's currently-shown image changes to the next one.
// JSON body: { transition: one of VALID_TRANSITIONS above }.
// Requires a valid admin session that owns this TV.
export async function PATCH(request, { params }) {
  const { code } = await params;

  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : null;
  const sessionUsername = await verifyAdminSession(token);
  if (!sessionUsername) {
    return NextResponse.json({ detail: "Not authenticated." }, { status: 401 });
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ detail: "Invalid JSON body" }, { status: 400 });
  }

  const transition = body?.transition;
  if (!VALID_TRANSITIONS.has(transition)) {
    return NextResponse.json(
      { detail: `transition must be one of: ${[...VALID_TRANSITIONS].join(", ")}` },
      { status: 400 }
    );
  }


  const existing = getEntry(code);
  if (!existing || (existing.adminUsername || null) !== sessionUsername) {
    return NextResponse.json({ detail: "Unknown TV code" }, { status: 404 });
  }

  const entry = setTransition(code, transition);
  if (!entry) {
    return NextResponse.json({ detail: "Unknown TV code" }, { status: 404 });
  }
  return NextResponse.json({ code, transition: entry.transition });
}
