/**
 * A stand-in for the DevDogs platform's public APIs, so the Edge Functions can
 * be tested in CI with no network: the catalog (`/catalog/v1/terms`,
 * `/course-exists`) and the moderation report API (`/moderation/v1/reports`).
 * It checks the same things the real report API checks - the Standard Webhooks
 * signature, the client id header, the body schema - and records what it got.
 */
import { reportRequestSchema, type ReportRequest } from "../_shared/moderation/messages.ts";
import { verifyMessage } from "../_shared/moderation/signing.ts";

export interface FakePlatform {
  url: string;
  reports: { clientId: string; request: ReportRequest }[];
  /** Make /course-exists answer 503, as if the catalog were down. */
  catalogDown: boolean;
  /** Make the report API answer this status (and error code) once. */
  failNextReport: { status: number; code: string } | null;
  close(): Promise<void>;
}

const day = 24 * 3600 * 1000;
const iso = (offsetDays: number) => new Date(Date.now() + offsetDays * day).toISOString().slice(0, 10);

/** Terms: 202808 open (deadline ahead), 202708 closed (deadline passed, term running). */
export const FAKE_TERMS = [
  { academicPeriod: 202808, description: "Open term", classesBegin: iso(-5), classesEnd: iso(90), dropAddEnds: iso(5), partsOfTerm: [] },
  { academicPeriod: 202708, description: "Closed term", classesBegin: iso(-40), classesEnd: iso(60), dropAddEnds: iso(-30), partsOfTerm: [] },
];

const OFFERED = new Set(["CSCI1301", "MATH2250", "BIOL1107", "ENGL1101"]);
const EXISTS_NOT_OFFERED = new Set(["HIST1111"]);

export function startFakePlatform(options: { port: number; clientId: string; secret: string }): FakePlatform {
  const state: FakePlatform = {
    url: `http://127.0.0.1:${options.port}`,
    reports: [],
    catalogDown: false,
    failNextReport: null,
    close: async () => {
      await server.shutdown();
    },
  };

  const server = Deno.serve({ port: options.port, hostname: "0.0.0.0", onListen: () => {} }, async (request) => {
    const url = new URL(request.url);

    if (url.pathname === "/catalog/v1/terms") {
      return Response.json({ terms: FAKE_TERMS });
    }
    if (url.pathname === "/catalog/v1/course-exists") {
      if (state.catalogDown) return Response.json({ error: { code: "unavailable" } }, { status: 503 });
      const abbr = (url.searchParams.get("abbr") ?? "").replace(/[\s-]/g, "").toUpperCase();
      return Response.json({
        abbr,
        term: Number(url.searchParams.get("term")),
        exists: OFFERED.has(abbr) || EXISTS_NOT_OFFERED.has(abbr),
        offered: OFFERED.has(abbr),
      });
    }

    if (url.pathname === "/moderation/v1/reports" && request.method === "POST") {
      const body = await request.text();
      const verified = await verifyMessage(options.secret, request.headers, body);
      if (!verified.ok) return Response.json({ error: { code: "bad_signature", message: verified.reason } }, { status: 401 });
      const clientId = request.headers.get("moderation-client-id") ?? "";
      if (clientId !== options.clientId) return Response.json({ error: { code: "unknown_client", message: clientId } }, { status: 401 });
      const parsed = reportRequestSchema.safeParse(JSON.parse(body));
      if (!parsed.success) return Response.json({ error: { code: "invalid_request", message: parsed.error.message } }, { status: 400 });
      if (state.failNextReport) {
        const { status, code } = state.failNextReport;
        state.failNextReport = null;
        return Response.json({ error: { code, message: code } }, { status });
      }
      state.reports.push({ clientId, request: parsed.data });
      return Response.json({ reportId: crypto.randomUUID(), corroborated: false, sandbox: false }, { status: 201 });
    }

    return new Response("not found", { status: 404 });
  });

  return state;
}
