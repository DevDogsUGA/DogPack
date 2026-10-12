/**
 * The platform's public catalog API (read-only, no credentials):
 * https://api.devdogsuga.org/catalog/v1, staging api-staging.devdogsuga.org.
 * DogPack never reads the catalog's database. If the API is down, the callers
 * fall back to the format check and say so (`catalogVerified: false`).
 */
import { catalogCode } from "./course.ts";

export interface CatalogTerm {
  academicPeriod: number;
  description: string;
  classesBegin: string | null;
  classesEnd: string | null;
  dropAddEnds: string | null;
}

export interface CourseExists {
  exists: boolean;
  offered: boolean | null;
}

export interface CatalogClient {
  terms(): Promise<CatalogTerm[]>;
  courseExists(term: number, course: string): Promise<CourseExists>;
}

export const DEFAULT_CATALOG_URL = "https://api.devdogsuga.org/catalog/v1";

export function createCatalogClient(options: {
  baseUrl?: string;
  fetch?: typeof fetch;
  timeoutMs?: number;
  client?: string;
}): CatalogClient {
  const base = (options.baseUrl ?? DEFAULT_CATALOG_URL).replace(/\/+$/, "");
  const doFetch = options.fetch ?? fetch;
  const timeout = options.timeoutMs ?? 4000;
  const headers = { "x-client": options.client ?? "dogpack/backend" };

  async function get(path: string): Promise<unknown> {
    const response = await doFetch(`${base}${path}`, {
      headers,
      signal: AbortSignal.timeout(timeout),
    });
    if (!response.ok) throw new Error(`catalog ${path} answered ${response.status}`);
    return await response.json();
  }

  return {
    async terms() {
      const body = (await get("/terms")) as { terms?: CatalogTerm[] };
      if (!Array.isArray(body.terms)) throw new Error("catalog /terms has no terms");
      return body.terms;
    },
    async courseExists(term, course) {
      const query = new URLSearchParams({ abbr: catalogCode(course), term: String(term) });
      const body = (await get(`/course-exists?${query}`)) as {
        exists?: unknown;
        offered?: unknown;
      };
      if (typeof body.exists !== "boolean") throw new Error("catalog /course-exists is malformed");
      return { exists: body.exists, offered: typeof body.offered === "boolean" ? body.offered : null };
    },
  };
}
