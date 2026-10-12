import { assertEquals, assertRejects } from "jsr:@std/assert@^1.0.0";
import { createCatalogClient } from "./catalog.ts";

function client(handler: (url: URL, init?: RequestInit) => Response) {
  return createCatalogClient({
    baseUrl: "https://catalog.test/catalog/v1/",
    fetch: ((input: string | URL | Request, init?: RequestInit) =>
      Promise.resolve(handler(new URL(String(input)), init))) as typeof fetch,
  });
}

Deno.test("courseExists asks with the catalog's spelling and says who is calling", async () => {
  let seen: { url: URL; client: string | null } | undefined;
  const catalog = client((url, init) => {
    seen = { url, client: new Headers(init?.headers).get("x-client") };
    return Response.json({ abbr: "CSCI1301", term: 202608, exists: true, offered: false });
  });
  assertEquals(await catalog.courseExists(202608, "CSCI 1301"), { exists: true, offered: false });
  assertEquals(seen?.url.pathname, "/catalog/v1/course-exists");
  assertEquals(seen?.url.searchParams.get("abbr"), "CSCI1301");
  assertEquals(seen?.url.searchParams.get("term"), "202608");
  assertEquals(seen?.client, "dogpack/backend");
});

Deno.test("an unhappy catalog is an error the caller can fall back from", async () => {
  await assertRejects(() => client(() => new Response("down", { status: 503 })).courseExists(202608, "CSCI 1301"));
  await assertRejects(() => client(() => Response.json({ nope: true })).courseExists(202608, "CSCI 1301"));
  await assertRejects(() => client(() => Response.json({})).terms());
});

Deno.test("terms returns the list", async () => {
  const terms = [{ academicPeriod: 202608, description: "Fall 2026", classesBegin: "2026-08-12", classesEnd: "2026-12-02", dropAddEnds: "2026-08-18" }];
  assertEquals(await client(() => Response.json({ terms })).terms(), terms);
});
