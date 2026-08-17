import { NextResponse } from "next/server";
import { listAdmins } from "../../../lib/db";
import { listAllTvs, ensureHydrated } from "../../../lib/store";

// GET /api/admins-overview - master dashboard: every admin, each admin's
// TVs, and the ads currently playing on each TV (regular + service ads).
// TVs with no admin_username (e.g. created before this feature existed)
// are grouped under "unassigned".
export async function GET() {
  await ensureHydrated();
  try {
    const admins = await listAdmins();
    const tvs = listAllTvs();

    const tvsByAdmin = new Map();
    for (const tv of tvs) {
      const key = tv.adminUsername || null;
      if (!tvsByAdmin.has(key)) tvsByAdmin.set(key, []);
      tvsByAdmin.get(key).push(tv);
    }

    const overview = admins.map((admin) => ({
      username: admin.username,
      mustChangePassword: admin.mustChangePassword,
      createdAt: admin.createdAt,
      tvs: tvsByAdmin.get(admin.username) || [],
    }));

    const unassignedTvs = tvsByAdmin.get(null) || [];

    return NextResponse.json({ admins: overview, unassignedTvs });
  } catch (err) {
    return NextResponse.json(
      { detail: "Failed to load overview: " + err.message },
      { status: 500 }
    );
  }
}
