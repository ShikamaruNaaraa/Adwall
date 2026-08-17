import { NextResponse } from "next/server";
import { playGroupAnimation, ensureHydrated } from "../../../../../lib/store";

// POST /api/groups/{id}/play - starts the snake/wave group animation.
// Optional body: { duration_per_screen_ms, color }
// Broadcasts one SSE frame to every connected TV in the group's order, all
// stamped with the same near-future start timestamp so playback stays in
// sync across screens (see playGroupAnimation in lib/store.js).
export async function POST(request, { params }) {
  await ensureHydrated();
  const { id } = await params;

  let body = {};
  try {
    body = await request.json();
  } catch {
    // No/empty body is fine - defaults apply.
  }

  const options = {};
  if (body?.duration_per_screen_ms !== undefined) {
    options.durationPerScreenMs = Number(body.duration_per_screen_ms) || 1500;
  }
  if (body?.color !== undefined) {
    options.color = String(body.color);
  }
  if (body?.text !== undefined) {
    options.text = String(body.text);
  }
  if (body?.text_color !== undefined) {
    options.textColor = String(body.text_color);
  }
  if (body?.text_font_size !== undefined) {
    options.textFontSize = Number(body.text_font_size) || 48;
  }
  if (body?.text_position_y !== undefined) {
    options.textPositionY = Number(body.text_position_y);
  }

  const result = playGroupAnimation(id, options);
  if (!result) {
    return NextResponse.json({ detail: "Unknown group" }, { status: 404 });
  }
  return NextResponse.json(result);
}
