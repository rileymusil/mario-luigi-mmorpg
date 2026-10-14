# Game server

A Cloudflare Worker with one Durable Object per map ("zone"). Players on the
same map see each other walk and jump. It runs on the Workers Free plan; if the
daily free limit is used up, connections fail until 00:00 UTC and nothing is
billed. The game keeps working offline when the server can't be reached.

The protocol is described at the top of `src/index.ts`. The Godot side is
`game/scripts/net.gd`.

## Run it locally

```sh
cd server
npm install
npm run dev        # serves ws://127.0.0.1:8787
npm test           # in a second terminal: two fake players walk around
```

To point the game at it, set `SERVER_URL` in `game/scripts/net.gd`, or on the
web build add `?server=ws://127.0.0.1:8787` to the page address. A desktop run
takes `MLMMO_SERVER=ws://127.0.0.1:8787` in the environment, or
`-- --server=ws://127.0.0.1:8787` after the Godot arguments.

## Deploy (one-time setup)

1. Make a free account at https://dash.cloudflare.com and open
   **Workers & Pages** once, so the account gets its `workers.dev` address.
2. Copy your **Account ID** from the Workers & Pages overview page.
3. **My Profile > API Tokens > Create Token**, use the **Edit Cloudflare
   Workers** template, and copy the token.
4. In this GitHub repository: **Settings > Secrets and variables > Actions**,
   add the secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.
5. **Actions > Game server > Run workflow**. The deploy step prints the
   address, like `https://mario-luigi-mmo.<your-name>.workers.dev`.
6. Put that address in `SERVER_URL` in `game/scripts/net.gd`, with `wss://`
   in place of `https://`, and push. Pages redeploys the game.

After that, every push to `main` that touches `server/` redeploys the server
and runs the smoke test against the live address.

Live server: `wss://mario-luigi-mmo.rileymusil2006.workers.dev`
