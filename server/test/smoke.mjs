// End-to-end check against a running server: `npm run dev`, then `npm test`.
// SERVER=wss://mario-luigi-mmo.<you>.workers.dev npm test checks a deployed one.
const base = process.env.SERVER ?? "ws://127.0.0.1:8787";
const zone = `smoke_${Date.now() % 100000}`;

function open(name, character, x, y, extra = {}, z = zone) {
  const ws = new WebSocket(`${base}/zone/${z}`);
  const inbox = [];
  const waiters = [];
  ws.onmessage = (e) => {
    const msg = e.data === "pong" ? { t: "pong" } : JSON.parse(e.data);
    const w = waiters.findIndex((f) => f.match(msg));
    if (w >= 0) waiters.splice(w, 1)[0].resolve(msg);
    else inbox.push(msg);
  };
  const next = (t) =>
    new Promise((resolve, reject) => {
      const i = inbox.findIndex((m) => m.t === t);
      if (i >= 0) return resolve(inbox.splice(i, 1)[0]);
      waiters.push({ match: (m) => m.t === t, resolve });
      setTimeout(() => reject(new Error(`${name}: no "${t}" message`)), 5000);
    });
  const ready = new Promise((resolve, reject) => {
    ws.onopen = () => {
      ws.send(JSON.stringify({ t: "hello", name, character, x, y, ...extra }));
      resolve();
    };
    ws.onerror = () => reject(new Error(`${name}: could not connect to ${base}`));
  });
  return { ws, next, ready, inbox, send: (m) => ws.send(typeof m === "string" ? m : JSON.stringify(m)) };
}

function check(ok, what) {
  if (!ok) throw new Error(`FAIL: ${what}`);
  console.log(`ok - ${what}`);
}

const a = open("Ann", "mario", 100, 200);
await a.ready;
const wa = await a.next("welcome");
check(wa.players.length === 0, "first player sees an empty zone");

const b = open("Bo<b>!", "bowser", 300, 400);
await b.ready;
const wb = await b.next("welcome");
check(wb.players.length === 1 && wb.players[0].name === "Ann", "second player sees the first");
const join = await a.next("join");
check(join.player.name === "Bob" && join.player.character === "bowser", "first player is told about the second, name cleaned");

a.send({ t: "mv", x: 120.6, y: 210, vx: 80, vy: 9999 });
const mv = await b.next("mv");
check(mv.id === wa.id && mv.x === 121 && mv.vy === 400, "movement is relayed, rounded and clamped");

b.send({ t: "jump" });
check((await a.next("jump")).id === wb.id, "jump is relayed");

a.send("ping");
check((await a.next("pong")).t === "pong", "ping gets pong");

const c = open("Cy", "rosalina", 0, 0);
await c.ready;
const wc = await c.next("welcome");
const ann = wc.players.find((p) => p.id === wa.id);
check(wc.players.length === 2 && ann.x === 121, "late joiner (a different character) sees everyone at their latest position");
check((await a.next("join")).player.character === "rosalina", "others see a character the server has never heard of");

const bad = open("Hax", "Not A Character!", 0, 0);
await bad.ready;
await new Promise((r) => (bad.ws.onclose = r));
check(true, "malformed character id is rejected");

a.send({ t: "chat", text: "  hello\u0007 shiiit world  " });
const heard = await c.next("chat");
const echo = await a.next("chat");
check(heard.text === "hello ****** world" && heard.name === "Ann", "chat reaches everyone, trimmed and filtered");
check(echo.id === wa.id, "sender gets their own chat back");
a.send({ t: "chat", text: "spam" });
a.send({ t: "chat", text: "x".repeat(200) });
await new Promise((r) => setTimeout(r, 300));
check(!c.inbox.some((m) => m.t === "chat"), "chat faster than once a second is dropped");
await new Promise((r) => setTimeout(r, 900));
a.send({ t: "chat", text: "x".repeat(200) });
check((await c.next("chat")).text.length === 80, "long chat is cut to 80 characters");

b.ws.close();
const leave = await a.next("leave");
check(leave.id === wb.id, "leaving is broadcast");

a.ws.close();
c.ws.close();

// --- Parties ---
const uidP = "aaaaaaaaaaa1", uidQ = "bbbbbbbbbbb2";
const p = open("Pat", "mario", 0, 0, { uid: uidP, side: "good" });
await p.ready;
check((await p.next("welcome")).id === uidP, "uid becomes the player id");
const q = open("Quinn", "luigi", 0, 0, { uid: uidQ });
await q.ready;
await q.next("welcome");
const r = open("Rex", "bowser", 0, 0, { uid: uidP, side: "evil" });
await r.ready;
const wr = await r.next("welcome");
check(wr.id !== uidP && /^[a-f0-9]{12}$/.test(wr.id), "a uid already in use gets a fresh id");
check(wr.players.find((x) => x.id === uidP).side === "good", "players carry their side");

q.send({ t: "accept", from: uidP });
p.send({ t: "invite", to: uidQ });
const inv = await q.next("invite");
check(inv.from === uidP && inv.name === "Pat", "invite reaches the invitee");
q.send({ t: "accept", from: uidP });
check((await p.next("party")).id === uidQ && (await q.next("party")).id === uidP, "accepting forms a party");

r.send({ t: "invite", to: uidQ });
await new Promise((res) => setTimeout(res, 300));
check(!q.inbox.some((m) => m.t === "invite"), "can't invite someone already in a party");

p.send({ t: "chat", text: "secret plan", party: true });
check((await q.next("chat")).party === true && (await p.next("chat")).text === "secret plan", "party chat reaches the partner");
await new Promise((res) => setTimeout(res, 300));
check(!r.inbox.some((m) => m.t === "chat"), "party chat doesn't reach others");

p.send({ t: "pmsg", d: { kind: "coop_start", foes: ["goomba"] } });
check((await q.next("pmsg")).d.kind === "coop_start", "party messages reach the partner");
r.send({ t: "pmsg", d: { kind: "sneaky" } });
await new Promise((res) => setTimeout(res, 300));
check(!p.inbox.some((m) => m.t === "pmsg") && !q.inbox.some((m) => m.t === "pmsg"), "party messages need a party");

p.send({ t: "warp", map: "outskirts", spawn: "south_path" });
const warp = await q.next("warp");
check(warp.map === "outskirts" && warp.spawn === "south_path", "warp is passed to the partner");

// Both move to another map: they find each other again by uid.
const zone2 = `${zone}_b`;
p.ws.close();
q.ws.close();
const p2 = open("Pat", "mario", 0, 0, { uid: uidP, party: uidQ }, zone2);
await p2.ready;
await p2.next("welcome");
const q2 = open("Quinn", "luigi", 0, 0, { uid: uidQ, party: uidP }, zone2);
await q2.ready;
await q2.next("welcome");
check((await p2.next("party")).id === uidQ && (await q2.next("party")).id === uidP, "partners find each other on a new map");

q2.send({ t: "leave_party" });
await p2.next("party_end");
check(true, "leaving the party tells the partner");

const p3 = open("Pat", "mario", 0, 0, { uid: "ccccccccccc3", party: uidQ }, zone2);
await p3.ready;
await p3.next("welcome");
await p3.next("party_end");
check(true, "arriving with a partner who left the party ends it");

r.send({ t: "invite", to: uidP });
await new Promise((res) => setTimeout(res, 200));
for (const x of [p2, q2, p3, r]) x.ws.close();

// Duels: an evil player attacks a good one outside town.
const zone3 = `${zone}_c`;
const ev = open("Bowsy", "bowser", 0, 0, { uid: "eeeeeeeeeee1", side: "evil" }, zone3);
await ev.ready;
await ev.next("welcome");
const gd = open("Goodie", "mario", 0, 0, { uid: "eeeeeeeeeee2", side: "good" }, zone3);
await gd.ready;
await gd.next("welcome");
const town = open("Townie", "luigi", 0, 0, { uid: "eeeeeeeeeee3", side: "good", safe: true }, zone3);
await town.ready;
await town.next("welcome");
const ev2 = open("Evie", "bowser", 0, 0, { uid: "eeeeeeeeeee4", side: "evil" }, zone3);
await ev2.ready;
await ev2.next("welcome");

ev.send({ t: "duel", to: "eeeeeeeeeee3", stats: { hp: 20 } });
check((await ev.next("duel_over")).result === "refused", "can't attack someone in a town");
gd.send({ t: "duel", to: "eeeeeeeeeee4", stats: { hp: 20 } });
check((await gd.next("duel_over")).result === "refused", "good players can't start duels");

ev.send({ t: "duel", to: "eeeeeeeeeee2", stats: { hp: 30, pow: 5, coins: 100, junk: 4 } });
const ch = await gd.next("challenge");
check(ch.from === "eeeeeeeeeee1" && ch.stats.hp === 30 && ch.stats.junk === undefined, "the good player is challenged with the attacker's stats");
ev2.send({ t: "duel", to: "eeeeeeeeeee2", stats: {} });
check((await ev2.next("duel_over")).result === "refused", "can't attack someone already in a duel");
gd.send({ t: "duel_ready", stats: { hp: 22, def: 1 } });
const s1 = await ev.next("duel_start");
const s2 = await gd.next("duel_start");
check(s1.first && !s2.first && s1.foe.stats.hp === 22 && s2.foe.name === "Bowsy", "both sides start the duel");

ev.send({ t: "duel_act", move: "jump", hits: [6, 7, 8, 9], rating: "Excellent", hp: 30 });
const act = await gd.next("duel_act");
check(act.move === "jump" && act.hits.length === 3 && act.rating === "Excellent", "moves are relayed to the foe");
gd.send({ t: "duel_hit", dmg: 12, hp: 10, dodged: false });
check((await ev.next("duel_hit")).hp === 10, "hit results go back to the attacker");

gd.send({ t: "duel_over", result: "lost" });
check((await ev.next("duel_over")).result === "lost", "the winner hears the loser lost");
ev.send({ t: "duel", to: "eeeeeeeeeee2", stats: {} });
check((await ev.next("duel_over")).result === "refused", "the loser can't be attacked again right away");

// Walking away mid-duel ends it.
const gd2 = open("Gwen", "peach", 0, 0, { uid: "eeeeeeeeeee5", side: "good" }, zone3);
await gd2.ready;
await gd2.next("welcome");
ev2.send({ t: "duel", to: "eeeeeeeeeee5", stats: {} });
await gd2.next("challenge");
gd2.send({ t: "duel_ready", stats: {} });
await ev2.next("duel_start");
gd2.ws.close();
check((await ev2.next("duel_over")).result === "left", "leaving mid-duel tells the foe");

ev.send({ t: "duel_act", move: "jump" });
for (const x of [ev, gd, town, ev2]) x.ws.close();

// Good and evil players can't team up, even with a modified client.
const zone4 = `${zone}_d`;
const hero = open("Hero", "mario", 0, 0, { uid: "fffffffff001", side: "good", key: "aaaaaaaaaaaaaaaa" }, zone4);
await hero.ready;
await hero.next("welcome");
const vil = open("Vil", "bowser", 0, 0, { uid: "fffffffff002", side: "evil" }, zone4);
await vil.ready;
await vil.next("welcome");
const pal = open("Pal", "luigi", 0, 0, { uid: "fffffffff003", side: "good" }, zone4);
await pal.ready;
await pal.next("welcome");
vil.send({ t: "invite", to: "fffffffff001" });
const nope = await vil.next("declined");
check(nope.reason === "side" && nope.name === "Hero", "an invite across sides is refused");
await new Promise((res) => setTimeout(res, 200));
check(!hero.inbox.some((m) => m.t === "invite"), "the other side never sees a cross-side invite");
hero.send({ t: "accept", from: "fffffffff002" });
await new Promise((res) => setTimeout(res, 200));
check(!hero.inbox.some((m) => m.t === "party") && !vil.inbox.some((m) => m.t === "party"), "accepting a cross-side invite that was never sent does nothing");
hero.send({ t: "invite", to: "fffffffff003" });
await pal.next("invite");
pal.send({ t: "accept", from: "fffffffff001" });
check((await hero.next("party")).id === "fffffffff003", "same-side players can still team up");
await pal.next("party");

// Hero switches to evil: arriving with the party claim doesn't relink, and the partner hears it's over.
hero.ws.close();
await pal.next("leave");
const hero2 = open("Hero", "bowser", 0, 0, { uid: "fffffffff001", side: "evil", party: "fffffffff003", key: "aaaaaaaaaaaaaaaa" }, zone4);
await hero2.ready;
await hero2.next("welcome");
await hero2.next("party_end");
await pal.next("party_end");
check(true, "switching sides breaks the party on both ends");

// The same save reconnecting (same uid and key) replaces the stale socket and keeps its id.
const hero3 = open("Hero", "bowser", 0, 0, { uid: "fffffffff001", side: "evil", key: "aaaaaaaaaaaaaaaa" }, zone4);
await hero3.ready;
check((await hero3.next("welcome")).id === "fffffffff001", "a reconnect with the save's key keeps the id");
check((await hero2.next("replaced")).t === "replaced", "the stale socket is told it was replaced");
check((await pal.next("leave")).id === "fffffffff001", "others drop the stale copy");
const fake = open("Fake", "bowser", 0, 0, { uid: "fffffffff001", side: "evil", key: "bbbbbbbbbbbbbbbb" }, zone4);
await fake.ready;
check((await fake.next("welcome")).id !== "fffffffff001", "a wrong key can't take over someone's id");

// Duel guard flag is relayed.
const g5 = open("Gil", "mario", 0, 0, { uid: "fffffffff005", side: "good" }, zone4);
await g5.ready;
await g5.next("welcome");
hero3.send({ t: "duel", to: "fffffffff005", stats: {} });
await g5.next("challenge");
g5.send({ t: "duel_ready", stats: {} });
await hero3.next("duel_start");
g5.send({ t: "duel_hit", dmg: 3, hp: 17, dodged: false, guard: true });
check((await hero3.next("duel_hit")).guard === true, "a guarded hit says so");
for (const x of [hero3, vil, pal, fake, g5]) x.ws.close();
console.log("all good");
process.exit(0);
