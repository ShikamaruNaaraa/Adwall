import { readFile } from "fs/promises";
import path from "path";

const MEDIA_DIR = path.join(process.cwd(), "media_files");

const CONTENT_TYPES = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".mp4": "video/mp4",
  ".mov": "video/quicktime",
  ".webm": "video/webm",
};

export async function GET(request, { params }) {
  const { file } = await params;
  // Guard against path traversal - only allow the plain filename.
  if (file.includes("/") || file.includes("..")) {
    return new Response("Not found", { status: 404 });
  }

  const filePath = path.join(MEDIA_DIR, file);
  try {
    const bytes = await readFile(filePath);
    const ext = path.extname(file).toLowerCase();
    return new Response(bytes, {
      headers: { "Content-Type": CONTENT_TYPES[ext] || "application/octet-stream" },
    });
  } catch {
    return new Response("Not found", { status: 404 });
  }
}
