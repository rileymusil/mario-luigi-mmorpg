extends Node
## Online play (autoloaded as "Net"): one WebSocket to the game server for
## the map you are on. Sends your position while you move and reports other
## players through signals. If SERVER_URL is empty or the server can't be
## reached, the game plays offline as before.
## The server lives in server/ at the repository root; see server/README.md.

## wss:// address of the deployed Worker. On the web build you can also
## override it with ?server=wss://... in the page address; on desktop (for
## testing against `npx wrangler dev`) with the MLMMO_SERVER environment
## variable or `-- --server=ws://127.0.0.1:8787` after the Godot arguments.
const SERVER_URL := "wss://mario-luigi-mmo.rileymusil2006.workers.dev"
const SEND_RATE := 5.0        # position updates per second while moving
const PING_SECONDS := 20.0    # keeps idle connections from being dropped
const RETRY_SECONDS := [2.0, 5.0, 10.0, 30.0]

signal player_joined(player: Dictionary)   # {id, name, character, x, y}
signal player_moved(id: String, pos: Vector2, velocity: Vector2)
signal player_jumped(id: String)
signal player_left(id: String)
signal player_arrived(player: Dictionary)  # someone walked in (not the roster on joining)
signal chat_received(id: String, name: String, text: String, party: bool)
signal invited(from_id: String, name: String)       # someone wants to team up
signal invite_declined(name: String, reason: String)  # reason "side": good and evil can't team up
signal party_changed                                # formed, ended, or partner arrived
signal warp_requested(map_id: String, spawn: String) # your partner took an exit
signal party_message(d: Dictionary)               # co-op battle traffic from your partner
signal challenged(foe: Dictionary)                  # an evil player attacks you: {id, name, character, stats}
signal duel_started(foe: Dictionary, first: bool)   # foe: Player + {stats}; first: you move first
signal duel_message(msg: Dictionary)                # duel_act / duel_hit from your foe
signal duel_over(result: String)                    # your foe ended the duel: lost, fled, timeout, left, busy, refused...
signal trade_requested(from_id: String, name: String) # someone asked to trade
signal trade_declined(name: String, reason: String)   # peer declined or busy
signal trade_started(peer_id: String, peer_name: String) # trade session active
signal trade_offer_updated(offer: Dictionary)         # peer updated coins, items, or partner
signal trade_confirmed_by(by_id: String)              # peer confirmed offer
signal trade_completed(your_give: Dictionary, your_receive: Dictionary) # trade completed!
signal trade_cancelled(reason: String)                # trade was cancelled
signal zone_reset                          # connection (re)opened: forget everyone
signal whisper_received(from_name: String, text: String)
signal whisper_sent(to_name: String, text: String)    # it got there; to_name as they spell it
signal whisper_failed(to_name: String)                 # nobody by that name is online
signal friends_status(online: Dictionary)              # lower-case name -> map id, or null when offline
signal bounty_won(name: String, coins: int)            # you beat someone with a bounty (already paid, see Game.collect_bounty)

var my_id := ""
var players := {}  # id -> {id, name, character, side, x, y}: everyone else in your zone
## Party: your partner's id (their uid, the same on every map) and name, and
## whether they're on this map with you right now.
var party_id := ""
var party_name := ""
var party_here := false
var pending_warp := {}  # {map, spawn} to follow your partner once you're free
## Trade: active trade partner id, name, and trading status
var trading_peer_id := ""
var trading_peer_name := ""
var is_trading := false
## True while the overworld is up and can take a duel; otherwise a challenge is
## answered "busy" straight away.
var in_world := false
var duel_foe := ""  # foe's id from challenging until the duel ends
## Duel traffic (duel_act, duel_hit, duel_over) since the duel started, so
## nothing is lost while the battle scene is still loading. pvp_battle.gd reads it.
var duel_inbox: Array = []
## While true, partner messages are also kept in party_inbox: set when you
## join your partner's battle, so their setup isn't lost while it loads.
var hold_party := false
var party_inbox: Array = []
var _socket: WebSocketPeer
var _zone := ""
var _hello := {}
var _was_open := false
var _send_timer := 0.0
var _ping_timer := 0.0
var _retry_timer := 0.0
var _retries := 0
var _last_sent := {}
var _pending_move := {}
var _closing: Array = []  # old sockets, polled until their close is sent


func server_url() -> String:
	if OS.has_feature("web"):
		var from_page = JavaScriptBridge.eval("new URLSearchParams(location.search).get('server') || ''", true)
		if typeof(from_page) == TYPE_STRING and from_page != "":
			return from_page
	else:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--server="):
				return arg.trim_prefix("--server=")
		if OS.get_environment("MLMMO_SERVER") != "":
			return OS.get_environment("MLMMO_SERVER")
	return SERVER_URL


func is_online() -> bool:
	return _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN and my_id != ""


## Joins the zone for a map. Staying on the same map (e.g. coming back from a
## battle) keeps the existing connection.
func join_zone(map_id: String, character: String, display_name: String, pos: Vector2) -> void:
	var same_look: bool = _hello.get("character") == character and _hello.get("name") == display_name \
		and _hello.get("side") == Game.player.get("side", "good")
	_hello = {"t": "hello", "name": display_name, "character": character, "x": pos.x, "y": pos.y,
		"side": Game.player.get("side", "good")}
	# Same map and still the same you: keep the connection. A side switch or a
	# new character on the same map reconnects, so the server sees the change.
	if map_id == _zone and _socket != null and same_look:
		return
	# Taking an exit (not being sent home) pulls your partner along.
	var spawn: String = Game.player.get("spawn", "start")
	if party_here and spawn != "start":
		_send({"t": "warp", "map": map_id, "spawn": spawn})
	leave()
	_zone = map_id
	_retries = 0
	_connect()


func leave() -> void:
	if _socket != null:
		_socket.close()
		_closing.append(_socket)
	_socket = null
	_zone = ""
	my_id = ""
	if not players.is_empty():
		players.clear()
		zone_reset.emit()
	party_here = false
	duel_foe = ""
	trading_peer_id = ""
	trading_peer_name = ""
	is_trading = false
	_was_open = false


## Call every frame with the local player's state; sends at most SEND_RATE
## times a second, and only when something changed.
func update_position(pos: Vector2, velocity: Vector2) -> void:
	_pending_move = {"t": "mv", "x": roundi(pos.x), "y": roundi(pos.y), "vx": roundi(velocity.x), "vy": roundi(velocity.y)}


func send_jump() -> void:
	_send({"t": "jump"})


## Returns false when not connected. The server trims, filters and echoes it back.
func send_chat(text: String, to_party := false) -> bool:
	if not is_online():
		return false
	_send({"t": "chat", "text": text, "party": to_party})
	return true


## A private message to the player named `to`, on any map. False when offline.
func whisper(to: String, text: String) -> bool:
	if not is_online():
		return false
	_send({"t": "whisper", "to": to, "text": text})
	return true


## Asks which of these players are online (answered with friends_status).
func request_friends(names: Array) -> bool:
	if not is_online() or names.is_empty():
		return false
	_send({"t": "friends", "names": names})
	return true


func send_invite(id: String) -> void:
	_send({"t": "invite", "to": id})


func answer_invite(from_id: String, accept: bool) -> void:
	_send({"t": "accept" if accept else "decline", "from": from_id})


## Anything for your partner on this map (co-op battles). Returns false if
## they aren't here to get it.
func send_party(d: Dictionary) -> bool:
	if not is_online() or not party_here:
		return false
	_send({"t": "pmsg", "d": d})
	return true


## Evil only: attack a good player standing next to you.
func challenge(id: String) -> void:
	duel_foe = id
	duel_inbox.clear()
	_send({"t": "duel", "to": id, "stats": Game.pvp_stats()})


## Answer a challenge: fight (sends your stats) or say you're busy.
func answer_challenge(ready: bool) -> void:
	if ready:
		duel_inbox.clear()
		_send({"t": "duel_ready", "stats": Game.pvp_stats()})
	else:
		duel_foe = ""
		_send({"t": "duel_busy"})


## duel_act / duel_hit to your foe.
func duel_send(msg: Dictionary) -> void:
	_send(msg)


## lost, fled, timeout or cancel.
func end_duel(result: String) -> void:
	if duel_foe != "":
		_send({"t": "duel_over", "result": result})
	duel_foe = ""


# --- Online Trading -----------------------------------------------------------

func request_trade(id: String) -> void:
	trading_peer_id = id
	_send({"t": "trade_req", "to": id})


func reply_trade(from_id: String, accept: bool) -> void:
	if not accept and trading_peer_id == from_id:
		trading_peer_id = ""
		is_trading = false
	_send({"t": "trade_reply", "from": from_id, "accept": accept})


func send_trade_offer(coins: int, items: Dictionary, partner) -> void:
	_send({"t": "trade_offer", "offer": {"coins": coins, "items": items, "partner": partner}})


func confirm_trade() -> void:
	_send({"t": "trade_confirm"})


func cancel_trade() -> void:
	_send({"t": "trade_cancel"})
	trading_peer_id = ""
	trading_peer_name = ""
	is_trading = false


func leave_party() -> void:
	_send({"t": "leave_party"})
	_end_party()


func _end_party() -> void:
	party_id = ""
	party_name = ""
	party_here = false
	pending_warp = {}
	party_changed.emit()


func _connect() -> void:
	var url := server_url()
	if url == "" or _zone == "":
		return
	_socket = WebSocketPeer.new()
	_was_open = false
	my_id = ""
	if _socket.connect_to_url("%s/zone/%s" % [url.trim_suffix("/"), _zone]) != OK:
		_schedule_retry()


func _schedule_retry() -> void:
	_socket = null
	_retry_timer = RETRY_SECONDS[mini(_retries, RETRY_SECONDS.size() - 1)]
	_retries += 1


func _send(msg) -> void:
	if is_online():
		_socket.send_text(msg if msg is String else JSON.stringify(msg))


func _process(delta: float) -> void:
	for old in _closing.duplicate():
		old.poll()
		if old.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_closing.erase(old)
	if _socket == null:
		if _zone != "" and _retry_timer > 0.0:
			_retry_timer -= delta
			if _retry_timer <= 0.0:
				_connect()
		return
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				_retries = 0
				_last_sent = {}
				players.clear()
				zone_reset.emit()
				var hello := _hello.duplicate()
				hello["uid"] = Game.player.get("uid", "")
				hello["key"] = _net_key()
				hello["side"] = Game.player.get("side", "good")
				hello["party"] = party_id
				hello["safe"] = Game.MAPS.get(_zone, {}).get("safe", true)
				hello["level"] = Game.player.get("level", 1)  # for the leaderboards
				hello["bosses"] = Game.total_boss_wins()
				_socket.send_text(JSON.stringify(hello))
			while _socket.get_available_packet_count() > 0:
				_handle(_socket.get_packet().get_string_from_utf8())
			_send_timer -= delta
			if _send_timer <= 0.0 and not _pending_move.is_empty() and _pending_move != _last_sent:
				_send(_pending_move)
				_last_sent = _pending_move
				_send_timer = 1.0 / SEND_RATE
			_ping_timer += delta
			if _ping_timer >= PING_SECONDS:
				_ping_timer = 0.0
				_socket.send_text("ping")
		WebSocketPeer.STATE_CLOSED:
			if _was_open:
				players.clear()
				my_id = ""
				zone_reset.emit()
				if party_here:
					party_here = false
					party_changed.emit()
			if _zone != "":
				_schedule_retry()
			else:
				_socket = null


func _handle(text: String) -> void:
	if text == "pong":
		return
	var msg = JSON.parse_string(text)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	match msg.get("t"):
		"welcome":
			my_id = str(msg["id"])
			for p in msg["players"]:
				_add(p)
		"join":
			_add(msg["player"])
			player_arrived.emit(msg["player"])
		"mv":
			var id := str(msg["id"])
			if players.has(id):
				players[id]["x"] = msg["x"]
				players[id]["y"] = msg["y"]
				player_moved.emit(id, Vector2(msg["x"], msg["y"]), Vector2(msg["vx"], msg["vy"]))
		"jump":
			player_jumped.emit(str(msg["id"]))
		"leave":
			var id := str(msg["id"])
			if players.erase(id):
				player_left.emit(id)
				if id == party_id:
					party_here = false
					party_changed.emit()
		"chat":
			chat_received.emit(str(msg["id"]), str(msg["name"]), str(msg["text"]), msg.get("party", false) == true)
		"whisper":
			if msg.get("sent", false) == true:
				whisper_sent.emit(str(msg.get("to", "")), str(msg.get("text", "")))
			else:
				whisper_received.emit(str(msg.get("from", "")), str(msg.get("text", "")))
		"whisper_fail":
			whisper_failed.emit(str(msg.get("to", "")))
		"friends":
			if typeof(msg.get("online")) == TYPE_DICTIONARY:
				friends_status.emit(msg["online"])
		"invite":
			invited.emit(str(msg["from"]), str(msg["name"]))
		"declined":
			invite_declined.emit(str(msg["name"]), str(msg.get("reason", "")))
		"party":
			party_id = str(msg["id"])
			party_name = str(msg["name"])
			party_here = true
			party_changed.emit()
		"party_end":
			_end_party()
		"warp":
			pending_warp = {"map": str(msg["map"]), "spawn": str(msg["spawn"])}
			warp_requested.emit(pending_warp["map"], pending_warp["spawn"])
		"pmsg":
			if typeof(msg.get("d")) == TYPE_DICTIONARY:
				if hold_party:
					party_inbox.append(msg["d"])
				party_message.emit(msg["d"])
		"challenge":
			var foe := {"id": str(msg["from"]), "name": str(msg["name"]), "character": str(msg["character"]),
				"stats": msg.get("stats", {})}
			if not in_world or duel_foe != "":
				_send({"t": "duel_busy"})
			else:
				duel_foe = foe["id"]
				challenged.emit(foe)
		"duel_start":
			var foe: Dictionary = msg["foe"]
			foe["id"] = str(foe["id"])
			duel_foe = foe["id"]
			duel_inbox.clear()
			duel_started.emit(foe, msg.get("first", false) == true)
		"duel_act", "duel_hit":
			duel_inbox.append(msg)
			duel_message.emit(msg)
		"duel_over":
			duel_foe = ""
			duel_inbox.append(msg)
			duel_over.emit(str(msg.get("result", "cancel")))
		"bounty":
			Game.collect_bounty(str(msg.get("name", "someone")), int(msg.get("coins", 0)))
			bounty_won.emit(str(msg.get("name", "")), int(msg.get("coins", 0)))
		"trade_req":
			trade_requested.emit(str(msg.get("from", "")), str(msg.get("name", "Someone")))
		"trade_declined":
			trading_peer_id = ""
			is_trading = false
			trade_declined.emit(str(msg.get("name", "They")), str(msg.get("reason", "declined")))
		"trade_start":
			trading_peer_id = str(msg.get("peer_id", ""))
			trading_peer_name = str(msg.get("peer_name", "Peer"))
			is_trading = true
			trade_started.emit(trading_peer_id, trading_peer_name)
		"trade_offer":
			trade_offer_updated.emit(msg.get("offer", {}))
		"trade_confirmed":
			trade_confirmed_by.emit(str(msg.get("by", "")))
		"trade_done":
			var give: Dictionary = msg.get("your_give", {})
			var recv: Dictionary = msg.get("your_receive", {})
			trading_peer_id = ""
			trading_peer_name = ""
			is_trading = false
			trade_completed.emit(give, recv)
		"trade_cancelled":
			trading_peer_id = ""
			trading_peer_name = ""
			is_trading = false
			trade_cancelled.emit(str(msg.get("reason", "cancelled")))
		"full", "replaced":
			_zone = ""  # don't retry into a full zone, or fight another tab with this save


## A secret kept with the save: lets this save take its id back from a stale
## connection (see the server's hello). Never shown to other players.
func _net_key() -> String:
	if str(Game.player.get("net_key", "")).length() < 16:
		Game.player["net_key"] = Crypto.new().generate_random_bytes(12).hex_encode()
	return Game.player["net_key"]


func _add(p: Dictionary) -> void:
	p["id"] = str(p["id"])
	players[p["id"]] = p
	player_joined.emit(p)
