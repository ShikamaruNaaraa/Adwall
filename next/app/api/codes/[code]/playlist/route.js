import { NextResponse } from "next/server";
import { getEntry, updatePlaylistItem, removePlaylistItem, reorderPlaylistItem, ensureHydrated } from "../../../../../lib/store";
import { verifyAdminSession } from "../../../../../lib/db";

function getSessionUsername(request) {
  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : null;
  return verifyAdminSession(token);
}

// PATCH /api/codes/{code}/playlist - edit one ad already on this TV's
// playlist (identified by its position) without re-uploading it.
// JSON body: { index, duration_seconds }. Requires a valid admin session
// that owns this TV.
export async function PATCH(request, { params }) {
  await ensureHydrated();
  const { code } = await params;

  const sessionUsername = await getSessionUsername(request);
  if (!sessionUsername) {
    return NextResponse.json({ detail: "Not authenticated." }, { status: 401 });
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ detail: "Invalid JSON body" }, { status: 400 });
  }

  const entry = getEntry(code);
  if (!entry || (entry.adminUsername || null) !== sessionUsername) {
    return NextResponse.json({ detail: "Unknown or expired code" }, { status: 404 });
  }

  const index = Number(body?.index);
  if (!Number.isInteger(index) || index < 0) {
    return NextResponse.json({ detail: "index is required" }, { status: 400 });
  }

  if (body?.to_index !== undefined) {
    const toIndex = Number(body.to_index);
    if (!Number.isInteger(toIndex) || toIndex < 0) {
      return NextResponse.json({ detail: "to_index must be a valid position" }, { status: 400 });
    }
    const reordered = reorderPlaylistItem(code, index, toIndex);
    if (!reordered) {
      return NextResponse.json({ detail: "No ad at that index" }, { status: 404 });
    }
    return NextResponse.json({ playlist: reordered });
  }

  const hasDuration = body?.duration_seconds !== undefined;
  const hasName = body?.name !== undefined;
  if (!hasDuration && !hasName) {
    return NextResponse.json(
      { detail: "duration_seconds or name is required" },
      { status: 400 }
    );
  }

  let durationSeconds;
  if (hasDuration) {
    durationSeconds = Number(body.duration_seconds);
    if (!Number.isFinite(durationSeconds) || durationSeconds < 1) {
      return NextResponse.json(
        { detail: "duration_seconds must be at least 1" },
        { status: 400 }
      );
    }
  }

  let name;
  if (hasName) {
    name = String(body.name).trim();
    if (!name) {
      return NextResponse.json({ detail: "name cannot be empty" }, { status: 400 });
    }
  }

  const playlist = updatePlaylistItem(code, index, { durationSeconds, name });
  if (!playlist) {
    return NextResponse.json({ detail: "No ad at that index" }, { status: 404 });
  }
  return NextResponse.json({ playlist });
}

// DELETE /api/codes/{code}/playlist?index=N - remove one ad already on this
// TV's playlist (identified by its position). Requires a valid admin
// session that owns this TV.
export async function DELETE(request, { params }) {
  await ensureHydrated();
  const { code } = await params;
  const url = new URL(request.url);

  const sessionUsername = await getSessionUsername(request);
  if (!sessionUsername) {
    return NextResponse.json({ detail: "Not authenticated." }, { status: 401 });
  }

  const entry = getEntry(code);
  if (!entry || (entry.adminUsername || null) !== sessionUsername) {
    return NextResponse.json({ detail: "Unknown or expired code" }, { status: 404 });
  }

  const index = Number(url.searchParams.get("index"));
  if (!Number.isInteger(index) || index < 0) {
    return NextResponse.json({ detail: "index is required" }, { status: 400 });
  }

  const playlist = removePlaylistItem(code, index);
  if (!playlist) {
    return NextResponse.json({ detail: "No ad at that index" }, { status: 404 });
  }
  return NextResponse.json({ playlist });
}
