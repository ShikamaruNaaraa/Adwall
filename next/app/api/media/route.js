import { NextResponse } from "next/server";
import { mkdir, writeFile } from "fs/promises";
import path from "path";
import { getEntry, setPlaylist, ensureHydrated } from "../../../lib/store";
import { verifyAdminSession } from "../../../lib/db";

const MEDIA_DIR = path.join(process.cwd(), "media_files");

const ALLOWED_EXTS = new Set([".jpg", ".jpeg", ".png", ".gif", ".webp", ".mp4", ".mov", ".webm", ".mkv"]);

function mediaTypeFor(fileName) {
  const ext = path.extname(fileName).toLowerCase();
  const videoExts = [".mp4", ".mov", ".webm", ".mkv"];
  return videoExts.includes(ext) ? "video" : "image";
}

// POST /api/media - upload one ad and attach it to several TVs at once, so
// the same file shows up on every selected TV instead of having to upload
// it once per TV.
// multipart/form-data: file, duration_seconds, codes (JSON array of TV codes)
// Requires a valid admin session (Authorization: Bearer <token>).
export async function POST(request) {
  await ensureHydrated();
  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : null;
  const sessionUsername = await verifyAdminSession(token);
  if (!sessionUsername) {
    return NextResponse.json({ detail: "Not authenticated." }, { status: 401 });
  }

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
  // Missing or not-owned-by-this-admin codes are treated the same way, so a
  // caller can't distinguish "unknown code" from "someone else's TV".
  const missing = targets
    .filter((t) => !t.entry || (t.entry.adminUsername || null) !== sessionUsername)
    .map((t) => t.code);
  if (missing.length > 0) {
    return NextResponse.json(
      { detail: `Unknown or expired code(s): ${missing.join(", ")}` },
      { status: 404 }
    );
  }


  const ext = path.extname(file.name).toLowerCase();
  if (!ALLOWED_EXTS.has(ext)) {
    return NextResponse.json({ detail: "Unsupported file type" }, { status: 400 });
  }

  await mkdir(MEDIA_DIR, { recursive: true });
  const safeName = `ad-${Date.now()}-${Math.random().toString(36).slice(2, 8)}${ext}`;
  const filePath = path.join(MEDIA_DIR, safeName);
  const bytes = Buffer.from(await file.arrayBuffer());
  await writeFile(filePath, bytes);

  const mediaUrl = `/media/${safeName}`;
  const item = {
    mediaType: mediaTypeFor(file.name),
    mediaUrl,
    name: file.name,
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
