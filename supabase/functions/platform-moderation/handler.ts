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
 * retrying; only a database or admin API failure answers 5xx, which it retries with the
 * message intact, because apply_event records the id and the change together.
 */
import postgres from "npm:postgres@3.4.9";
import { parseMessage } from "../_shared/moderation/messages.ts";
import { verifyMessage } from "../_shared/moderation/signing.ts";
import { parseUserDelete } from "../_shared/user-delete.ts";
import { serviceClient } from "../_shared/auth.ts";
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

  const deletion = parseUserDelete(body);
  const message = deletion ?? parseMessage(body);
  if (!message) {
    // Signed but not a message this version understands (a newer schema, say).
    // Answer 2xx like every other non-application: a retry cannot fix it.
    return json(200, { status: "ignored", reason: "unsupported_message" });
  }

  try {
    const [row] = await database()`
      select moderation.apply_event(${verified.id}, ${body}::text::jsonb) as outcome`;
    const outcome = row.outcome as string;
    // user.delete: apply_event locked the account out and recorded the id; the
    // auth user is removed here, through the admin API, and DogPack's foreign
    // keys cascade the rest. It runs on 'duplicate' too, so a retry after a
    // failed admin call finishes the job. Deletion is final, so it runs
    // whatever the ordering outcome (even 'stale'). An unknown user, or one
    // already deleted, is a success.
    if (deletion) {
      await deleteLocalUser(deletion.data.userId);
    }
    return json(200, { status: 200, outcome });
  } catch (error) {
    console.error("platform-moderation failed", verified.id, error);
    return json(500, { status: 500, error: "apply_failed" });
  }
}

/**
 * Delete the DogPack auth user linked to a DevDogs identity, if there is one.
 * Their identity row is what links them, so once the user is gone a repeat
 * finds nothing and returns quietly.
 */
async function deleteLocalUser(platformUserId: string): Promise<void> {
  const rows = await database()`
    select i.user_id as id
      from auth.identities i
     where i.provider = 'custom:devdogsuga' and i.provider_id = ${platformUserId}`;
  for (const { id } of rows) {
    const { error } = await serviceClient().auth.admin.deleteUser(id as string);
    // Deleted between the lookup and the call: that is what we wanted.
    if (error && error.status !== 404 && error.code !== "user_not_found") throw error;
  }
}
