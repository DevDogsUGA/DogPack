import { assertEquals } from "jsr:@std/assert@^1.0.0";
import { catalogCode, isTerm, normalizeCourse } from "./course.ts";

Deno.test("normalizeCourse accepts the ways people type a course", () => {
  for (const input of ["CSCI 1301", "csci1301", "CSCI-1301", " csci  1301 ", "Csci\t1301"]) {
    assertEquals(normalizeCourse(input), "CSCI 1301", input);
  }
  assertEquals(normalizeCourse("chem 1211l"), "CHEM 1211L");
});

Deno.test("normalizeCourse rejects what is not a course code", () => {
  for (const input of ["", "CSCI", "1301", "CS 1301", "CSCI 130", "CSCI 13011", "CSCI 1301LL", "CSCI 13 01", "CSCI/1301", "CSCI 1301; drop table"]) {
    assertEquals(normalizeCourse(input), null, input);
  }
});

Deno.test("catalogCode drops the space", () => {
  assertEquals(catalogCode("CSCI 1301"), "CSCI1301");
});

Deno.test("isTerm is YYYYMM with Spring, Summer or Fall", () => {
  assertEquals([202602, 202605, 202608, 299908, 200002].every(isTerm), true);
  assertEquals([202601, 202609, 202612, 1, 20260, 3000000, 202608.5, "202608", null].some(isTerm), false);
});
