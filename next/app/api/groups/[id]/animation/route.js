import { NextResponse } from "next/server";
import { mkdir, writeFile } from "fs/promises";
import path from "path";
import { setGroupAnimationMedia, getGroup, ensureHydrated } from "../../../../../lib/store";

const MEDIA_DIR = path.join(process.cwd(), "media_files");

function mediaTypeFor(fileName) {
  const ext = path.extname(fileName).toLowerCase();
  const videoExts = [".mp4", ".mov", ".webm", ".mkv"];
  return videoExts.includes(ext) ? "video" : "image";
}

// POST /api/groups/{id}/animation - upload the one media file (image or
// video) that this group's animation hands off across its TVs, in order.
// multipart/form-data: file, duration_seconds (optional, images only)
export async function POST(request, { params }) {
  await ensureHydrated();
  const { id } = await params;

  if (!getGroup(id)) {
    return NextResponse.json({ detail: "Unknown group" }, { status: 404 });
  }

  const form = await request.formData();
  const file = form.get("file");
  if (!file || typeof file === "string") {
    return NextResponse.json({ detail: "file is required" }, { status: 400 });
  }

  const mediaType = mediaTypeFor(file.name);
  let durationSeconds;
  if (form.get("duration_seconds") !== null) {
    durationSeconds = Number(form.get("duration_seconds"));
    if (!Number.isFinite(durationSeconds) || durationSeconds < 1) {
      return NextResponse.json(
        { detail: "duration_seconds must be at least 1" },
        { status: 400 }
      );
    }
  }

  await mkdir(MEDIA_DIR, { recursive: true });
  const safeName = `grp-${id}-${Date.now()}${path.extname(file.name)}`;
  const filePath = path.join(MEDIA_DIR, safeName);
  const bytes = Buffer.from(await file.arrayBuffer());
  await writeFile(filePath, bytes);

  const mediaUrl = `/media/${safeName}`;
  const group = setGroupAnimationMedia(id, { mediaUrl, mediaType, durationSeconds });
  return NextResponse.json(group);
}
