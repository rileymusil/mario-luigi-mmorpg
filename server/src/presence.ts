// Who is online and on which map, for whispers and friends lists. One
// Durable Object ("presence") keeps a row per connected player; zones add
// the row when someone says hello and remove it when they leave. A zone
// that gets the row wrong (a crash) only makes a whisper fail with
// "not online" or a friend show online a little too long.

import { DurableObject } from "cloudflare:workers";

export interface Seen {
  uid: string;
  name: string;
  zone: string;
}

export class Presence extends DurableObject {
  private sql: SqlStorage;

  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env as never);
    this.sql = ctx.storage.sql;
    this.sql.exec(
      "CREATE TABLE IF NOT EXISTS seen (uid TEXT PRIMARY KEY, name TEXT, name_lc TEXT, zone TEXT, at INTEGER)",
    );
    this.sql.exec("CREATE INDEX IF NOT EXISTS seen_name ON seen (name_lc)");
  }

  async arrive(uid: string, name: string, zone: string): Promise<void> {
    this.sql.exec(
      "INSERT OR REPLACE INTO seen (uid, name, name_lc, zone, at) VALUES (?, ?, ?, ?, ?)",
      uid, name, name.toLowerCase(), zone, Date.now(),
    );
  }

  // Only the zone the player is in removes them: on a map change the new
  // zone's hello can land before the old zone notices the close.
  async depart(uid: string, zone: string): Promise<void> {
    this.sql.exec("DELETE FROM seen WHERE uid = ? AND zone = ?", uid, zone);
  }

  // The most recent player online with this name (names aren't unique).
  async find(name: string): Promise<Seen | null> {
    const rows = this.sql
      .exec("SELECT uid, name, zone FROM seen WHERE name_lc = ? ORDER BY at DESC LIMIT 1", name.toLowerCase())
      .toArray();
    return rows.length ? (rows[0] as unknown as Seen) : null;
  }

  // name (lower case) -> map id, or null when they aren't online.
  async status(names: string[]): Promise<Record<string, string | null>> {
    const out: Record<string, string | null> = {};
    for (const n of names) {
      const seen = await this.find(n);
      out[n.toLowerCase()] = seen ? seen.zone : null;
    }
    return out;
  }
}
