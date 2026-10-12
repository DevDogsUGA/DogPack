/**
 * `enroll`: add courses to a term, the only way a row reaches
 * dogpack.enrollments.
 *
 * The database cannot call out, so this function does the part that needs the
 * network: it checks each course against the platform's catalog API (does it
 * exist, is it offered that term) and keeps dogpack.terms, the cache the
 * add/drop deadline rule reads, fresh. The deadline itself is enforced by the
 * database (private.enrollments_guard), whoever inserts.
 *
 * If the catalog API is down it falls back to the format check and stores the
 * row with catalogVerified = false. Removing a course needs no function: a
 * member deletes their own enrollment row.
 *
 * POST { term: 202608, courses: ["csci1301", "MATH 2250"] }   (1 to 12 courses)
 *   200 { term, dropAddEnds, results: [{ course, status }] }
 *   status: added | already_enrolled | unknown_course | not_offered |
 *           invalid_format | enrollment_closed | term_over | unknown_term |
 *           too_many_courses | account_restricted | error
 *   400 invalid_request   401 unauthorized
 */
import { z } from "zod";
import { authenticate } from "../_shared/auth.ts";
import {
  createCatalogClient,
  type CatalogClient,
  type CatalogTerm,
} from "../_shared/catalog.ts";
import { isTerm, normalizeCourse } from "../_shared/course.ts";
import { json, problem } from "../_shared/http.ts";

const requestSchema = z.object({
  term: z.number().refine(isTerm, "term must be YYYYMM with MM of 02, 05 or 08"),
  courses: z.array(z.string().min(1).max(20)).min(1).max(12),
});

/** The cache is refreshed when it lacks the term or is older than this. */
const CACHE_HOURS = 24;

export type Status =
  | "added"
  | "already_enrolled"
  | "unknown_course"
  | "not_offered"
  | "invalid_format"
  | "enrollment_closed"
  | "term_over"
  | "unknown_term"
  | "too_many_courses"
  | "account_restricted"
  | "error";

/** The message of a guard error (private.enrollments_guard) is its status. */
const GUARD_MESSAGES: ReadonlySet<string> = new Set([
  "enrollment_closed",
  "term_over",
  "unknown_term",
  "too_many_courses",
  "account_restricted",
]);

export function catalog(): CatalogClient {
  return createCatalogClient({
    baseUrl: Deno.env.get("CATALOG_URL") ?? undefined,
    client: "dogpack/backend",
  });
}

export async function handle(
  request: Request,
  catalogClient: CatalogClient = catalog(),
): Promise<Response> {
  if (request.method !== "POST") return new Response(null, { status: 405 });

  const caller = await authenticate(request);
  if (!caller) return problem(401, "unauthorized");

  const parsed = requestSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return problem(400, "invalid_request", parsed.error.issues.map((i) => i.message).join("; "));
  }
  const { term, courses } = parsed.data;
  const service = caller.asService.schema("dogpack");

  // 1. The term's dates, from the cache or, when it is cold or stale, the catalog.
  let known: { dropAddEnds: string | null; fetchedAt: string } | null = (
    await service.from("terms").select("dropAddEnds, fetchedAt").eq("term", term).maybeSingle()
  ).data;
  const stale =
    !known || Date.now() - Date.parse(known.fetchedAt) > CACHE_HOURS * 3600 * 1000;
  if (stale) {
    try {
      const terms: CatalogTerm[] = await catalogClient.terms();
      const rows = terms.map((t) => ({
        term: t.academicPeriod,
        description: t.description,
        classesBegin: t.classesBegin,
        classesEnd: t.classesEnd,
        dropAddEnds: t.dropAddEnds,
        fetchedAt: new Date().toISOString(),
      }));
      if (rows.length > 0) await service.from("terms").upsert(rows, { onConflict: "term" });
      const fresh = rows.find((r) => r.term === term);
      if (fresh) known = { dropAddEnds: fresh.dropAddEnds, fetchedAt: fresh.fetchedAt };
    } catch (error) {
      // Down or slow: go on with what the cache has (or nothing).
      console.warn("catalog terms unavailable, using the cache", String(error));
    }
  }

  // 2. Each course: format, then the catalog, then the insert.
  const results: { course: string; status: Status; catalogVerified?: boolean }[] = [];
  const seen = new Set<string>();
  for (const input of courses) {
    const course = normalizeCourse(input);
    if (!course) {
      results.push({ course: input, status: "invalid_format" });
      continue;
    }
    if (seen.has(course)) continue;
    seen.add(course);

    let catalogVerified = false;
    try {
      const answer = await catalogClient.courseExists(term, course);
      if (!answer.exists) {
        results.push({ course, status: "unknown_course" });
        continue;
      }
      if (answer.offered === false) {
        results.push({ course, status: "not_offered" });
        continue;
      }
      catalogVerified = true;
    } catch (error) {
      console.warn("catalog course-exists unavailable, format check only", course, String(error));
    }

    const { error } = await service
      .from("enrollments")
      .insert({ userId: caller.user.id, term, course, catalogVerified });
    if (!error) {
      results.push({ course, status: "added", catalogVerified });
    } else if (error.code === "23505") {
      results.push({ course, status: "already_enrolled" });
    } else if (GUARD_MESSAGES.has(error.message)) {
      results.push({ course, status: error.message as Status });
    } else {
      console.error("enrollment insert failed", course, error);
      results.push({ course, status: "error" });
    }
  }

  return json(200, { term, dropAddEnds: known?.dropAddEnds ?? null, results });
}
