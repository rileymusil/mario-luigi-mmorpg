class_name AccountModal
extends Control
## Overhauled Account Management, Creation, and Login Modal.
## Supports Logging In, Creating new accounts, and managing linked cloud status.

signal closed
signal account_changed

@onready var dim: ColorRect = $Dim
@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/VBox/Header/Title
@onready var tab_login_btn: Button = $Panel/VBox/Tabs/LoginTab
@onready var tab_register_btn: Button = $Panel/VBox/Tabs/RegisterTab

# Form elements
@onready var user_label: Label = $Panel/VBox/Form/UserRow/Value
@onready var user_btn: Button = $Panel/VBox/Form/UserRow/EditBtn

@onready var pass_label: Label = $Panel/VBox/Form/PassRow/Value
@onready var pass_btn: Button = $Panel/VBox/Form/PassRow/EditBtn

@onready var pass2_row: HBoxContainer = $Panel/VBox/Form/Pass2Row
@onready var pass2_label: Label = $Panel/VBox/Form/Pass2Row/Value
@onready var pass2_btn: Button = $Panel/VBox/Form/Pass2Row/EditBtn

@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var action_btn: Button = $Panel/VBox/ActionBtn
@onready var close_btn: Button = $Panel/VBox/CloseBtn

# Info elements (when already logged in)
@onready var info_box: VBoxContainer = $Panel/VBox/InfoBox
@onready var info_account_label: Label = $Panel/VBox/InfoBox/AccountName
@onready var info_sync_label: Label = $Panel/VBox/InfoBox/SyncStatus
@onready var info_sync_btn: Button = $Panel/VBox/InfoBox/SyncBtn
@onready var info_logout_btn: Button = $Panel/VBox/InfoBox/LogoutBtn
@onready var form_box: VBoxContainer = $Panel/VBox/Form

var prompt: TextPrompt
var mode := "login" # "login", "register", "info"
var current_user := ""
var current_pass := ""
var current_pass2 := ""
var _is_busy := false


func _ready() -> void:
	visible = false
	prompt = TextPrompt.new()
	add_child(prompt)

	get_tree().root.size_changed.connect(_layout_modal)
	tab_login_btn.pressed.connect(_set_mode.bind("login"))
	tab_register_btn.pressed.connect(_set_mode.bind("register"))
	user_btn.pressed.connect(_edit_username)
	pass_btn.pressed.connect(_edit_password)
	pass2_btn.pressed.connect(_edit_password_confirm)
	action_btn.pressed.connect(_on_action_pressed)
	close_btn.pressed.connect(close)
	info_sync_btn.pressed.connect(_on_sync_pressed)
	info_logout_btn.pressed.connect(_on_logout_pressed)


func _layout_modal() -> void:
	if not visible:
		return
	var vp := get_viewport_rect().size
	var safe := Game.get_safe_rect()
	dim.size = vp
	dim.position = Vector2.ZERO
	panel.custom_minimum_size = Vector2(minf(280.0, safe.size.x - 16.0), minf(190.0, safe.size.y - 10.0))
	panel.size = panel.custom_minimum_size
	panel.position = (safe.position + (safe.size - panel.size) / 2.0).round()
	if prompt:
		prompt.position = ((vp - prompt.size) / 2.0).round()


func open(initial_mode := "") -> void:
	if initial_mode != "":
		mode = initial_mode
	elif Cloud.linked():
		mode = "info"
	else:
		mode = "login"

	current_user = Game.username()
	current_pass = ""
	current_pass2 = ""
	_set_mode(mode)
	visible = true
	_layout_modal()


func close() -> void:
	visible = false
	closed.emit()


func _set_mode(new_mode: String) -> void:
	mode = new_mode
	status_label.text = ""

	if mode == "info":
		title_label.text = "ONLINE ACCOUNT STATUS"
		$Panel/VBox/Tabs.visible = false
		form_box.visible = false
		action_btn.visible = false
		info_box.visible = true
		info_account_label.text = "Logged in as: %s" % Cloud.account_name()
		info_sync_label.text = "Online Cloud Saves Active"
		info_sync_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	else:
		$Panel/VBox/Tabs.visible = true
		form_box.visible = true
		action_btn.visible = true
		info_box.visible = false

		if mode == "login":
			title_label.text = "LOG IN TO ACCOUNT"
			tab_login_btn.disabled = true
			tab_register_btn.disabled = false
			pass2_row.visible = false
			action_btn.text = "Log In"
			status_label.text = "Enter your username and password."
			status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		else:
			title_label.text = "CREATE ONLINE ACCOUNT"
			tab_login_btn.disabled = false
			tab_register_btn.disabled = true
			pass2_row.visible = true
			action_btn.text = "Create Account & Save"
			status_label.text = "Pick a username and 4+ character password."
			status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))

	_refresh_fields()
	_layout_modal()


func _refresh_fields() -> void:
	user_label.text = current_user if current_user != "" else "(Tap to enter)"
	user_label.add_theme_color_override("font_color", Color(1, 1, 1) if current_user != "" else Color(0.7, 0.7, 0.7))

	pass_label.text = "*".repeat(current_pass.length()) if current_pass != "" else "(Tap to enter)"
	pass_label.add_theme_color_override("font_color", Color(1, 1, 1) if current_pass != "" else Color(0.7, 0.7, 0.7))

	pass2_label.text = "*".repeat(current_pass2.length()) if current_pass2 != "" else "(Tap to enter)"
	pass2_label.add_theme_color_override("font_color", Color(1, 1, 1) if current_pass2 != "" else Color(0.7, 0.7, 0.7))


func _edit_username() -> void:
	if _is_busy:
		return
	var res := await prompt.ask("Username", current_user, 16, "Letters, numbers, and spaces")
	if res != "":
		current_user = Game.clean_username(res)
		_refresh_fields()


func _edit_password() -> void:
	if _is_busy:
		return
	var res := await prompt.ask("Password", "", 64, "Minimum 4 characters", true)
	if res != "":
		current_pass = res
		_refresh_fields()


func _edit_password_confirm() -> void:
	if _is_busy:
		return
	var res := await prompt.ask("Confirm Password", "", 64, "Re-enter password", true)
	if res != "":
		current_pass2 = res
		_refresh_fields()


func _on_action_pressed() -> void:
	if _is_busy:
		return
	if current_user == "":
		status_label.text = "Please enter a username."
		status_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
		return
	if current_pass == "":
		status_label.text = "Please enter a password."
		status_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
		return
	if current_pass.length() < 4:
		status_label.text = "Password must be at least 4 characters."
		status_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
		return

	if mode == "register":
		if current_pass != current_pass2:
			status_label.text = "Passwords do not match."
			status_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
			return

		_is_busy = true
		status_label.text = "Checking username..."
		status_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))

		var available := await Cloud.check_username(current_user)
		if not available:
			_is_busy = false
			status_label.text = "Username '%s' is already taken." % current_user
			status_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
			return

		status_label.text = "Creating online account..."
		Game.player["username"] = current_user
		var err := await Cloud.register(current_pass)
		_is_busy = false

		if err != "":
			status_label.text = Cloud.error_text(err)
			status_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
			return

		status_label.text = "Account created & saved online!"
		status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		account_changed.emit()
		var timer := get_tree().create_timer(1.2)
		timer.timeout.connect(close)

	elif mode == "login":
		_is_busy = true
		status_label.text = "Logging in..."
		status_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))

		var err := await Cloud.login(current_user, current_pass)
		_is_busy = false

		if err != "":
			status_label.text = Cloud.error_text(err)
			status_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
			return

		status_label.text = "Logged in successfully! Save loaded."
		status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		account_changed.emit()
		var timer := get_tree().create_timer(1.2)
		timer.timeout.connect(close)


func _on_sync_pressed() -> void:
	if _is_busy:
		return
	_is_busy = true
	info_sync_label.text = "Syncing with cloud..."
	info_sync_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	var ok := await Cloud.upload()
	_is_busy = false
	if ok:
		info_sync_label.text = "Synced successfully!"
		info_sync_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	else:
		info_sync_label.text = "Sync failed. Will retry automatically."
		info_sync_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))


func _on_logout_pressed() -> void:
	Cloud.logout()
	account_changed.emit()
	_set_mode("login")
