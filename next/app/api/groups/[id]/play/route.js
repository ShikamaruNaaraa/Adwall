import { NextResponse } from "next/server";
import { playGroupAnimation, ensureHydrated } from "../../../../../lib/store";

// POST /api/groups/{id}/play - starts the group animation: sends the
// group's attached media to the first connected TV in its order. Later TVs
// pick it up one at a time as each prior one finishes (see
// /api/groups/{id}/advance and playGroupAnimation in lib/store.js).
export async function POST(_request, { params }) {
  await ensureHydrated();
  const { id } = await params;

  const result = playGroupAnimation(id);
  if (!result) {
    return NextResponse.json({ detail: "Unknown group" }, { status: 404 });
  }
  if (result.error === "no_media") {
    return NextResponse.json(
      { detail: "Add an animation to this group before playing it." },
      { status: 400 }
    );
  }
  return NextResponse.json(result);
}
