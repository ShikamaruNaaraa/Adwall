import { NextResponse } from "next/server";
import { mkdir, writeFile } from "fs/promises";
import path from "path";
import { getEntry, setPlaylist } from "../../../lib/store";

const MEDIA_DIR = path.join(process.cwd(), "media_files");

function mediaTypeFor(fileName) {
  const ext = path.extname(fileName).toLowerCase();
  const videoExts = [".mp4", ".mov", ".webm", ".mkv"];
  return videoExts.includes(ext) ? "video" : "image";
}

// POST /api/media - upload one ad and attach it to several TVs at once, so
// the same file shows up on every selected TV instead of having to upload
// it once per TV.
// multipart/form-data: file, duration_seconds, codes (JSON array of TV codes)
export async function POST(request) {
  const form = await request.formData();
  const file = form.get("file");
  const durationSeconds = Number(form.get("duration_seconds") ?? 10);
  const codesRaw = form.get("codes");

  if (!file || typeof file === "string") {
    return NextResponse.json({ detail: "file is required" }, { status: 400 });
  }
  if (!Number.isFinite(durationSeconds) || durationSeconds < 1) {
    return NextResponse.json(
      { detail: "duration_seconds must be at least 1" },
      { status: 400 }
    );
  }

  let codes;
  try {
    codes = JSON.parse(String(codesRaw ?? "[]"));
  } catch {
    codes = null;
  }
  if (!Array.isArray(codes) || codes.length === 0) {
    return NextResponse.json(
      { detail: "codes (a non-empty array of TV codes) is required" },
      { status: 400 }
    );
  }

  const targets = codes.map((code) => ({ code, entry: getEntry(code) }));
  const missing = targets.filter((t) => !t.entry).map((t) => t.code);
  if (missing.length > 0) {
    return NextResponse.json(
      { detail: `Unknown or expired code(s): ${missing.join(", ")}` },
      { status: 404 }
    );
  }

  await mkdir(MEDIA_DIR, { recursive: true });
  const safeName = `ad-${Date.now()}-${Math.random().toString(36).slice(2, 8)}${path.extname(file.name)}`;
  const filePath = path.join(MEDIA_DIR, safeName);
  const bytes = Buffer.from(await file.arrayBuffer());
  await writeFile(filePath, bytes);

  const mediaUrl = `/media/${safeName}`;
  const item = {
    mediaType: mediaTypeFor(file.name),
    mediaUrl,
    durationSeconds,
  };

  const results = {};
  for (const { code, entry } of targets) {
    const playlist = [...entry.playlist, item];
    setPlaylist(code, playlist);
    results[code] = playlist;
  }

  return NextResponse.json({ media_url: mediaUrl, results });
}
