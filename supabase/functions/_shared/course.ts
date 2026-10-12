/**
 * Course codes. DogPack stores `CSCI 1301` (four letters, a space, four digits
 * and an optional letter); the catalog takes the code with or without the
 * space. A member types it however they like.
 */
const FORMAT = /^([A-Za-z]{4})[\s-]*([0-9]{4}[A-Za-z]?)$/;

/** `csci1301`, `CSCI-1301` and ` csci  1301 ` all become `CSCI 1301`. */
export function normalizeCourse(input: string): string | null {
  const match = FORMAT.exec(input.trim());
  return match ? `${match[1].toUpperCase()} ${match[2].toUpperCase()}` : null;
}

/** The catalog's spelling: `CSCI1301`. */
export function catalogCode(course: string): string {
  return course.replace(" ", "");
}

/** A term code is `YYYYMM` with `MM` of 02, 05 or 08. */
export function isTerm(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isInteger(value) &&
    value >= 200002 &&
    value <= 299908 &&
    [2, 5, 8].includes(value % 100)
  );
}
