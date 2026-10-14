extends Node
## Online saves (autoloaded as "Cloud"). A player who saves online picks a
## password for their username; from then on every save is also sent to the
## game server (at most every UPLOAD_EVERY seconds), and they can log in with
## that name and password in any browser to carry on. The server side is
## server/src/accounts.ts.
## Game.player["account"] = {"name", "token"} once linked; it stays out of the
## copy that goes online.

const UPLOAD_EVERY := 10.0

signal _uploaded(ok: bool)

var _dirty := false
var _uploading := false
var _since := UPLOAD_EVERY


## https:// address of the game server (the same Worker as Net's wss:// one).
func base_url() -> String:
	var u := Net.server_url()
	if u.begins_with("wss://"):
		return "https://" + u.trim_prefix("wss://")
	if u.begins_with("ws://"):
		return "http://" + u.trim_prefix("ws://")
	return u


## True if this save is saved online too.
func linked() -> bool:
	return typeof(Game.player.get("account")) == TYPE_DICTIONARY


func account_name() -> String:
	return str(Game.player["account"]["name"]) if linked() else ""


## Game.save() calls this: the next upload picks up the change.
func mark_dirty() -> void:
	if linked():
		_dirty = true


func _process(delta: float) -> void:
	_since += delta
	if _dirty and not _uploading and _since >= UPLOAD_EVERY:
		upload()


## Sends the save now. Returns true if the server has it.
func upload() -> bool:
	while _uploading:
		await _uploaded  # one already on its way may have an older copy
	if not linked():
		return false
	_uploading = true
	_dirty = false
	_since = 0.0
	var acct: Dictionary = Game.player["account"]
	var res := await call_server("save", {"name": acct["name"], "token": acct["token"], "save": online_copy()})
	_uploading = false
	var ok: bool = res["status"] == 200
	if res["status"] == 401:
		# This device was logged out (too many others logged in since).
		Game.player.erase("account")
		Game.save()
	elif not ok:
		_dirty = true  # try again later
	_uploaded.emit(ok)
	return ok


## The save without the login.
func online_copy() -> Dictionary:
	var d: Dictionary = Game.player.duplicate(true)
	d.erase("account")
	return d


## Saves online for the first time under the current username.
## Returns "" when it worked, else "taken", "offline" or another error word.
func register(password: String) -> String:
	Game.save()
	var who := Game.username()
	var res := await call_server("register", {"name": who, "password": password, "save": online_copy()})
	if res["status"] != 200:
		return _error(res)
	Game.player["account"] = {"name": str(res["body"].get("name", who)), "token": str(res["body"]["token"])}
	Game.save()
	_dirty = false
	return ""


## Logs in and makes the online save this browser's save.
## Returns "" when it worked, else "wrong", "locked", "offline"...
func login(who: String, password: String) -> String:
	var res := await call_server("login", {"name": who, "password": password})
	if res["status"] != 200:
		return _error(res)
	var data = res["body"].get("save")
	if typeof(data) != TYPE_DICTIONARY:
		return "save"
	data["account"] = {"name": str(res["body"].get("name", who)), "token": str(res["body"]["token"])}
	if not Game.use_save(data):
		return "save"
	Game.save()
	_dirty = false
	return ""


## Before continuing a linked save: if another device saved since, take its
## copy. Gives up quietly when the server can't be reached.
func pull_newer() -> void:
	if not linked():
		return
	var acct: Dictionary = Game.player["account"]
	var res := await call_server("load", {"name": acct["name"], "token": acct["token"]}, 5.0)
	if res["status"] == 401:
		Game.player.erase("account")
		Game.save()
		return
	if res["status"] != 200:
		return
	var data = res["body"].get("save")
	if typeof(data) != TYPE_DICTIONARY:
		return
	if float(data.get("saved_at", 0)) > float(Game.player.get("saved_at", 0)) + 0.5:
		data["account"] = acct
		if Game.use_save(data):
			Game.save()
			_dirty = false


## What an error means to the player.
static func error_text(code: String) -> String:
	match code:
		"taken":
			return "Someone already saved online with that name."
		"wrong":
			return "Wrong name or password."
		"locked":
			return "Too many wrong tries. Wait 10 minutes and try again."
		"offline":
			return "Couldn't reach the game server. Try again in a bit."
		"password":
			return "Passwords need 4 to 64 letters or numbers."
		"name":
			return "That isn't a username anyone can have."
	return "Something went wrong saving online. Try again in a bit."


func _error(res: Dictionary) -> String:
	if res["status"] == 0:
		return "offline"
	return str(res["body"].get("error", "error"))


## POSTs to /account/<op>. Returns {"status": HTTP status (0: no answer),
## "body": the reply}.
func call_server(op: String, body: Dictionary, timeout := 10.0) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = timeout
	add_child(req)
	var err := req.request(base_url() + "/account/" + op, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		req.queue_free()
		return {"status": 0, "body": {}}
	var res: Array = await req.request_completed
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "body": {}}
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return {"status": int(res[1]), "body": parsed if typeof(parsed) == TYPE_DICTIONARY else {}}
