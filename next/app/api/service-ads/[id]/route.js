import { NextResponse } from "next/server";
import { deleteServiceAd, updateServiceAd } from "../../../../lib/store";

// PATCH /api/service-ads/{id} - edit an existing service ad's duration
// and/or play interval (occurrence count).
// JSON body: { duration_seconds?, interval? }
export async function PATCH(request, { params }) {
  const { id } = await params;

  let body;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ detail: "Invalid JSON body" }, { status: 400 });
  }

  const updates = {};
  if (body?.duration_seconds !== undefined) {
    const durationSeconds = Number(body.duration_seconds);
    if (!Number.isFinite(durationSeconds) || durationSeconds < 1) {
      return NextResponse.json(
        { detail: "duration_seconds must be at least 1" },
        { status: 400 }
      );
    }
    updates.durationSeconds = durationSeconds;
  }
  if (body?.interval !== undefined) {
    const interval = Number(body.interval);
    if (!Number.isFinite(interval) || interval < 1) {
      return NextResponse.json(
        { detail: "interval must be at least 1" },
        { status: 400 }
      );
    }
    updates.interval = interval;
  }
  // target_tv_codes: array of TV codes to restrict this ad to, or
  // null/empty array to play it on every TV.
  if (body?.target_tv_codes !== undefined) {
    if (
      body.target_tv_codes !== null &&
      !Array.isArray(body.target_tv_codes)
    ) {
      return NextResponse.json(
        { detail: "target_tv_codes must be an array of TV codes or null" },
        { status: 400 }
      );
    }
    updates.targetTvCodes = body.target_tv_codes;
  }

  const updated = updateServiceAd(id, updates);
  if (!updated) {
    return NextResponse.json({ detail: "Unknown service ad" }, { status: 404 });
  }
  return NextResponse.json(updated);
}

// DELETE /api/service-ads/{id} - remove a service ad. It stops being
// inserted into every TV's playlist immediately (SSE push).
export async function DELETE(request, { params }) {
  const { id } = await params;
  const removed = deleteServiceAd(id);
  if (!removed) {
    return NextResponse.json({ detail: "Unknown service ad" }, { status: 404 });
  }
  return NextResponse.json({ ok: true });
}

