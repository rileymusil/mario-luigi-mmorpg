// Game server for the Mario & Luigi MMO.
//
// The Worker routes each WebSocket to the Durable Object for that map
// ("zone"). A zone relays movement between everyone standing in it. It uses
// the WebSocket Hibernation API, so an empty or quiet zone is not billed.
//
// Protocol (JSON text frames):
//   client -> server
//     {t:"hello", name, character, x, y, uid?, key?, side?, party?, safe?}
//                                          first message after connecting. uid keeps your
//                                          id the same across maps; key is a secret kept with
//                                          the save: a hello with the same uid and key replaces
//                                          a stale connection (e.g. after a dropped network);
//                                          party is your partner's uid;
//                                          safe: this map is a town (no PvP against you).
//     {t:"mv", x, y, vx, vy}               position + velocity, ~5 times a second while moving
//     {t:"jump"}
//     {t:"chat", text, party?}             at most one per CHAT_COOLDOWN_MS; party: partner only
//     {t:"invite", to} / {t:"accept", from} / {t:"decline", from} / {t:"leave_party"}
//                                          good and evil players can't team up: an invite
//                                          across sides is answered {t:"declined", reason:"side"}
//     {t:"warp", map, spawn}               tell your partner you took an exit
//     {t:"pmsg", d:{...}}                  anything for your partner on this map (co-op battles)
//     {t:"duel", to, stats}                evil player attacks a good player (not in a safe zone)
//     {t:"duel_ready", stats} / {t:"duel_busy"}   the attacked player's game answers
//     {t:"duel_act", move, hits?, rating?, hp?}   your move in a duel, relayed to your foe
//     {t:"duel_hit", dmg, hp, dodged, guard?}  how much your foe's move did to you
//     {t:"duel_over", result}              lost | fled | timeout | cancel: ends the duel
//   server -> client
//     {t:"welcome", id, players:[Player]}  everyone already in the zone
//     {t:"join", player:Player}
//     {t:"mv", id, x, y, vx, vy}
//     {t:"jump", id}
//     {t:"chat", id, name, text, party?}   sent to everyone (or the party), sender included
//     {t:"invite", from, name}             someone wants to team up with you
//     {t:"declined", name, reason?}        reason "side": they're on the other side
//     {t:"party", id, name}                you and `id` are a party (also on rejoining a map)
//     {t:"party_end"}                       your partner left the party
//     {t:"warp", map, spawn}               your partner took an exit
//     {t:"pmsg", d:{...}}                  from your partner
//     {t:"challenge", from, name, character, stats}  an evil player attacks you
//     {t:"duel_start", foe:Player+{stats}, first}  both sides, first = you move first
//     {t:"duel_act", ...} / {t:"duel_hit", ...}    your foe's move / its result
//     {t:"duel_over", result}              your foe ended the duel (or "left", "busy", "refused")
//     {t:"leave", id}
//     {t:"full"}                            zone is full; the socket is closed
//     {t:"replaced"}                        the same save connected again; this socket is closed
//   Player = {id, name, character, side, x, y}
// The text "ping" is answered with "pong" without waking the zone.

import { DurableObject } from "cloudflare:workers";
import { cleanChat } from "./filter";
import { Account, accountKey, MAX_SAVE_BYTES, NAME } from "./accounts";

export { Account };

export interface Env {
  ZONES: DurableObjectNamespace<Zone>;
  ACCOUNTS: DurableObjectNamespace<Account>;
}

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Max-Age": "86400",
};

function json(status: number, body: object): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...CORS } });
}

// Online saves, see accounts.ts.
async function account(op: string, request: Request, env: Env): Promise<Response> {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (request.method !== "POST") return json(405, { error: "method" });
  const text = await request.text();
  if (text.length > MAX_SAVE_BYTES + 1024) return json(413, { error: "save" });
  let body: Record<string, unknown>;
  try {
    body = JSON.parse(text);
  } catch {
    return json(400, { error: "json" });
  }
  if (typeof body !== "object" || body === null) return json(400, { error: "json" });
  const name = String(body.name ?? "").trim();
  if (!NAME.test(name)) return json(400, { error: "name" });
  body.name = name;
  const stub = env.ACCOUNTS.get(env.ACCOUNTS.idFromName(accountKey(name)));
  // (RPC typing can't follow the unknown-valued body, so name the shape here.)
  const reply = (await stub.handle(op, body)) as unknown as { status: number; body: object };
  return json(reply.status, reply.body);
}

const ZONE_NAME = /^[a-z0-9_]{1,32}$/;
// Character ids are checked for shape only, so new characters in the game
// don't need a server deploy.
const CHARACTER_ID = /^[a-z0-9_]{1,32}$/;
const MAX_PLAYERS_PER_ZONE = 50;
const MAX_MESSAGES_PER_SECOND = 30; // a co-op host streams its battle at ~10 a second
const MAX_MESSAGE_BYTES = 2048;
const MAX_COORD = 10000;
const MAX_SPEED = 400;
const MAX_CHAT_LENGTH = 80;
const CHAT_COOLDOWN_MS = 1000;
const UID = /^[a-f0-9]{12}$/;
const KEY = /^[a-f0-9]{16,64}$/;
const MAP_ID = /^[a-z0-9_]{1,32}$/;
const DUEL_MOVES = new Set(["jump", "special", "heal", "wait"]);
const DUEL_COOLDOWN_MS = 30000; // after a duel, neither player can be attacked for a while
const STAT_KEYS = ["hp", "max_hp", "sp", "max_sp", "pow", "def", "level", "coins"];

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const match = url.pathname.match(/^\/zone\/([^/]+)$/);
    if (match) {
      const zone = match[1];
      if (!ZONE_NAME.test(zone)) return new Response("bad zone name", { status: 400 });
      if (request.headers.get("Upgrade") !== "websocket") {
        return new Response("expected a WebSocket", { status: 426 });
      }
      return env.ZONES.get(env.ZONES.idFromName(zone)).fetch(request);
    }
    const acct = url.pathname.match(/^\/account\/(register|login|save|load)$/);
    if (acct) return account(acct[1], request, env);
    if (url.pathname === "/") return new Response("Mario & Luigi MMO server is running.\n");
    return new Response("not found", { status: 404 });
  },
} satisfies ExportedHandler<Env>;

interface Player {
  id: string;
  name: string;
  character: string;
  side: "good" | "evil";
  x: number;
  y: number;
}

// Kept on each socket with serializeAttachment so it survives hibernation.
interface Attachment {
  player: Player | null; // null until the client says hello
  windowStart: number;
  count: number;
  lastChat?: number;
  party?: string; // partner's id once both agree
  wantParty?: string; // partner uid claimed at hello, waiting for them to arrive
  invited?: string; // id of the player this one invited
  safe?: boolean; // on a town map, where nobody can attack this player
  duel?: string; // foe's id while challenging or fighting
  dueling?: boolean; // false while the challenge waits for an answer
  stats?: Record<string, number>;
  safeUntil?: number; // can't be attacked again before this time
  key?: string; // the save's secret, lets the same save replace a stale connection
}

export class Zone extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }

  async fetch(_request: Request): Promise<Response> {
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server);
    const attachment: Attachment = { player: null, windowStart: Date.now(), count: 0 };
    server.serializeAttachment(attachment);
    if (this.players().length >= MAX_PLAYERS_PER_ZONE) {
      server.send(JSON.stringify({ t: "full" }));
      server.close(1013, "zone full");
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws: WebSocket, raw: string | ArrayBuffer): Promise<void> {
    if (typeof raw !== "string" || raw.length > MAX_MESSAGE_BYTES) return;
    const a = ws.deserializeAttachment() as Attachment;

    // Simple flood guard: drop messages over the per-second budget.
    const now = Date.now();
    if (now - a.windowStart >= 1000) {
      a.windowStart = now;
      a.count = 0;
    }
    a.count++;
    if (a.count > MAX_MESSAGES_PER_SECOND) {
      ws.serializeAttachment(a);
      return;
    }

    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(raw);
    } catch {
      return;
    }
    if (typeof msg !== "object" || msg === null) return;

    if (msg.t === "hello" && a.player === null) {
      const character = String(msg.character);
      if (!CHARACTER_ID.test(character)) {
        ws.close(1008, "unknown character");
        return;
      }
      const uid = String(msg.uid ?? "");
      const key = KEY.test(String(msg.key ?? "")) ? String(msg.key) : undefined;
      let taken = UID.test(uid) ? this.socketFor(uid) : null;
      if (taken && key && (taken.deserializeAttachment() as Attachment).key === key) {
        // The same save again (a reconnect, or coming back to this map before
        // the old socket was noticed closing): drop the old one, keep the id.
        this.leave(taken);
        try {
          taken.send(JSON.stringify({ t: "replaced" }));
          taken.close(1000, "replaced");
        } catch {
          // already closed
        }
        taken = null;
      }
      const id = UID.test(uid) && !taken ? uid : crypto.randomUUID().replace(/-/g, "").slice(0, 12);
      a.key = key;
      a.player = {
        id,
        name: cleanName(msg.name),
        character,
        side: msg.side === "evil" ? "evil" : "good",
        x: coord(msg.x),
        y: coord(msg.y),
      };
      a.safe = msg.safe === true;
      const want = String(msg.party ?? "");
      if (UID.test(want) && want !== id) a.wantParty = want;
      ws.serializeAttachment(a);
      ws.send(JSON.stringify({ t: "welcome", id: a.player.id, players: this.players(ws) }));
      this.broadcast({ t: "join", player: a.player }, ws);
      this.rejoinParty(ws, a);
      return;
    }

    if (a.player === null) return;

    if (msg.t === "mv") {
      a.player.x = coord(msg.x);
      a.player.y = coord(msg.y);
      ws.serializeAttachment(a);
      this.broadcast(
        { t: "mv", id: a.player.id, x: a.player.x, y: a.player.y, vx: speed(msg.vx), vy: speed(msg.vy) },
        ws,
      );
    } else if (msg.t === "jump") {
      ws.serializeAttachment(a);
      this.broadcast({ t: "jump", id: a.player.id }, ws);
    } else if (msg.t === "chat") {
      const text = cleanChat(
        String(msg.text ?? "").replace(/[\u0000-\u001f\u007f]/g, "").trim().slice(0, MAX_CHAT_LENGTH),
      );
      if (text && now - (a.lastChat ?? 0) >= CHAT_COOLDOWN_MS) {
        a.lastChat = now;
        const out = { t: "chat", id: a.player.id, name: a.player.name, text };
        if (msg.party) {
          // Party chat reaches your partner only if they're on this map too.
          ws.send(JSON.stringify({ ...out, party: true }));
          const partner = a.party ? this.socketFor(a.party) : null;
          partner?.send(JSON.stringify({ ...out, party: true }));
        } else {
          this.broadcast(out, null);
        }
      }
      ws.serializeAttachment(a);
    } else if (msg.t === "invite") {
      const target = this.socketFor(String(msg.to));
      const t = target?.deserializeAttachment() as Attachment | undefined;
      if (target && t?.player && target !== ws && t.player.side !== a.player.side) {
        ws.serializeAttachment(a);
        ws.send(JSON.stringify({ t: "declined", name: t.player.name, reason: "side" }));
      } else if (target && t?.player && target !== ws && !a.party && !t.party) {
        a.invited = t.player.id;
        ws.serializeAttachment(a);
        target.send(JSON.stringify({ t: "invite", from: a.player.id, name: a.player.name }));
      } else {
        ws.serializeAttachment(a);
      }
    } else if (msg.t === "accept" || msg.t === "decline") {
      const inviter = this.socketFor(String(msg.from));
      const i = inviter?.deserializeAttachment() as Attachment | undefined;
      ws.serializeAttachment(a);
      if (!inviter || !i?.player || i.invited !== a.player.id) return;
      i.invited = undefined;
      const otherSide = i.player.side !== a.player.side;
      if (msg.t === "decline" || a.party || i.party || otherSide) {
        inviter.serializeAttachment(i);
        inviter.send(JSON.stringify({ t: "declined", name: a.player.name, ...(otherSide ? { reason: "side" } : {}) }));
        return;
      }
      this.link(ws, a, inviter, i);
    } else if (msg.t === "leave_party") {
      const partner = a.party ? this.socketFor(a.party) : null;
      a.party = undefined;
      a.wantParty = undefined;
      ws.serializeAttachment(a);
      if (partner) {
        const p = partner.deserializeAttachment() as Attachment;
        p.party = undefined;
        p.wantParty = undefined;
        partner.serializeAttachment(p);
        partner.send(JSON.stringify({ t: "party_end" }));
      }
    } else if (msg.t === "warp") {
      ws.serializeAttachment(a);
      const map = String(msg.map);
      const spawn = String(msg.spawn);
      const partner = a.party ? this.socketFor(a.party) : null;
      if (partner && MAP_ID.test(map) && MAP_ID.test(spawn)) {
        partner.send(JSON.stringify({ t: "warp", map, spawn }));
      }
    } else if (msg.t === "pmsg") {
      ws.serializeAttachment(a);
      const partner = a.party ? this.socketFor(a.party) : null;
      if (partner && typeof msg.d === "object" && msg.d !== null && !Array.isArray(msg.d)) {
        partner.send(JSON.stringify({ t: "pmsg", d: msg.d }));
      }
    } else if (msg.t === "duel") {
      const target = this.socketFor(String(msg.to));
      const t = target?.deserializeAttachment() as Attachment | undefined;
      const ok =
        target && t?.player && target !== ws &&
        a.player.side === "evil" && t.player.side === "good" && !t.safe &&
        !a.duel && !t.duel && a.party !== t.player.id && (t.safeUntil ?? 0) <= now;
      if (!ok || !target || !t?.player) {
        ws.serializeAttachment(a);
        ws.send(JSON.stringify({ t: "duel_over", result: "refused" }));
        return;
      }
      a.duel = t.player.id;
      a.dueling = false;
      a.stats = stats(msg.stats);
      t.duel = a.player.id;
      t.dueling = false;
      ws.serializeAttachment(a);
      target.serializeAttachment(t);
      target.send(JSON.stringify({
        t: "challenge", from: a.player.id, name: a.player.name, character: a.player.character, stats: a.stats,
      }));
    } else if (msg.t === "duel_ready" || msg.t === "duel_busy") {
      const foe = a.duel ? this.socketFor(a.duel) : null;
      const f = foe?.deserializeAttachment() as Attachment | undefined;
      if (!foe || !f?.player || a.dueling || f.duel !== a.player.id) {
        ws.serializeAttachment(a);
        return;
      }
      if (msg.t === "duel_busy") {
        a.duel = f.duel = undefined;
        ws.serializeAttachment(a);
        foe.serializeAttachment(f);
        foe.send(JSON.stringify({ t: "duel_over", result: "busy" }));
        return;
      }
      a.stats = stats(msg.stats);
      a.dueling = f.dueling = true;
      ws.serializeAttachment(a);
      foe.serializeAttachment(f);
      foe.send(JSON.stringify({ t: "duel_start", foe: { ...a.player, stats: a.stats }, first: true }));
      ws.send(JSON.stringify({ t: "duel_start", foe: { ...f.player, stats: f.stats }, first: false }));
    } else if (msg.t === "duel_act" || msg.t === "duel_hit") {
      ws.serializeAttachment(a);
      const foe = a.dueling && a.duel ? this.socketFor(a.duel) : null;
      if (!foe) return;
      const out: Record<string, unknown> =
        msg.t === "duel_act"
          ? {
              t: "duel_act",
              move: DUEL_MOVES.has(String(msg.move)) ? String(msg.move) : "wait",
              hits: Array.isArray(msg.hits) ? msg.hits.slice(0, 3).map((h) => num(h, 999)) : [],
              rating: ["Excellent", "Good", "Miss"].includes(String(msg.rating)) ? String(msg.rating) : "Miss",
              hp: num(msg.hp, 9999),
              name: String(msg.name ?? "").slice(0, 24),
            }
          : {
              t: "duel_hit", dmg: num(msg.dmg, 9999), hp: num(msg.hp, 9999), dodged: msg.dodged === true,
              guard: msg.guard === true,
            };
      foe.send(JSON.stringify(out));
    } else if (msg.t === "duel_over") {
      const result = ["lost", "fled", "timeout", "cancel"].includes(String(msg.result)) ? String(msg.result) : "cancel";
      this.endDuel(ws, a, result, now);
    } else {
      ws.serializeAttachment(a);
    }
  }

  // Ends the duel `a` is in and tells the foe how it ended.
  private endDuel(ws: WebSocket | null, a: Attachment, result: string, now: number): void {
    const foe = a.duel ? this.socketFor(a.duel) : null;
    const fought = a.dueling;
    a.duel = undefined;
    a.dueling = false;
    if (fought) a.safeUntil = now + DUEL_COOLDOWN_MS;
    ws?.serializeAttachment(a);
    if (!foe) return;
    const f = foe.deserializeAttachment() as Attachment;
    if (f.duel !== a.player?.id) return;
    f.duel = undefined;
    f.dueling = false;
    if (fought) f.safeUntil = now + DUEL_COOLDOWN_MS;
    foe.serializeAttachment(f);
    foe.send(JSON.stringify({ t: "duel_over", result }));
  }

  async webSocketClose(ws: WebSocket, code: number, _reason: string, _wasClean: boolean): Promise<void> {
    this.leave(ws);
    try {
      ws.close(code === 1005 ? 1000 : code, "bye");
    } catch {
      // already closed
    }
  }

  async webSocketError(ws: WebSocket, _error: unknown): Promise<void> {
    this.leave(ws);
  }

  private leave(ws: WebSocket): void {
    const a = ws.deserializeAttachment() as Attachment | null;
    if (!a?.player) return;
    const id = a.player.id;
    if (a.duel) this.endDuel(null, a, "left", Date.now());
    a.player = null;
    ws.serializeAttachment(a);
    this.broadcast({ t: "leave", id }, ws);
  }

  private socketFor(id: string): WebSocket | null {
    for (const ws of this.ctx.getWebSockets()) {
      const a = ws.deserializeAttachment() as Attachment | null;
      if (a?.player?.id === id) return ws;
    }
    return null;
  }

  private link(ws: WebSocket, a: Attachment, other: WebSocket, o: Attachment): void {
    a.party = o.player!.id;
    o.party = a.player!.id;
    a.wantParty = o.wantParty = undefined;
    a.invited = o.invited = undefined;
    ws.serializeAttachment(a);
    other.serializeAttachment(o);
    ws.send(JSON.stringify({ t: "party", id: o.player!.id, name: o.player!.name }));
    other.send(JSON.stringify({ t: "party", id: a.player!.id, name: a.player!.name }));
  }

  // A party member arriving on a map finds their partner again. If the
  // partner is here but no longer counts them as a partner, the party is over.
  private rejoinParty(ws: WebSocket, a: Attachment): void {
    if (!a.wantParty) return;
    const other = this.socketFor(a.wantParty);
    if (!other) return; // partner is elsewhere; they'll find us when they arrive
    const o = other.deserializeAttachment() as Attachment;
    const together = o.wantParty === a.player!.id || o.party === a.player!.id;
    if (together && o.player?.side === a.player!.side) {
      this.link(ws, a, other, o);
    } else {
      if (together) {
        // One of them switched sides since: good and evil can't be a party.
        o.party = o.wantParty = undefined;
        other.serializeAttachment(o);
        other.send(JSON.stringify({ t: "party_end" }));
      }
      a.wantParty = undefined;
      ws.serializeAttachment(a);
      ws.send(JSON.stringify({ t: "party_end" }));
    }
  }

  // Everyone in the zone who has said hello, except `skip`.
  private players(skip?: WebSocket): Player[] {
    const out: Player[] = [];
    for (const ws of this.ctx.getWebSockets()) {
      if (ws === skip) continue;
      const a = ws.deserializeAttachment() as Attachment | null;
      if (a?.player) out.push(a.player);
    }
    return out;
  }

  private broadcast(msg: object, skip: WebSocket | null): void {
    const text = JSON.stringify(msg);
    for (const ws of this.ctx.getWebSockets()) {
      if (ws === skip) continue;
      const a = ws.deserializeAttachment() as Attachment | null;
      if (!a?.player) continue;
      try {
        ws.send(text);
      } catch {
        // socket is closing; webSocketClose will clean it up
      }
    }
  }
}

function cleanName(value: unknown): string {
  const name = String(value ?? "").replace(/[^\p{L}\p{N} _.'-]/gu, "").trim().slice(0, 16);
  return name || "Player";
}

function coord(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) ? Math.round(Math.min(MAX_COORD, Math.max(0, n))) : 0;
}

function num(value: unknown, max: number): number {
  const n = Number(value);
  return Number.isFinite(n) ? Math.round(Math.min(max, Math.max(0, n))) : 0;
}

function stats(value: unknown): Record<string, number> {
  const out: Record<string, number> = {};
  const v = (typeof value === "object" && value !== null ? value : {}) as Record<string, unknown>;
  for (const key of STAT_KEYS) out[key] = num(v[key], 99999);
  return out;
}

function speed(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) ? Math.round(Math.min(MAX_SPEED, Math.max(-MAX_SPEED, n))) : 0;
}
