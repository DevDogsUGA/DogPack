/** A JSON response. Edge Functions here are called by the app and by the
 *  platform, never by a browser, so there is no CORS handling. */
export function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export function problem(status: number, code: string, message?: string): Response {
  return json(status, { error: { code, message: message ?? code } });
}

/** A required environment variable, or a thrown error naming it. */
export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not set`);
  return value;
}
