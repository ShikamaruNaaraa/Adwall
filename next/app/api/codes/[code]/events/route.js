import { getEntry, subscribe, unsubscribe, ensureHydrated } from "../../../../../lib/store";

// Server-Sent Events: lighter than WebSocket for this one-way
// server->client "waiting / paired" push, and works as a plain Next.js
// route handler with no custom server required.
export async function GET(request, { params }) {
  await ensureHydrated();
  const { code } = await params;

  if (!getEntry(code)) {
    return new Response(JSON.stringify({ detail: "Unknown or expired code" }), {
      status: 404,
      headers: { "Content-Type": "application/json" },
    });
  }

  let controllerRef;
  const stream = new ReadableStream({
    start(controller) {
      controllerRef = controller;
      subscribe(code, controller);
    },
    cancel() {
      unsubscribe(code, controllerRef);
    },
  });

  request.signal.addEventListener("abort", () => {
    unsubscribe(code, controllerRef);
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
    },
  });
}
