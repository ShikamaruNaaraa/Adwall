import { NextResponse } from "next/server";
import { advanceGroupAnimation, ensureHydrated } from "../../../../../lib/store";

// POST /api/groups/{id}/advance - called by a TV once its copy of the
// group animation finishes playing, so the backend can hand off to the
// next TV in the group's order. Body: { index } - the position (0-based)
// the reporting TV was playing at.
export async function POST(request, { params }) {
  await ensureHydrated();
  const { id } = await params;

  let body;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ detail: "Invalid JSON body" }, { status: 400 });
  }

  const index = Number(body?.index);
  if (!Number.isInteger(index) || index < 0) {
    return NextResponse.json({ detail: "index is required" }, { status: 400 });
  }

  const result = advanceGroupAnimation(id, index);
  if (!result) {
    return NextResponse.json({ detail: "Unknown group" }, { status: 404 });
  }
  return NextResponse.json(result);
}
