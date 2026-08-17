import { NextResponse } from "next/server";
import { getEntry, updatePlaylistItem } from "../../../../../lib/store";

// PATCH /api/codes/{code}/playlist - edit one ad already on this TV's
// playlist (identified by its position) without re-uploading it.
// JSON body: { index, duration_seconds }
export async function PATCH(request, { params }) {
  const { code } = await params;

  const entry = getEntry(code);
  if (!entry) {
    return NextResponse.json({ detail: "Unknown or expired code" }, { status: 404 });
  }

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

  const durationSeconds = Number(body?.duration_seconds);
  if (!Number.isFinite(durationSeconds) || durationSeconds < 1) {
    return NextResponse.json(
      { detail: "duration_seconds must be at least 1" },
      { status: 400 }
    );
  }

  const playlist = updatePlaylistItem(code, index, { durationSeconds });
  if (!playlist) {
    return NextResponse.json({ detail: "No ad at that index" }, { status: 404 });
  }
  return NextResponse.json({ playlist });
}
