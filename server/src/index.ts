// Game server for the Mario & Luigi MMO.
//
// The Worker routes each WebSocket to the Durable Object for that map
// ("zone"). A zone relays movement between everyone standing in it. It uses
// the WebSocket Hibernation API, so an empty or quiet zone is not billed.
//
// Protocol (JSON text frames):
//   client -> server
//     {t:"hello", name, character, x, y, uid?, side?, party?}
//                                          first message after connecting. uid keeps your
//                                          id the same across maps; party is your partner's uid.
//     {t:"mv", x, y, vx, vy}               position + velocity, ~5 times a second while moving
//     {t:"jump"}
//     {t:"chat", text, party?}             at most one per CHAT_COOLDOWN_MS; party: partner only
//     {t:"invite", to} / {t:"accept", from} / {t:"decline", from} / {t:"leave_party"}
//     {t:"warp", map, spawn}               tell your partner you took an exit
//   server -> client
//     {t:"welcome", id, players:[Player]}  everyone already in the zone
//     {t:"join", player:Player}
//     {t:"mv", id, x, y, vx, vy}
//     {t:"jump", id}
//     {t:"chat", id, name, text, party?}   sent to everyone (or the party), sender included
//     {t:"invite", from, name}             someone wants to team up with you
//     {t:"declined", name}
//     {t:"party", id, name}                you and `id` are a party (also on rejoining a map)
//     {t:"party_end"}                       your partner left the party
//     {t:"warp", map, spawn}               your partner took an exit
//     {t:"leave", id}
//     {t:"full"}                            zone is full; the socket is closed
//   Player = {id, name, character, side, x, y}
// The text "ping" is answered with "pong" without waking the zone.

import { DurableObject } from "cloudflare:workers";
import { cleanChat } from "./filter";

export interface Env {
  ZONES: DurableObjectNamespace<Zone>;
}

const ZONE_NAME = /^[a-z0-9_]{1,32}$/;
// Character ids are checked for shape only, so new characters in the game
// don't need a server deploy.
const CHARACTER_ID = /^[a-z0-9_]{1,32}$/;
const MAX_PLAYERS_PER_ZONE = 50;
const MAX_MESSAGES_PER_SECOND = 15;
const MAX_MESSAGE_BYTES = 512;
const MAX_COORD = 10000;
const MAX_SPEED = 400;
const MAX_CHAT_LENGTH = 80;
const CHAT_COOLDOWN_MS = 1000;
const UID = /^[a-f0-9]{12}$/;
const MAP_ID = /^[a-z0-9_]{1,32}$/;

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
      const id = UID.test(uid) && !this.socketFor(uid) ? uid : crypto.randomUUID().replace(/-/g, "").slice(0, 12);
      a.player = {
        id,
        name: cleanName(msg.name),
        character,
        side: msg.side === "evil" ? "evil" : "good",
        x: coord(msg.x),
        y: coord(msg.y),
      };
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
      if (target && t?.player && target !== ws && !a.party && !t.party) {
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
      if (msg.t === "decline" || a.party || i.party) {
        inviter.serializeAttachment(i);
        inviter.send(JSON.stringify({ t: "declined", name: a.player.name }));
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
    } else {
      ws.serializeAttachment(a);
    }
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
    if (o.wantParty === a.player!.id || o.party === a.player!.id) {
      this.link(ws, a, other, o);
    } else {
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

function speed(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) ? Math.round(Math.min(MAX_SPEED, Math.max(-MAX_SPEED, n))) : 0;
}
