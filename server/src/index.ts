// Game server for the Mario & Luigi MMO.
//
// The Worker routes each WebSocket to the Durable Object for that map
// ("zone"). A zone relays movement between everyone standing in it. It uses
// the WebSocket Hibernation API, so an empty or quiet zone is not billed.
//
// Protocol (JSON text frames):
//   client -> server
//     {t:"hello", name, character, x, y}   first message after connecting
//     {t:"mv", x, y, vx, vy}               position + velocity, ~5 times a second while moving
//     {t:"jump"}
//   server -> client
//     {t:"welcome", id, players:[Player]}  everyone already in the zone
//     {t:"join", player:Player}
//     {t:"mv", id, x, y, vx, vy}
//     {t:"jump", id}
//     {t:"leave", id}
//     {t:"full"}                            zone is full; the socket is closed
//   Player = {id, name, character, x, y}
// The text "ping" is answered with "pong" without waking the zone.

import { DurableObject } from "cloudflare:workers";

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
  x: number;
  y: number;
}

// Kept on each socket with serializeAttachment so it survives hibernation.
interface Attachment {
  player: Player | null; // null until the client says hello
  windowStart: number;
  count: number;
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
      a.player = {
        id: crypto.randomUUID().slice(0, 8),
        name: cleanName(msg.name),
        character,
        x: coord(msg.x),
        y: coord(msg.y),
      };
      ws.serializeAttachment(a);
      ws.send(JSON.stringify({ t: "welcome", id: a.player.id, players: this.players(ws) }));
      this.broadcast({ t: "join", player: a.player }, ws);
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

  private broadcast(msg: object, skip: WebSocket): void {
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
