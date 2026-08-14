import { NextResponse } from "next/server";
import { claimCode, getEntry } from "../../../../../lib/store";

export async function POST(request, { params }) {
  const { code } = await params;

  let body;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ detail: "Invalid JSON body" }, { status: 400 });
  }

  const tvDeviceId = (body?.tv_device_id || "").trim();
  if (!tvDeviceId) {
    return NextResponse.json({ detail: "tv_device_id is required" }, { status: 400 });
  }

  const existing = getEntry(code);
  if (!existing) {
    return NextResponse.json({ detail: "Unknown or expired code" }, { status: 404 });
  }

  const entry = claimCode(code, tvDeviceId);
  return NextResponse.json({ nickname: entry.nickname });
}
