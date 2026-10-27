/**
 * The `user.delete` moderation message, accepted locally.
 *
 * The vendored `messages.ts` is pinned to a commit that predates it, and the
 * published @devdogsuga/sdk does not carry it yet (DevDogsUGA PR #215 adds it
 * to USER_MESSAGE_TYPES, the receiver and sdk-spec). Same wire shape as the
 * other user messages. Delete this file and use `parseMessage` once the vendored
 * copy is re-vendored from a commit that includes #215.
 */
import { z } from "zod";

export const userDeleteMessageSchema = z.object({
  type: z.literal("user.delete"),
  timestamp: z.iso.datetime(),
  data: z.object({
    userId: z.uuid(),
    reason: z.string().max(1000).nullable(),
    reportId: z.uuid().nullable(),
  }),
});
export type UserDeleteMessage = z.infer<typeof userDeleteMessageSchema>;

export function parseUserDelete(body: string): UserDeleteMessage | null {
  let json: unknown;
  try {
    json = JSON.parse(body);
  } catch {
    return null;
  }
  const parsed = userDeleteMessageSchema.safeParse(json);
  return parsed.success ? parsed.data : null;
}
