import "server-only";
import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

function encryptionKey() {
  const raw = process.env.PAYMENT_CREDENTIALS_ENCRYPTION_KEY;
  if (!raw) throw new Error("Payment credential encryption is not configured.");
  const key = Buffer.from(raw, "base64");
  if (key.length !== 32) throw new Error("PAYMENT_CREDENTIALS_ENCRYPTION_KEY must be a base64-encoded 32-byte key.");
  return key;
}

export function encryptCredentials(value: Record<string, string>) {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(value), "utf8"), cipher.final()]);
  return [iv, cipher.getAuthTag(), ciphertext].map((part) => part.toString("base64")).join(".");
}

export function decryptCredentials(payload: string): Record<string, string> {
  const [ivText, tagText, ciphertextText] = payload.split(".");
  if (!ivText || !tagText || !ciphertextText) throw new Error("Stored payment credentials have an invalid format.");
  const decipher = createDecipheriv("aes-256-gcm", encryptionKey(), Buffer.from(ivText, "base64"));
  decipher.setAuthTag(Buffer.from(tagText, "base64"));
  const plaintext = Buffer.concat([decipher.update(Buffer.from(ciphertextText, "base64")), decipher.final()]).toString("utf8");
  return JSON.parse(plaintext) as Record<string, string>;
}
