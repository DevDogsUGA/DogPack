/**
 * `report`: a member reports a session or a profile.
 *
 * The app calls this with the member's own session; this function vouches for
 * the report to the platform with DogPack's client secret (the member's
 * session never leaves DogPack). It reads the content AS the member, so row
 * level security decides what can be reported: content the member cannot see
 * does not exist. The platform queues it for moderators, who decide in the
 * console; the decision comes back through `platform-moderation`.
 *
 * POST { contentType: "session" | "profile", contentRef, reason, description? }
 *   201 { reportId, corroborated }
 *   400 invalid_request / cannot_report_self   401 unauthorized
 *   403 reporter_not_allowed (suspended)       404 not_found
 *   429 rate_limited
 *   502 platform_rejected / platform_unavailable   503 not_configured
 */
import { z } from "zod";
import {
  createModerationClient,
  ReportRejectedError,
} from "../_shared/moderation/client.ts";
import { reportReasonSchema } from "../_shared/moderation/messages.ts";
import { authenticate, platformUserId } from "../_shared/auth.ts";
import { json, problem } from "../_shared/http.ts";

const requestSchema = z
  .object({
    contentType: z.enum(["session", "profile"]),
    contentRef: z.uuid(),
    reason: reportReasonSchema,
    description: z.string().trim().max(1000).optional(),
  })
  .refine((r) => r.reason !== "other" || (r.description?.length ?? 0) > 0, {
    message: "describe what is wrong when the reason is 'other'",
    path: ["description"],
  });

interface Config {
  baseUrl: string;
  clientId: string;
  secret: string;
}

function config(): Config | null {
  const baseUrl = Deno.env.get("PLATFORM_API_URL") ?? "https://api.devdogsuga.org";
  const clientId = Deno.env.get("DEVDOGS_OAUTH_CLIENT_ID");
  const secret = Deno.env.get("PLATFORM_MODERATION_SECRET")?.split(",")[0]?.trim();
  return clientId && secret ? { baseUrl, clientId, secret } : null;
}

export async function handle(
  request: Request,
  doFetch: typeof fetch = fetch,
): Promise<Response> {
  if (request.method !== "POST") return new Response(null, { status: 405 });

  const caller = await authenticate(request);
  if (!caller) return problem(401, "unauthorized");

  const cfg = config();
  if (!cfg) return problem(503, "not_configured");

  const parsed = requestSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return problem(400, "invalid_request", parsed.error.issues.map((i) => i.message).join("; "));
  }
  const { contentType, contentRef, reason, description } = parsed.data;

  // What the member can see, and who wrote it.
  let authorId: string;
  let snapshot: string;
  if (contentType === "session") {
    const { data } = await caller.asMember
      .schema("dogpack")
      .from("sessions")
      .select("hostId, title, description, location, course, startsAt")
      .eq("id", contentRef)
      .maybeSingle();
    if (!data) return problem(404, "not_found");
    authorId = data.hostId;
    snapshot = [
      data.title,
      `${data.course} at ${data.location}, ${data.startsAt}`,
      data.description,
    ]
      .filter(Boolean)
      .join("\n");
  } else {
    const { data } = await caller.asMember
      .schema("dogpack")
      .from("profiles")
      .select("userId, displayName, classYear, major")
      .eq("userId", contentRef)
      .maybeSingle();
    if (!data) return problem(404, "not_found");
    authorId = data.userId;
    snapshot = `${data.displayName}, ${data.classYear}, ${data.major ?? "no major"}`;
  }
  if (authorId === caller.user.id) return problem(400, "cannot_report_self");

  const [reporterUserId, authorUserId] = await Promise.all([
    platformUserId(caller.asService, caller.user.id),
    platformUserId(caller.asService, authorId),
  ]);
  if (!reporterUserId || !authorUserId) {
    // Not signed in with DevDogs: the platform cannot know either of them.
    return problem(400, "invalid_request", "both members need a DevDogs sign-in");
  }

  const platform = createModerationClient({ ...cfg, fetch: doFetch });
  try {
    const result = await platform.fileReport({
      reporterUserId,
      authorUserId,
      contentType,
      contentRef,
      contentSnapshot: snapshot.slice(0, 5000),
      reason,
      ...(description ? { description } : {}),
    });
    return json(201, { reportId: result.reportId, corroborated: result.corroborated });
  } catch (error) {
    if (error instanceof ReportRejectedError) {
      if (error.status === 429) return problem(429, "rate_limited");
      if (error.code === "reporter_not_allowed") return problem(403, "reporter_not_allowed");
      // The platform refused it: a client or registration problem on our side,
      // not something the member can fix. Log the code; tell the app generically.
      console.error("platform refused the report", error.status, error.code, error.message);
      return problem(502, "platform_rejected");
    }
    console.error("platform report API unreachable", error);
    return problem(502, "platform_unavailable");
  }
}
