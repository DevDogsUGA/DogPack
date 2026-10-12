/**
 * The Edge Functions against a running local stack (`supabase start` and
 * `supabase functions serve`), with the platform's APIs faked.
 *
 *   enroll             catalog checks, the cache, the add/drop deadline, the
 *                      catalog-down fallback
 *   report             vouches for a report to the platform, reads content as
 *                      the member
 *   platform-moderation  signed, idempotent, order-safe, and what a ban does
 *
 * Run by `.github/scripts/functions-check.sh`, which starts the stack and the
 * functions and passes the environment. See docs/guides/backend.md.
 */
import { assert, assertEquals, assertNotEquals } from "@std/assert";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { startFakePlatform } from "./fake_platform.ts";
import { buildAndSign } from "./sign.ts";

const need = (name: string): string => {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`${name} is not set (run .github/scripts/functions-check.sh)`);
  return v;
};
const API_URL = need("API_URL");
const SECRET_KEY = need("SECRET_KEY");
const PUBLISHABLE_KEY = need("PUBLISHABLE_KEY");
const DB_URL = need("DB_URL");
const SECRET = need("PLATFORM_MODERATION_SECRET");
const CLIENT_ID = need("DEVDOGS_OAUTH_CLIENT_ID");
const FAKE_PORT = Number(Deno.env.get("FAKE_PLATFORM_PORT") ?? "8799");
const FN = `${API_URL}/functions/v1`;

const options = { auth: { persistSession: false, autoRefreshToken: false } };
const admin = createClient(API_URL, SECRET_KEY, options);
const sql = postgres(DB_URL, { max: 2, prepare: false });
const platform = startFakePlatform({ port: FAKE_PORT, clientId: CLIENT_ID, secret: SECRET });

const run = crypto.randomUUID().slice(0, 8);

interface Member {
  id: string;
  platformId: string;
  client: SupabaseClient;
  token: string;
}

async function member(name: string): Promise<Member> {
  const email = `${name}-${run}@dogpack.devdogsuga.test`;
  const created = await admin.auth.admin.createUser({ email, email_confirm: true });
  if (created.error) throw created.error;
  const id = created.data.user.id;
  const platformId = crypto.randomUUID();
  // What GoTrue writes on a real sign-in. The timestamps matter: without them
  // GoTrue cannot load the user ("Database error finding user").
  await sql`insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at, last_sign_in_at)
            values (${platformId}, ${id}, ${sql.json({ sub: platformId, email })}, 'custom:devdogsuga', now(), now(), now())`;
  const link = await admin.auth.admin.generateLink({ type: "magiclink", email });
  if (link.error) throw link.error;
  const anon = createClient(API_URL, PUBLISHABLE_KEY, options);
  const verified = await anon.auth.verifyOtp({ token_hash: link.data.properties.hashed_token, type: "magiclink" });
  if (verified.error || !verified.data.session) throw verified.error ?? new Error("no session");
  const token = verified.data.session.access_token;
  const client = createClient(API_URL, PUBLISHABLE_KEY, { ...options, global: { headers: { Authorization: `Bearer ${token}` } } });
  return { id, platformId, client, token };
}

async function call(fn: string, token: string | null, body: unknown): Promise<{ status: number; json: any }> {
  const response = await fetch(`${FN}/${fn}`, {
    method: "POST",
    headers: { "content-type": "application/json", apikey: PUBLISHABLE_KEY, ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  });
  return { status: response.status, json: await response.json().catch(() => null) };
}

async function statusOf(response: Promise<Response>): Promise<number> {
  const r = await response;
  await r.body?.cancel();
  return r.status;
}

async function deliver(message: unknown, options: { id?: string; secret?: string } = {}) {
  const { headers, body } = await buildAndSign(options.secret ?? SECRET, message, options.id);
  const response = await fetch(`${FN}/platform-moderation`, { method: "POST", headers: { ...headers, "content-type": "application/json", apikey: PUBLISHABLE_KEY }, body });
  return { status: response.status, json: await response.json().catch(() => null) as any };
}

const alice = await member("alice");
const bob = await member("bob");
const cara = await member("cara");

const loose = { sanitizeOps: false, sanitizeResources: false, sanitizeExit: false };

Deno.test({ name: "enroll: the catalog decides, the cache fills, the deadline holds", ...loose, fn: async () => {
  assertEquals((await call("enroll", null, { term: 202808, courses: ["CSCI 1301"] })).status, 401);
  assertEquals((await call("enroll", bob.token, { term: 202808, courses: [] })).status, 400);
  assertEquals((await call("enroll", bob.token, { term: 202809, courses: ["CSCI 1301"] })).status, 400);

  // Bob is still onboarding: the first call fills the term cache from the catalog.
  const first = await call("enroll", bob.token, {
    term: 202808,
    courses: ["csci1301", "Math-2250", "hist1111", "nope", "CSCI 9999", "CSCI 1301"],
  });
  assertEquals(first.status, 200);
  const byCourse = Object.fromEntries(first.json.results.map((r: any) => [r.course, r.status]));
  assertEquals(byCourse, {
    "CSCI 1301": "added",
    "MATH 2250": "added",
    "HIST 1111": "not_offered",
    nope: "invalid_format",
    "CSCI 9999": "unknown_course",
  });
  assert(first.json.dropAddEnds, "the response carries the deadline");
  const cached = await sql`select count(*)::int as n from dogpack.terms where term in (202808, 202708)`;
  assertEquals(cached[0].n, 2);

  assertEquals((await call("enroll", bob.token, { term: 202808, courses: ["CSCI 1301"] })).json.results[0].status, "already_enrolled");

  const verified = await sql`select "catalogVerified" from dogpack.enrollments where "userId" = ${bob.id} and course = 'CSCI 1301'`;
  assertEquals(verified[0].catalogVerified, true);

  // Bob finishes onboarding; now the closed term refuses him, while the open one still takes courses.
  await bob.client.schema("dogpack").from("profiles").insert({ userId: bob.id, displayName: "Bob", classYear: "junior", major: "CS" });
  const done = await bob.client.schema("dogpack").rpc("complete_onboarding");
  assertEquals(done.error, null);
  const closed = await call("enroll", bob.token, { term: 202708, courses: ["ENGL 1101"] });
  assertEquals(closed.json.results[0].status, "enrollment_closed");
  const open = await call("enroll", bob.token, { term: 202808, courses: ["ENGL 1101"] });
  assertEquals(open.json.results[0].status, "added");

  // The catalog is down: format check only, and the row says so.
  platform.catalogDown = true;
  const fallback = await call("enroll", bob.token, { term: 202808, courses: ["BIOL 1107"] });
  platform.catalogDown = false;
  assertEquals(fallback.json.results[0], { course: "BIOL 1107", status: "added", catalogVerified: false });
  const stored = await sql`select "catalogVerified" from dogpack.enrollments where "userId" = ${bob.id} and course = 'BIOL 1107'`;
  assertEquals(stored[0].catalogVerified, false);
}});

Deno.test({ name: "report: a member reports a session they can see", ...loose, fn: async () => {
  // Alice onboards and hosts; Bob (enrolled in CSCI 1301 above) can see it.
  await call("enroll", alice.token, { term: 202808, courses: ["CSCI 1301"] });
  await alice.client.schema("dogpack").from("profiles").insert({ userId: alice.id, displayName: "Alice", classYear: "senior", major: "CS" });
  assertEquals((await alice.client.schema("dogpack").rpc("complete_onboarding")).error, null);
  const created = await alice.client.schema("dogpack").from("sessions").insert({
    term: 202808, course: "CSCI 1301", title: "Pointers, honestly", location: "MLC 3rd floor", description: "Bring snacks",
    startsAt: new Date(Date.now() + 86400000).toISOString(), endsAt: new Date(Date.now() + 90000000).toISOString(), capacity: 4,
  }).select("id").single();
  assertEquals(created.error, null);
  const sessionId = created.data!.id as string;

  const report = { contentType: "session", contentRef: sessionId, reason: "spam" };
  assertEquals((await call("report", null, report)).status, 401);
  assertEquals((await call("report", bob.token, { ...report, reason: "nonsense" })).status, 400);
  assertEquals((await call("report", bob.token, { ...report, reason: "other" })).status, 400); // 'other' needs a description
  assertEquals((await call("report", alice.token, report)).json.error.code, "cannot_report_self");
  assertEquals((await call("report", bob.token, { ...report, contentRef: crypto.randomUUID() })).status, 404);
  // Cara takes no CSCI course: the session does not exist for her.
  assertEquals((await call("report", cara.token, report)).status, 404);

  const ok = await call("report", bob.token, { ...report, reason: "harassment", description: "rude in the chat" });
  assertEquals(ok.status, 201);
  assertEquals(ok.json.corroborated, false);
  assert(typeof ok.json.reportId === "string");
  assertEquals(platform.reports.length, 1);
  const filed = platform.reports[0];
  assertEquals(filed.clientId, CLIENT_ID);
  assertEquals(filed.request.reporterUserId, bob.platformId);
  assertEquals(filed.request.authorUserId, alice.platformId);
  assertEquals(filed.request.contentType, "session");
  assertEquals(filed.request.contentRef, sessionId);
  assertEquals(filed.request.reason, "harassment");
  assertEquals(filed.request.description, "rude in the chat");
  assert(filed.request.contentSnapshot.includes("Pointers, honestly"));

  // The platform's limits reach the app as they are.
  platform.failNextReport = { status: 429, code: "rate_limited" };
  assertEquals((await call("report", bob.token, report)).status, 429);
  platform.failNextReport = { status: 403, code: "client_not_registered" };
  assertEquals((await call("report", bob.token, report)).json.error.code, "platform_rejected");
  platform.failNextReport = { status: 403, code: "reporter_not_allowed" };
  assertEquals((await call("report", bob.token, report)).status, 403);

  // A profile can be reported once the reporter shares a session with its owner.
  assertEquals((await call("report", bob.token, { contentType: "profile", contentRef: alice.id, reason: "impersonation" })).status, 201);
}});

Deno.test({ name: "platform-moderation: signed, idempotent, order-safe, and a hide really hides", ...loose, fn: async () => {
  const sessionRow = await sql`select id from dogpack.sessions where "hostId" = ${alice.id}`;
  const sessionId = sessionRow[0].id as string;
  const at = (offsetSeconds: number) => new Date(Date.now() + offsetSeconds * 1000).toISOString();
  const hide = { type: "content.hide", timestamp: at(0), data: { contentType: "session", contentRef: sessionId, reportId: null } };

  // Unsigned, mis-signed, expired.
  assertEquals(await statusOf(fetch(`${FN}/platform-moderation`, { method: "POST", body: JSON.stringify(hide), headers: { apikey: PUBLISHABLE_KEY } })), 401);
  assertEquals((await deliver(hide, { secret: "whsec_d3Jvbmctc2VjcmV0LXdyb25nLXNlY3JldC0wMDAwMDA=" })).status, 401);
  assertEquals(await statusOf(fetch(`${FN}/platform-moderation`, { method: "GET", headers: { apikey: PUBLISHABLE_KEY } })), 405);
  // Signed but not a moderation message.
  assertEquals((await deliver({ type: "content.explode" })).status, 400);

  const first = await deliver(hide, { id: `msg_hide_${run}` });
  assertEquals(first.json.outcome, "applied");
  assertEquals((await deliver(hide, { id: `msg_hide_${run}` })).json.outcome, "duplicate");
  const older = { ...hide, type: "content.restore", timestamp: at(-60) };
  assertEquals((await deliver(older, { id: `msg_old_${run}` })).json.outcome, "stale");

  // Hidden for Bob; still there for Alice, the author.
  const bobSees = await bob.client.schema("dogpack").from("sessions").select("id").eq("id", sessionId);
  assertEquals(bobSees.data!.length, 0);
  const aliceSees = await alice.client.schema("dogpack").from("sessions").select("id").eq("id", sessionId);
  assertEquals(aliceSees.data!.length, 1);
  // ...so Bob cannot report it any more either.
  assertEquals((await call("report", bob.token, { contentType: "session", contentRef: sessionId, reason: "spam" })).status, 404);

  const restore = { ...hide, type: "content.restore", timestamp: at(30) };
  assertEquals((await deliver(restore, { id: `msg_restore_${run}` })).json.outcome, "applied");
  assertEquals((await bob.client.schema("dogpack").from("sessions").select("id").eq("id", sessionId)).data!.length, 1);

  // A ban: Alice's sessions go, and so does her sign-in.
  const ban = { type: "user.ban", timestamp: at(60), data: { userId: alice.platformId, reason: "harassment", reportId: null } };
  assertEquals((await deliver(ban, { id: `msg_ban_${run}` })).json.outcome, "applied");
  const authed = await createClient(API_URL, PUBLISHABLE_KEY, options).auth.getUser(alice.token);
  assertNotEquals(authed.error, null, "the banned member's session no longer authenticates");
  assertEquals((await call("enroll", alice.token, { term: 202808, courses: ["MATH 2250"] })).status, 401);
  assertEquals((await bob.client.schema("dogpack").from("sessions").select("id").eq("id", sessionId)).data!.length, 0);
  const lift = { type: "user.restore", timestamp: at(90), data: { userId: alice.platformId, reason: null, reportId: null } };
  assertEquals((await deliver(lift, { id: `msg_lift_${run}` })).json.outcome, "applied");
  assertEquals((await bob.client.schema("dogpack").from("sessions").select("id").eq("id", sessionId)).data!.length, 1);
}});

Deno.test({ name: "cleanup", ...loose, fn: async () => {
  for (const m of [alice, bob, cara]) {
    await admin.auth.admin.deleteUser(m.id);
  }
  await sql`delete from moderation.events where id like ${"%" + run}`;
  await sql`delete from moderation.user_states where "platformUserId" in ${sql([alice.platformId, bob.platformId, cara.platformId])}`;
  await sql`delete from moderation.decisions where "itemKey" like 'content:session:%' or "itemKey" like ${"user:" + alice.platformId}`;
  await sql.end();
  await platform.close();
}});
