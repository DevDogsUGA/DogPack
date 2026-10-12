import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2";
import { requireEnv } from "./http.ts";

export interface Caller {
  user: User;
  /** Acts as the member: row level security applies. */
  asMember: SupabaseClient;
  /** Acts as the service role: bypasses row level security. */
  asService: SupabaseClient;
}

const options = { auth: { persistSession: false, autoRefreshToken: false } };

/** The service-role client. Never hand it a member's input unchecked. */
export function serviceClient(): SupabaseClient {
  return createClient(requireEnv("SUPABASE_URL"), requireEnv("SUPABASE_SERVICE_ROLE_KEY"), options);
}

/**
 * Verifies the member's session. The gateway's JWT check is off for these
 * functions (see supabase/config.toml), so this is the check: `getUser` asks
 * Auth whether the token is a live session, which also fails for a banned
 * member whose sessions were revoked.
 */
export async function authenticate(request: Request): Promise<Caller | null> {
  const header = request.headers.get("authorization") ?? "";
  const token = /^Bearer (.+)$/i.exec(header)?.[1];
  if (!token) return null;

  const asMember = createClient(requireEnv("SUPABASE_URL"), requireEnv("SUPABASE_ANON_KEY"), {
    ...options,
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data, error } = await asMember.auth.getUser(token);
  if (error || !data.user) return null;
  return { user: data.user, asMember, asService: serviceClient() };
}

/**
 * The DevDogs user id behind a DogPack user: the subject of their
 * custom:devdogsuga identity. It is what the platform knows a member by.
 */
export async function platformUserId(
  service: SupabaseClient,
  userId: string,
): Promise<string | null> {
  const { data, error } = await service.auth.admin.getUserById(userId);
  if (error || !data.user) return null;
  const identity = data.user.identities?.find((i) => i.provider === "custom:devdogsuga");
  if (!identity) return null;
  // The same value the database joins on (auth.identities.provider_id, which
  // GoTrue sets to the provider's subject). Never identity.id: that is the
  // identity row's own uuid and would match no suspension.
  const claims = identity.identity_data as { sub?: unknown } | undefined;
  const providerId = (identity as { provider_id?: unknown }).provider_id;
  const sub = typeof claims?.sub === "string" && claims.sub !== "" ? claims.sub : providerId;
  return typeof sub === "string" && sub !== "" ? sub : null;
}
