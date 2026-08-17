import { NextResponse } from "next/server";
import { mkdir, writeFile } from "fs/promises";
import path from "path";
import { getEntry, setPlaylist, ensureHydrated } from "../../../../../lib/store";
const MEDIA_DIR = path.join(process.cwd(), "media_files");

function mediaTypeFor(fileName) {
  const ext = path.extname(fileName).toLowerCase();
  const videoExts = [".mp4", ".mov", ".webm", ".mkv"];
  return videoExts.includes(ext) ? "video" : "image";
}

export async function POST(request, { params }) {
  await ensureHydrated();
  const { code } = await params;

  const form = await request.formData();
  const adminUsername = (form.get("admin_username") || "").toString().trim() || null;

  const entry = getEntry(code);
  if (!entry || (entry.adminUsername || null) !== adminUsername) {
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

  await mkdir(MEDIA_DIR, { recursive: true });
  const safeName = `${code}-${Date.now()}${path.extname(file.name)}`;
  const filePath = path.join(MEDIA_DIR, safeName);
  const bytes = Buffer.from(await file.arrayBuffer());
  await writeFile(filePath, bytes);

  const mediaUrl = `/media/${safeName}`;
  const playlist = [
    ...entry.playlist,
    {
      mediaType: mediaTypeFor(file.name),
      mediaUrl,
      durationSeconds,
    },
  ];
  setPlaylist(code, playlist);

  return NextResponse.json({ media_url: mediaUrl, playlist });
}
