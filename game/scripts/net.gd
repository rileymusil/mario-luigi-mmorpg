extends Node
## Online play (autoloaded as "Net"): one WebSocket to the game server for
## the map you are on. Sends your position while you move and reports other
## players through signals. If SERVER_URL is empty or the server can't be
## reached, the game plays offline as before.
## The server lives in server/ at the repository root; see server/README.md.

## wss:// address of the deployed Worker. On the web build you can also
## override it with ?server=wss://... in the page address.
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
signal invite_declined(name: String)
signal party_changed                                # formed, ended, or partner arrived
signal warp_requested(map_id: String, spawn: String) # your partner took an exit
signal party_message(d: Dictionary)               # co-op battle traffic from your partner
signal challenged(foe: Dictionary)                  # an evil player attacks you: {id, name, character, stats}
signal duel_started(foe: Dictionary, first: bool)   # foe: Player + {stats}; first: you move first
signal duel_message(msg: Dictionary)                # duel_act / duel_hit from your foe
signal duel_over(result: String)                    # your foe ended the duel: lost, fled, timeout, left, busy, refused...
signal zone_reset                          # connection (re)opened: forget everyone

var my_id := ""
var players := {}  # id -> {id, name, character, side, x, y}: everyone else in your zone
## Party: your partner's id (their uid, the same on every map) and name, and
## whether they're on this map with you right now.
var party_id := ""
var party_name := ""
var party_here := false
var pending_warp := {}  # {map, spawn} to follow your partner once you're free
## True while the overworld is up and can take a duel; otherwise a challenge is
## answered "busy" straight away.
var in_world := false
var duel_foe := ""  # foe's id from challenging until the duel ends
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


func server_url() -> String:
	if OS.has_feature("web"):
		var from_page = JavaScriptBridge.eval("new URLSearchParams(location.search).get('server') || ''", true)
		if typeof(from_page) == TYPE_STRING and from_page != "":
			return from_page
	return SERVER_URL


func is_online() -> bool:
	return _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN and my_id != ""


## Joins the zone for a map. Staying on the same map (e.g. coming back from a
## battle) keeps the existing connection.
func join_zone(map_id: String, character: String, display_name: String, pos: Vector2) -> void:
	_hello = {"t": "hello", "name": display_name, "character": character, "x": pos.x, "y": pos.y}
	if map_id == _zone and _socket != null:
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
	_socket = null
	_zone = ""
	my_id = ""
	players.clear()
	party_here = false
	duel_foe = ""
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
	_send({"t": "duel", "to": id, "stats": Game.pvp_stats()})


## Answer a challenge: fight (sends your stats) or say you're busy.
func answer_challenge(ready: bool) -> void:
	if ready:
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
				hello["side"] = Game.player.get("side", "good")
				hello["party"] = party_id
				hello["safe"] = Game.MAPS.get(_zone, {}).get("safe", true)
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
				zone_reset.emit()
			_schedule_retry()


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
		"invite":
			invited.emit(str(msg["from"]), str(msg["name"]))
		"declined":
			invite_declined.emit(str(msg["name"]))
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
			duel_started.emit(foe, msg.get("first", false) == true)
		"duel_act", "duel_hit":
			duel_message.emit(msg)
		"duel_over":
			duel_foe = ""
			duel_over.emit(str(msg.get("result", "cancel")))
		"full":
			_zone = ""  # don't retry into a full zone


func _add(p: Dictionary) -> void:
	p["id"] = str(p["id"])
	players[p["id"]] = p
	player_joined.emit(p)
