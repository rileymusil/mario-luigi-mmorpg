// End-to-end check against a running server: `npm run dev`, then `npm test`.
// SERVER=wss://mario-luigi-mmo.<you>.workers.dev npm test checks a deployed one.
const base = process.env.SERVER ?? "ws://127.0.0.1:8787";
const zone = `smoke_${Date.now() % 100000}`;

function open(name, character, x, y) {
  const ws = new WebSocket(`${base}/zone/${zone}`);
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
      ws.send(JSON.stringify({ t: "hello", name, character, x, y }));
      resolve();
    };
    ws.onerror = () => reject(new Error(`${name}: could not connect to ${base}`));
  });
  return { ws, next, ready, send: (m) => ws.send(typeof m === "string" ? m : JSON.stringify(m)) };
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

const c = open("Cy", "luigi", 0, 0);
await c.ready;
const wc = await c.next("welcome");
const ann = wc.players.find((p) => p.id === wa.id);
check(wc.players.length === 2 && ann.x === 121, "late joiner sees everyone at their latest position");

const bad = open("Hax", "goomba", 0, 0);
await bad.ready;
await new Promise((r) => (bad.ws.onclose = r));
check(true, "unknown character is rejected");

b.ws.close();
const leave = await a.next("leave");
check(leave.id === wb.id, "leaving is broadcast");

a.ws.close();
c.ws.close();
console.log("all good");
process.exit(0);
