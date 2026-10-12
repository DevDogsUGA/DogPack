/**
 * `platform-moderation`: where the DevDogs platform delivers moderators'
 * decisions about DogPack content and members.
 *
 * Registered on the platform as the endpoint of DogPack's production OAuth
 * client (console > Apps Outside the Platform). The gateway's JWT check is off
 * (config.toml): the Standard Webhooks signature is the authentication.
 *
 * The three rules every receiver keeps, and where each one lives:
 *   1. signed        verified here against PLATFORM_MODERATION_SECRET; 401 else
 *   2. idempotent    moderation.apply_event (the webhook id is recorded)
 *   3. order-safe    moderation.apply_event (older than the last decision: stale)
 * Everything that is not an application still answers 2xx so the platform stops
 * retrying; only a database failure answers 5xx, which it retries with the
 * message intact, because apply_event records the id and the change together.
 */
import postgres from "npm:postgres@3.4.9";
import { parseMessage } from "../_shared/moderation/messages.ts";
import { verifyMessage } from "../_shared/moderation/signing.ts";
import { json } from "../_shared/http.ts";

/** One secret, or several (comma separated) while a rotation is in flight. */
function secrets(): string[] {
  return (Deno.env.get("PLATFORM_MODERATION_SECRET") ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

let sql: ReturnType<typeof postgres> | undefined;
function database() {
  const url = Deno.env.get("SUPABASE_DB_URL");
  if (!url) throw new Error("SUPABASE_DB_URL is not set");
  // `prepare: false` so it also works behind a transaction-mode pooler.
  sql ??= postgres(url, { max: 1, prepare: false, idle_timeout: 20 });
  return sql;
}

export async function handle(request: Request): Promise<Response> {
  if (request.method !== "POST") return new Response(null, { status: 405 });

  const keys = secrets();
  if (keys.length === 0) {
    console.error("PLATFORM_MODERATION_SECRET is not set");
    return json(503, { status: 503, error: "not_configured" });
  }

  const body = await request.text();
  const verified = await verifyMessage(keys, request.headers, body);
  if (!verified.ok) return json(401, { status: 401, error: verified.reason });

  const message = parseMessage(body);
  if (!message) return json(400, { status: 400, error: "invalid_body" });

  try {
    const [row] = await database()`
      select moderation.apply_event(${verified.id}, ${body}::text::jsonb) as outcome`;
    return json(200, { status: 200, outcome: row.outcome as string });
  } catch (error) {
    console.error("moderation.apply_event failed", verified.id, error);
    return json(500, { status: 500, error: "apply_failed" });
  }
}

