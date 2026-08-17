import { NextResponse } from "next/server";
import { updateGroup, deleteGroup, ensureHydrated } from "../../../../lib/store";

// PATCH /api/groups/{id} - rename a group and/or replace its ordered TV
// list. Body: { name?, tv_codes? }
export async function PATCH(request, { params }) {
  await ensureHydrated();
  const { id } = await params;

  let body;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ detail: "Invalid JSON body" }, { status: 400 });
  }

  const patch = {};
  if (body?.name !== undefined) patch.name = String(body.name).trim();
  if (body?.tv_codes !== undefined) {
    if (!Array.isArray(body.tv_codes) || body.tv_codes.length < 2) {
      return NextResponse.json(
        { detail: "tv_codes must include at least 2 TVs" },
        { status: 400 }
      );
    }
    patch.tvCodes = body.tv_codes;
  }

  const group = updateGroup(id, patch);
  if (!group) {
    return NextResponse.json({ detail: "Unknown group" }, { status: 404 });
  }
  return NextResponse.json(group);
}

// DELETE /api/groups/{id} - remove a group (does not affect the TVs
// themselves, just the saved order/selection).
export async function DELETE(_request, { params }) {
  await ensureHydrated();
  const { id } = await params;
  const removed = deleteGroup(id);
  if (!removed) {
    return NextResponse.json({ detail: "Unknown group" }, { status: 404 });
  }
  return NextResponse.json({ ok: true });
}
