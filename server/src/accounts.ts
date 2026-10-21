// Online saves. Each username that has been saved online gets its own
// Durable Object ("account"), holding a password hash, the login tokens
// handed out for it and the latest copy of the save.
//
// HTTP API (JSON bodies, any origin may call it: there are no cookies, a
// token in the body is what lets a game write):
//   POST /account/register {name, password, save}  -> {token, name}
//        409 {error:"taken"} if someone already saved online with that name
//   POST /account/login    {name, password}        -> {token, name, save, saved_at}
//        403 {error:"wrong"} for a wrong name or password,
//        429 {error:"locked"} after too many wrong passwords in a row
//   POST /account/save     {name, token, save}     -> {ok:true, saved_at}
//   POST /account/load     {name, token}           -> {save, saved_at}
//        401 {error:"token"} for a token this account didn't hand out
// `save` is the game's save as a JSON object; saved_at is the save's own
// "saved_at" (seconds), so the game can tell which copy is newer.

import { DurableObject } from "cloudflare:workers";

export const NAME = /^[\p{L}\p{N} _.'-]{1,16}$/u;
const TOKEN = /^[a-f0-9]{32}$/;
const MIN_PASSWORD = 4;
const MAX_PASSWORD = 64;
export const MAX_SAVE_BYTES = 64 * 1024;
const MAX_TOKENS = 8; // devices logged in at once; the oldest is dropped
const ITERATIONS = 20000; // PBKDF2 rounds: slow enough to matter, fits the free plan's CPU budget
const MAX_FAILS = 8;
const LOCK_MS = 10 * 60 * 1000;

interface Stored {
  name: string; // as the player wrote it
  salt: string;
  hash: string;
  tokens: string[];
  save: string;
  savedAt: number;
  fails?: number;
  lockedUntil?: number;
}

type Reply = { status: number; body: Record<string, unknown> };

// Accounts are looked up by the username in lower case.
export function accountKey(name: string): string {
  return name.trim().toLowerCase();
}

export class Account extends DurableObject {
  async handle(op: string, body: Record<string, unknown>): Promise<Reply> {
    const acct = await this.ctx.storage.get<Stored>("acct");
    const now = Date.now();
    if (op === "register") {
      if (acct) return { status: 409, body: { error: "taken" } };
      const password = String(body.password ?? "");
      if (password.length < MIN_PASSWORD || password.length > MAX_PASSWORD) {
        return { status: 400, body: { error: "password" } };
      }
      const save = saveText(body.save);
      if (save === null) return { status: 400, body: { error: "save" } };
      const salt = hex(crypto.getRandomValues(new Uint8Array(16)));
      const token = newToken();
      const stored: Stored = {
        name: String(body.name),
        salt,
        hash: await hashPassword(password, salt),
        tokens: [token],
        save,
        savedAt: savedAt(save),
      };
      await this.ctx.storage.put("acct", stored);
      return { status: 200, body: { token, name: stored.name } };
    }
    if (op === "check") {
      return { status: 200, body: { available: !acct } };
    }
    if (op === "lookup") {
      if (!acct) return { status: 404, body: { error: "not_found" } };
      let saveObj: Record<string, unknown> = {};
      try {
        saveObj = JSON.parse(acct.save);
      } catch {}
      return {
        status: 200,
        body: {
          exists: true,
          name: acct.name,
          character: saveObj.character ?? "mario",
          level: saveObj.level ?? 1,
          side: saveObj.side ?? "good",
          coins: saveObj.coins ?? 0,
          saved_at: acct.savedAt,
        },
      };
    }
    if (!acct) {
      return op === "login" ? { status: 403, body: { error: "wrong" } } : { status: 401, body: { error: "token" } };
    }
    if (op === "login") {
      if ((acct.lockedUntil ?? 0) > now) return { status: 429, body: { error: "locked" } };
      const password = String(body.password ?? "").slice(0, MAX_PASSWORD);
      if ((await hashPassword(password, acct.salt)) !== acct.hash) {
        acct.fails = (acct.fails ?? 0) + 1;
        if (acct.fails >= MAX_FAILS) {
          acct.fails = 0;
          acct.lockedUntil = now + LOCK_MS;
        }
        await this.ctx.storage.put("acct", acct);
        return { status: 403, body: { error: "wrong" } };
      }
      const token = newToken();
      acct.tokens = [...acct.tokens, token].slice(-MAX_TOKENS);
      acct.fails = 0;
      acct.lockedUntil = undefined;
      await this.ctx.storage.put("acct", acct);
      return { status: 200, body: { token, name: acct.name, save: JSON.parse(acct.save), saved_at: acct.savedAt } };
    }
    const token = String(body.token ?? "");
    if (!TOKEN.test(token) || !acct.tokens.includes(token)) return { status: 401, body: { error: "token" } };
    if (op === "save") {
      const save = saveText(body.save);
      if (save === null) return { status: 400, body: { error: "save" } };
      acct.save = save;
      acct.savedAt = savedAt(save);
      await this.ctx.storage.put("acct", acct);
      return { status: 200, body: { ok: true, saved_at: acct.savedAt } };
    }
    if (op === "load") {
      return { status: 200, body: { save: JSON.parse(acct.save), saved_at: acct.savedAt } };
    }
    return { status: 404, body: { error: "op" } };
  }
}

// The save as text, or null if it isn't a JSON object or is too big.
function saveText(value: unknown): string | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  const text = JSON.stringify(value);
  return text.length > MAX_SAVE_BYTES ? null : text;
}

function savedAt(save: string): number {
  const n = Number((JSON.parse(save) as Record<string, unknown>).saved_at);
  return Number.isFinite(n) ? n : 0;
}

function newToken(): string {
  return hex(crypto.getRandomValues(new Uint8Array(16)));
}

function hex(bytes: Uint8Array): string {
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function hashPassword(password: string, salt: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, [
    "deriveBits",
  ]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt: new TextEncoder().encode(salt), iterations: ITERATIONS },
    key,
    256,
  );
  return hex(new Uint8Array(bits));
}
