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
console.log("all good");
process.exit(0);
