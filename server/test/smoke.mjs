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

ev.send({ t: "duel", to: "eeeeeeeeeee3" });
check((await ev.next("duel_over")).result === "refused", "can't attack someone in a town");
gd.send({ t: "duel", to: "eeeeeeeeeee4" });
check((await gd.next("duel_over")).result === "refused", "good players can't start duels");

ev.send({ t: "duel", to: "eeeeeeeeeee2" });
const ch = await gd.next("challenge");
check(ch.from === "eeeeeeeeeee1" && ch.name === "Bowsy" && !ch.ally, "the good player is challenged");
ev2.send({ t: "duel", to: "eeeeeeeeeee2" });
check((await ev2.next("duel_over")).result === "refused", "can't attack someone already in a duel");
gd.send({ t: "duel_ready" });
const s1 = await ev.next("duel_start");
const s2 = await gd.next("duel_start");
check(s1.host === "eeeeeeeeeee1" && s2.host === "eeeeeeeeeee1" && s1.players.length === 2, "both sides start the duel");

ev.send({ t: "duel_msg", d: { k: "round", n: 1 } });
const dm = await gd.next("duel_msg");
check(dm.from === "eeeeeeeeeee1" && dm.d.k === "round", "the attacker's game runs the duel through duel_msg");
gd.send({ t: "duel_msg", d: { k: "plan" }, to_host: true });
check((await ev.next("duel_msg")).d.k === "plan", "secret picks go to the attacker's game");
gd.send({ t: "duel_end", winner: "good" });
await new Promise((r) => setTimeout(r, 200));
check(!ev.inbox.some((m) => m.t === "duel_over"), "only the attacker's game can end the duel");

const scoreUrl = `${base.replace(/^ws/, "http")}/score`;
const before = await (await fetch(scoreUrl)).json();
check(Number.isInteger(before.good) && Number.isInteger(before.evil) && before.ends_at > Date.now(), "the weekly score can be read");
ev.send({ t: "duel_end", winner: "evil" });
await new Promise((r) => setTimeout(r, 300));
ev.send({ t: "duel", to: "eeeeeeeeeee2" });
check((await ev.next("duel_over")).result === "refused", "the loser can't be attacked again right away");

// Walking away mid-duel: the others hear it, and it's a loss if that side loses.
const gd2 = open("Gwen", "peach", 0, 0, { uid: "eeeeeeeeeee5", side: "good" }, zone3);
await gd2.ready;
await gd2.next("welcome");
ev2.send({ t: "duel", to: "eeeeeeeeeee5" });
await gd2.next("challenge");
gd2.send({ t: "duel_ready" });
await ev2.next("duel_start");
gd2.ws.close();
const gone = await ev2.next("duel_left");
check(gone.id === "eeeeeeeeeee5" && gone.fled === false, "leaving mid-duel tells the others");
ev2.send({ t: "duel_end", winner: "evil" });
await new Promise((r) => setTimeout(r, 500));
const after = await (await fetch(scoreUrl)).json();
check(after.week !== before.week || after.evil >= before.evil + 2, "a win and a walk-out each count a win for evil");
for (const x of [ev, gd, town, ev2]) x.ws.close();

// Party vs party: both players' partners on the map join in.
const zp = `${zone}_pp`;
const pe1 = open("Ev One", "bowser", 0, 0, { uid: "cccccccccc01", side: "evil" }, zp);
const pe2 = open("Ev Two", "bowser", 0, 0, { uid: "cccccccccc02", side: "evil" }, zp);
const pg1 = open("Gd One", "mario", 0, 0, { uid: "cccccccccc03", side: "good" }, zp);
const pg2 = open("Gd Two", "luigi", 0, 0, { uid: "cccccccccc04", side: "good" }, zp);
for (const x of [pe1, pe2, pg1, pg2]) {
  await x.ready;
  await x.next("welcome");
}
pe1.send({ t: "invite", to: "cccccccccc02" });
await pe2.next("invite");
pe2.send({ t: "accept", from: "cccccccccc01" });
await pe1.next("party");
pg1.send({ t: "invite", to: "cccccccccc04" });
await pg2.next("invite");
pg2.send({ t: "accept", from: "cccccccccc03" });
await pg1.next("party");
pe1.send({ t: "duel", to: "cccccccccc03" });
const c1 = await pg1.next("challenge");
const c2 = await pg2.next("challenge");
const c3 = await pe2.next("challenge");
check(!c1.ally && !c2.ally && c3.ally === true, "both parties are called into the duel");
for (const x of [pg1, pg2]) x.send({ t: "duel_ready" });
await new Promise((r) => setTimeout(r, 200));
check(!pe1.inbox.some((m) => m.t === "duel_start"), "the duel waits for everyone to answer");
pe2.send({ t: "duel_ready" });
const ps = await Promise.all([pe1, pe2, pg1, pg2].map((x) => x.next("duel_start")));
check(ps.every((m) => m.players.length === 4 && m.host === "cccccccccc01"), "two against two");
pe1.ws.close();
const hl = await pg1.next("duel_over");
check(hl.result === "host_left" && hl.winner === "", "the attacker leaving calls it off while a teammate is still in");
await pe2.next("duel_over");
for (const x of [pe2, pg1, pg2]) x.ws.close();

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

for (const x of [hero3, vil, pal, fake]) x.ws.close();

// --- Online Trading ---
const zoneTrade = `${zone}_trade`;
const traderA = open("TraderA", "mario", 0, 0, { uid: "eeeeeeeee001", side: "good" }, zoneTrade);
await traderA.ready;
await traderA.next("welcome");
const traderB = open("TraderB", "luigi", 0, 0, { uid: "eeeeeeeee002", side: "good" }, zoneTrade);
await traderB.ready;
await traderB.next("welcome");

// A sends trade request to B
traderA.send({ t: "trade_req", to: "eeeeeeeee002" });
const req = await traderB.next("trade_req");
check(req.from === "eeeeeeeee001" && req.name === "TraderA", "trade request reaches recipient");

// B accepts
traderB.send({ t: "trade_reply", from: "eeeeeeeee001", accept: true });
const startA = await traderA.next("trade_start");
const startB = await traderB.next("trade_start");
check(startA.peer_id === "eeeeeeeee002" && startB.peer_id === "eeeeeeeee001", "both players enter trade session");

// A offers coins, items, and partner
const partnerA = { id: "goombario", name: "Goombario", kind: "partner", hp: 10, max_hp: 10, sp: 0, max_sp: 0, pow: 1, def: 0 };
traderA.send({ t: "trade_offer", offer: { coins: 50, items: { mushroom: 2 }, partner: partnerA } });
const offerToB = await traderB.next("trade_offer");
check(offerToB.offer.coins === 50 && offerToB.offer.items.mushroom === 2 && offerToB.offer.partner.id === "goombario", "A's offer (coins, items, partner) arrives at B");

// B offers items
traderB.send({ t: "trade_offer", offer: { coins: 10, items: { syrup: 1 }, partner: null } });
const offerToA = await traderA.next("trade_offer");
check(offerToA.offer.coins === 10 && offerToA.offer.items.syrup === 1, "B's offer arrives at A");

// A confirms
traderA.send({ t: "trade_confirm" });
const confirmedForB = await traderB.next("trade_confirmed");
check(confirmedForB.by === "eeeeeeeee001", "B is notified that A confirmed offer");

// B confirms, finalizing trade
traderB.send({ t: "trade_confirm" });
const doneA = await traderA.next("trade_done");
const doneB = await traderB.next("trade_done");
check(doneA.your_give.coins === 50 && doneA.your_receive.coins === 10, "A receives B's coins and gives own");
check(doneB.your_give.coins === 10 && doneB.your_receive.coins === 50, "B receives A's coins and gives own");
check(doneB.your_receive.partner.id === "goombario", "B receives A's partner");

// A asks again, then gives up before B answers: B's late "accept" is told it expired.
traderA.send({ t: "trade_req", to: "eeeeeeeee002" });
await traderB.next("trade_req");
traderA.send({ t: "trade_cancel" });
await traderB.next("trade_cancelled");
traderB.send({ t: "trade_reply", from: "eeeeeeeee001", accept: true });
const expired = await traderB.next("trade_cancelled");
check(expired.reason === "expired", "accepting a withdrawn trade request says it expired");

for (const x of [traderA, traderB]) x.ws.close();


// Whispers and friends: across maps, by name.
const tag = Date.now() % 100000;
const wn = `Wendy${tag}`, xn = `Xavi${tag}`;
const w1 = open(wn, "peach", 0, 0, { uid: "ccccccccccc1", level: 7, bosses: 3 }, `${zone}_w1`);
await w1.ready;
await w1.next("welcome");
const x1 = open(xn, "bowser", 0, 0, { uid: "ccccccccccc2", side: "evil", level: 12 }, `${zone}_w2`);
await x1.ready;
await x1.next("welcome");
await new Promise((res) => setTimeout(res, 200));
w1.send({ t: "whisper", to: xn.toLowerCase(), text: "psst over here" });
const wIn = await x1.next("whisper");
const wOut = await w1.next("whisper");
check(wIn.from === wn && wIn.text === "psst over here", "a whisper reaches a player on another map");
check(wOut.sent === true && wOut.to === xn, "the sender is told it got there, with their name as they spell it");
await new Promise((res) => setTimeout(res, 1100));
w1.send({ t: "whisper", to: "Nobody Here", text: "hello?" });
check((await w1.next("whisper_fail")).to === "Nobody Here", "whispering someone offline fails");
w1.send({ t: "friends", names: [xn, "Nobody Here"] });
const fr = await w1.next("friends");
check(fr.online[xn.toLowerCase()] === `${zone}_w2` && fr.online["nobody here"] === null, "friends list shows who's online and where");
x1.ws.close();
await new Promise((res) => setTimeout(res, 500));
w1.send({ t: "friends", names: [xn] });
check((await w1.next("friends")).online[xn.toLowerCase()] === null, "a friend who left shows offline");
w1.ws.close();

// Leaderboards.
const lb = await (await fetch(`${base.replace(/^ws/, "http")}/leaders`)).json();
check(lb.level.some((l) => l.name === xn && l.level === 12) && lb.bosses.some((l) => l.name === wn && l.bosses === 3),
  "leaderboards list players by level and boss wins");
check(Array.isArray(lb.pvp) && lb.level.length <= 10, "leaderboards keep the top 10");
// A second save with the same name (another uid, other letter case) is the same entry.
const w2 = open(wn.toUpperCase(), "luigi", 0, 0, { uid: "ccccccccccc3", level: 9, bosses: 1 }, `${zone}_w1`);
await w2.ready;
await w2.next("welcome");
await new Promise((res) => setTimeout(res, 300));
w2.ws.close();
const lb2 = await (await fetch(`${base.replace(/^ws/, "http")}/leaders`)).json();
const mine = lb2.level.filter((l) => l.name.toLowerCase() === wn.toLowerCase());
check(mine.length === 1 && mine[0].level === 9 && lb2.bosses.find((l) => l.name.toLowerCase() === wn.toLowerCase()).bosses === 3,
  "one leaderboard entry per username, with its best level and boss wins");

// Bounties: a strong good hero has one; so does an evil player on a winning streak.
const bz = `${zone}_bounty`;
const hunter = `Hunter${tag}`, braveName = `Brave${tag}`;
const bh = open(hunter, "bowser", 0, 0, { uid: "ddddddddddd1", side: "evil", level: 5 }, bz);
const bg1 = open(braveName, "mario", 0, 0, { uid: "ddddddddddd2", side: "good", level: 20 }, bz);
const bg2 = open(`Second${tag}`, "luigi", 0, 0, { uid: "ddddddddddd3", side: "good", level: 3 }, bz);
const bg3 = open(`Third${tag}`, "peach", 0, 0, { uid: "ddddddddddd4", side: "good", level: 4 }, bz);
for (const x of [bh, bg1, bg2, bg3]) {
  await x.ready;
  await x.next("welcome");
}
await new Promise((res) => setTimeout(res, 300));
async function duel(evil, good, goodUid, loser) {
  evil.send({ t: "duel", to: goodUid });
  await good.next("challenge");
  good.send({ t: "duel_ready" });
  await evil.next("duel_start");
  await good.next("duel_start");
  evil.send({ t: "duel_end", winner: loser === evil ? "good" : "evil" });
  await new Promise((res) => setTimeout(res, 300));
}
await duel(bh, bg1, "ddddddddddd2", bg1);
const paid = await bh.next("bounty");
check(paid.name === braveName && paid.coins === 100, "beating a level 20 hero pays their bounty");
await duel(bh, bg2, "ddddddddddd3", bg2);
await new Promise((res) => setTimeout(res, 300));
check(!bh.inbox.some((m) => m.t === "bounty"), "a weak hero has no bounty");
const lb3 = await (await fetch(`${base.replace(/^ws/, "http")}/leaders`)).json();
check(lb3.bounties.some((l) => l.name === hunter && l.bounty === 40), "an evil player on a 2-win streak shows on the bounty board");
await duel(bh, bg3, "ddddddddddd4", bh);
const won = await bg3.next("bounty");
check(won.name === hunter && won.coins === 40, "the hero who ends the streak collects the bounty");
const lb4 = await (await fetch(`${base.replace(/^ws/, "http")}/leaders`)).json();
check(!lb4.bounties.some((l) => l.name === hunter), "a broken streak takes the bounty down");
for (const x of [bh, bg1, bg2, bg3]) x.ws.close();

// Online saves.
const http = base.replace(/^ws/, "http");
async function post(op, body) {
  const r = await fetch(`${http}/account/${op}`, { method: "POST", body: JSON.stringify(body) });
  return { status: r.status, body: await r.json(), cors: r.headers.get("access-control-allow-origin") };
}
const who = `Smoke ${Date.now() % 1000000}`;
const reg = await post("register", { name: who, password: "pass1", save: { level: 3, saved_at: 100 } });
check(reg.status === 200 && /^[a-f0-9]{32}$/.test(reg.body.token) && reg.cors === "*", "register hands out a token");
check((await post("register", { name: who.toUpperCase(), password: "x1234", save: {} })).status === 409,
  "the same name in other letter case is taken");
check((await post("login", { name: who, password: "nope" })).status === 403, "a wrong password is refused");
const login = await post("login", { name: who.toLowerCase(), password: "pass1" });
check(login.status === 200 && login.body.save.level === 3 && login.body.saved_at === 100, "login returns the save");
const saved = await post("save", { name: who, token: login.body.token, save: { level: 4, saved_at: 200 } });
check(saved.status === 200 && saved.body.saved_at === 200, "a logged-in device can save");
const loaded = await post("load", { name: who, token: reg.body.token });
check(loaded.body.save.level === 4, "another device loads the newer save");
check((await post("save", { name: who, token: "0".repeat(32), save: {} })).status === 401, "a made-up token can't save");
check((await post("login", { name: "Nobody Here 0", password: "pass1" })).status === 403, "an unknown name can't log in");
const big = { junk: "x".repeat(70000) };
check((await post("save", { name: who, token: reg.body.token, save: big })).status >= 400, "a huge save is refused");
console.log("all good");
process.exit(0);
