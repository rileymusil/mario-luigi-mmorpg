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
signal zone_reset                          # connection (re)opened: forget everyone

var my_id := ""
var players := {}  # id -> {id, name, character, x, y}: everyone else in your zone
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
	_was_open = false


## Call every frame with the local player's state; sends at most SEND_RATE
## times a second, and only when something changed.
func update_position(pos: Vector2, velocity: Vector2) -> void:
	_pending_move = {"t": "mv", "x": roundi(pos.x), "y": roundi(pos.y), "vx": roundi(velocity.x), "vy": roundi(velocity.y)}


func send_jump() -> void:
	_send({"t": "jump"})


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
				_socket.send_text(JSON.stringify(_hello))
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
		"full":
			_zone = ""  # don't retry into a full zone


func _add(p: Dictionary) -> void:
	p["id"] = str(p["id"])
	players[p["id"]] = p
	player_joined.emit(p)
