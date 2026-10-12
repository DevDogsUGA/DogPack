import { signMessage } from "../_shared/moderation/signing.ts";

/** A message signed the way the platform signs a delivery. */
export async function buildAndSign(secret: string, message: unknown, id?: string) {
  const body = JSON.stringify(message);
  const headers = await signMessage(secret, body, id ? { id } : {});
  return { headers, body };
}
