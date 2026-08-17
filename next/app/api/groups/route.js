import { NextResponse } from "next/server";
import { createGroup, listGroups, ensureHydrated } from "../../../lib/store";

// GET /api/groups - every TV group, in creation order.
export async function GET() {
  await ensureHydrated();
  return NextResponse.json(listGroups());
}

// POST /api/groups - create a group. Body: { name, tv_codes: [code, ...] }
// tv_codes order is the animation order (snake starts on tv_codes[0]).
export async function POST(request) {
  await ensureHydrated();
  let body;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ detail: "Invalid JSON body" }, { status: 400 });
  }

  const name = (body?.name || "").trim();
  if (!name) {
    return NextResponse.json({ detail: "name is required" }, { status: 400 });
  }
  const tvCodes = Array.isArray(body?.tv_codes) ? body.tv_codes : [];
  if (tvCodes.length < 2) {
    return NextResponse.json(
      { detail: "tv_codes must include at least 2 TVs" },
      { status: 400 }
    );
  }

  const group = createGroup(name, tvCodes);
  return NextResponse.json(group);
}
