// The weekly good vs evil score: PvP wins for each side this week. One
// Durable Object ("scores") holds every week's count; a week runs Monday
// 00:00 UTC to the next Monday. Zones add wins; the game reads them with
//   GET /score -> {week, good, evil, ends_at}   (ends_at: ms since 1970)

import { DurableObject } from "cloudflare:workers";

const DAY_MS = 86400000;

// Weeks since the Monday before 1970-01-01 (a Thursday).
export function weekOf(now: number): number {
  return Math.floor((Math.floor(now / DAY_MS) + 3) / 7);
}

export function weekEnds(week: number): number {
  return ((week + 1) * 7 - 3) * DAY_MS;
}

export class Scores extends DurableObject {
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
