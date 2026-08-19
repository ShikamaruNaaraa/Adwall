import { getEntry, subscribe, unsubscribe, ensureHydrated } from "../../../../../lib/store";

// Server-Sent Events: lighter than WebSocket for this one-way
// server->client "waiting / paired" push, and works as a plain Next.js
// route handler with no custom server required.
//
// A periodic ": ping" comment frame is sent every 15s so that a silently
// dropped connection (e.g. the server process was killed/restarted without
// a clean TCP close reaching the client, or a proxy in between swallows the
// FIN) surfaces as a failed write here - which drops the subscriber - and,
// on the client, as a stall the reconnect logic in watchPairing() detects,
// instead of the client's read loop hanging forever waiting for bytes that
// will never arrive.
const HEARTBEAT_INTERVAL_MS = 15000;

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
  let heartbeat;
  const stream = new ReadableStream({
    start(controller) {
      controllerRef = controller;
      subscribe(code, controller);
      heartbeat = setInterval(() => {
        try {
          controller.enqueue(`: ping\n\n`);
        } catch {
          clearInterval(heartbeat);
          unsubscribe(code, controllerRef);
        }
      }, HEARTBEAT_INTERVAL_MS);
    },
    cancel() {
      clearInterval(heartbeat);
      unsubscribe(code, controllerRef);
    },
  });

  request.signal.addEventListener("abort", () => {
    clearInterval(heartbeat);
    unsubscribe(code, controllerRef);
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    },
  });
}

