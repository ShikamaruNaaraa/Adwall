import { NextResponse } from "next/server";
import { mkdir, writeFile } from "fs/promises";
import path from "path";
import { createServiceAd, listServiceAds } from "../../../lib/store";

const MEDIA_DIR = path.join(process.cwd(), "media_files");

// GET /api/service-ads - list every admin-wide service ad.
export async function GET() {
  return NextResponse.json(listServiceAds());
}

// POST /api/service-ads - upload an image and register it as a service ad.
// multipart/form-data: file, duration_seconds, interval
export async function POST(request) {
  const form = await request.formData();
  const file = form.get("file");
  const durationSeconds = Number(form.get("duration_seconds") ?? 10);
  const interval = Number(form.get("interval") ?? 1);

  // target_tv_codes: JSON-encoded array of TV codes, e.g. '["123456"]'.
  // Omitted, empty, or not valid JSON all mean "all TVs".
  let targetTvCodes = null;
  const rawTargetTvCodes = form.get("target_tv_codes");
  if (typeof rawTargetTvCodes === "string" && rawTargetTvCodes.trim()) {
    try {
      const parsed = JSON.parse(rawTargetTvCodes);
      if (Array.isArray(parsed) && parsed.length > 0) {
        targetTvCodes = parsed.map(String);
      }
    } catch {
      return NextResponse.json(
        { detail: "target_tv_codes must be a JSON array of TV codes" },
        { status: 400 }
      );
    }
  }

  if (!file || typeof file === "string") {
    return NextResponse.json({ detail: "file is required" }, { status: 400 });
  }
  if (!Number.isFinite(durationSeconds) || durationSeconds < 1) {
    return NextResponse.json(
      { detail: "duration_seconds must be at least 1" },
      { status: 400 }
    );
  }
  if (!Number.isFinite(interval) || interval < 1) {
    return NextResponse.json(
      { detail: "interval must be at least 1" },
      { status: 400 }
    );
  }

  await mkdir(MEDIA_DIR, { recursive: true });
  const safeName = `svc-${Date.now()}-${Math.random().toString(36).slice(2, 8)}${path.extname(file.name)}`;
  const filePath = path.join(MEDIA_DIR, safeName);
  const bytes = Buffer.from(await file.arrayBuffer());
  await writeFile(filePath, bytes);

  const mediaUrl = `/media/${safeName}`;
  const ad = createServiceAd({
    mediaUrl,
    mediaType: "image",
    durationSeconds,
    interval,
    targetTvCodes,
  });
  return NextResponse.json(ad);
}
