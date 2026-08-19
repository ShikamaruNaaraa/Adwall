import { NextResponse } from "next/server";
import { mkdir, writeFile } from "fs/promises";
import path from "path";
import { getEntry, setPlaylist, ensureHydrated } from "../../../../../lib/store";
import { verifyAdminSession } from "../../../../../lib/db";
const MEDIA_DIR = path.join(process.cwd(), "media_files");
const ALLOWED_EXTS = new Set([".jpg", ".jpeg", ".png", ".gif", ".webp", ".mp4", ".mov", ".webm", ".mkv"]);

function mediaTypeFor(fileName) {
  const ext = path.extname(fileName).toLowerCase();
  const videoExts = [".mp4", ".mov", ".webm", ".mkv"];
  return videoExts.includes(ext) ? "video" : "image";
}

export async function POST(request, { params }) {
  await ensureHydrated();
  const { code } = await params;

  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : null;
  const sessionUsername = await verifyAdminSession(token);
  if (!sessionUsername) {
    return NextResponse.json({ detail: "Not authenticated." }, { status: 401 });
  }

  const form = await request.formData();

  const entry = getEntry(code);
  if (!entry || (entry.adminUsername || null) !== sessionUsername) {
    return NextResponse.json({ detail: "Unknown or expired code" }, { status: 404 });
  }

  const file = form.get("file");
  const durationSeconds = Number(form.get("duration_seconds") ?? 10);
  if (!file || typeof file === "string") {
    return NextResponse.json({ detail: "file is required" }, { status: 400 });
  }
  if (!Number.isFinite(durationSeconds) || durationSeconds < 1) {
    return NextResponse.json({ detail: "duration_seconds must be at least 1" }, { status: 400 });
  }

  const ext = path.extname(file.name).toLowerCase();
  if (!ALLOWED_EXTS.has(ext)) {
    return NextResponse.json({ detail: "Unsupported file type" }, { status: 400 });
  }

  await mkdir(MEDIA_DIR, { recursive: true });
  const safeName = `${code}-${Date.now()}${ext}`;
  const filePath = path.join(MEDIA_DIR, safeName);
  const bytes = Buffer.from(await file.arrayBuffer());
  await writeFile(filePath, bytes);

  const mediaUrl = `/media/${safeName}`;
  const playlist = [
    ...entry.playlist,
    {
      mediaType: mediaTypeFor(file.name),
      mediaUrl,
      name: file.name,
      durationSeconds,
    },
  ];
  setPlaylist(code, playlist);

  return NextResponse.json({ media_url: mediaUrl, playlist });
}
