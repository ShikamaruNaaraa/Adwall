import { NextResponse } from "next/server";
import { mkdir, writeFile } from "fs/promises";
import path from "path";
import { setGroupAnimationMedia, getGroup, ensureHydrated } from "../../../../../lib/store";

const MEDIA_DIR = path.join(process.cwd(), "media_files");

// POST /api/groups/{id}/animation - upload the one video that plays
// stretched across this group's TVs, split into equal vertical slices.
// multipart/form-data: file
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

  await mkdir(MEDIA_DIR, { recursive: true });
  const safeName = `grp-${id}-${Date.now()}${path.extname(file.name)}`;
  const filePath = path.join(MEDIA_DIR, safeName);
  const bytes = Buffer.from(await file.arrayBuffer());
  await writeFile(filePath, bytes);

  const mediaUrl = `/media/${safeName}`;
  const group = setGroupAnimationMedia(id, { mediaUrl, mediaType: "video" });
  return NextResponse.json(group);
}
