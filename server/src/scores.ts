// The weekly good vs evil score: PvP wins for each side this week. One
// Durable Object ("scores") holds every week's count; a week runs Monday
// 00:00 UTC to the next Monday. Zones add wins; the game reads them with
//   GET /score -> {week, good, evil, ends_at}   (ends_at: ms since 1970)
//
// It also keeps the leaderboards: each player's level and boss wins (sent by
// their game when they join a map; saves live in the game, so these are
// trusted like the save is) and PvP wins (counted here when a duel ends).
//   GET /leaders -> {level: [Leader], pvp: [Leader], bosses: [Leader]}
//   Leader = {name, side, character, level, pvp, bosses}, best first, top 10

import { DurableObject } from "cloudflare:workers";

const DAY_MS = 86400000;

// Weeks since the Monday before 1970-01-01 (a Thursday).
export function weekOf(now: number): number {
  return Math.floor((Math.floor(now / DAY_MS) + 3) / 7);
}

export function weekEnds(week: number): number {
  return ((week + 1) * 7 - 3) * DAY_MS;
}

export interface Leader {
  name: string;
  side: string;
  character: string;
  level: number;
  pvp: number;
  bosses: number;
}

const TOP = 10;

export class Scores extends DurableObject {
  private sql: SqlStorage;

  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env as never);
    this.sql = ctx.storage.sql;
    this.sql.exec(
      "CREATE TABLE IF NOT EXISTS leaders (uid TEXT PRIMARY KEY, name TEXT, side TEXT, character TEXT, " +
        "level INTEGER DEFAULT 0, pvp INTEGER DEFAULT 0, bosses INTEGER DEFAULT 0, at INTEGER)",
    );
  }

  // A player joined a map: their name, look, level and boss wins.
  async report(uid: string, name: string, side: string, character: string, level: number, bosses: number): Promise<void> {
    this.sql.exec(
      "INSERT INTO leaders (uid, name, side, character, level, bosses, at) VALUES (?, ?, ?, ?, ?, ?, ?) " +
        "ON CONFLICT(uid) DO UPDATE SET name = excluded.name, side = excluded.side, character = excluded.character, " +
        "level = excluded.level, bosses = excluded.bosses, at = excluded.at",
      uid, name, side, character, level, bosses, Date.now(),
    );
  }

  async addPvpWin(uid: string, name: string, side: string, character: string): Promise<void> {
    this.sql.exec(
      "INSERT INTO leaders (uid, name, side, character, pvp, at) VALUES (?, ?, ?, ?, 1, ?) " +
        "ON CONFLICT(uid) DO UPDATE SET pvp = pvp + 1, name = excluded.name, at = excluded.at",
      uid, name, side, character, Date.now(),
    );
  }

  async leaders(): Promise<{ level: Leader[]; pvp: Leader[]; bosses: Leader[] }> {
    const top = (order: string, min: string) =>
      this.sql
        .exec(
          `SELECT name, side, character, level, pvp, bosses FROM leaders WHERE ${min} > 0 ORDER BY ${order} LIMIT ${TOP}`,
        )
        .toArray() as unknown as Leader[];
    return {
      level: top("level DESC, bosses DESC, at ASC", "level"),
      pvp: top("pvp DESC, level DESC, at ASC", "pvp"),
      bosses: top("bosses DESC, level DESC, at ASC", "bosses"),
    };
  }

  async addWin(side: "good" | "evil"): Promise<void> {
    const key = `${weekOf(Date.now())}:${side}`;
    const n = (await this.ctx.storage.get<number>(key)) ?? 0;
    await this.ctx.storage.put(key, n + 1);
  }

  async current(): Promise<{ week: number; good: number; evil: number; ends_at: number }> {
    const week = weekOf(Date.now());
    const got = await this.ctx.storage.get<number>([`${week}:good`, `${week}:evil`]);
    return {
      week,
      good: got.get(`${week}:good`) ?? 0,
      evil: got.get(`${week}:evil`) ?? 0,
      ends_at: weekEnds(week),
    };
  }
}
