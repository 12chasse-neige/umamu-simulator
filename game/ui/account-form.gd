extends VBoxContainer

const Preferences := preload("res://game/app/game-preferences.gd")
const Language := preload("res://game/app/game-language.gd")
const ControlsHelp := preload("res://game/ui/controls-help.gd")
const Session := preload("res://game/app/game-session.gd")
const Style := preload("res://game/ui/meet-theme.gd")
const Login := preload("res://game/apis/accounts/login-account-message.gd")
const Register := preload("res://game/apis/accounts/register-account-message.gd")
const Request := preload("res://game/apis/account-request.gd")

var _forms: VBoxContainer
var _status: Label
var _username := LineEdit.new()
var _password := LineEdit.new()
var _submit_button: Button
var _login_tab: Button
var _register_tab: Button
var _logout: Button
var _registering := false


func _ready() -> void:
	add_theme_constant_override("separation", 13)
	add_child(Style.label("Player account", 26))
	_status = Style.label("", 14, Style.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 32
	add_child(_status)
	_forms = Style.column(10)
	add_child(_forms)
	var tabs := Style.row(5)
	_forms.add_child(tabs)
	var modes := ButtonGroup.new()
	_login_tab = Style.button("Sign in", _mode.bind(false))
	_register_tab = Style.button("Register", _mode.bind(true))
	for tab in [_login_tab, _register_tab]:
		tab.toggle_mode = true
		tab.button_group = modes
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(tab)
	_login_tab.set_pressed_no_signal(true)
	_username.custom_minimum_size.y = 41
	_username.max_length = 24
	_password.custom_minimum_size.y = 41
	_password.secret = true
	_password.max_length = 128
	_password.text_submitted.connect(func(_text: String) -> void: _submit())
	_forms.add_child(Style.label("Username", 14))
	_forms.add_child(_username)
	_forms.add_child(Style.label("Password", 14))
	_forms.add_child(_password)
	_submit_button = Style.button("Sign in", _submit, true)
	_forms.add_child(_submit_button)
	_logout = Style.button("Sign out", _sign_out)
	add_child(_logout)
	var tools := Style.row(8)
	add_child(tools)
	var help := ControlsHelp.new()
	add_child(help)
	tools.add_child(Style.button("Controls", help.open))
	tools.add_child(Style.button("中文 / EN", Language.toggle))
	var names := CheckBox.new()
	names.text = "Show NPC names"
	names.set_pressed_no_signal(Preferences.show_npc_names)
	names.toggled.connect(Preferences.set_show_npc_names)
	add_child(names)
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _status != null and not Session.account_name.is_empty():
		_show_account_name()


func _mode(register: bool) -> void:
	_registering = register
	_submit_button.text = "Create account" if register else "Sign in"
	_password.clear()
	_refresh()


func _submit() -> void:
	if _submit_button.disabled:
		return
	if _username.text.strip_edges().is_empty() or _password.text.is_empty():
		_status.text = "Enter your username and password."
		return
	_submit_button.disabled = true
	_login_tab.disabled = true
	_register_tab.disabled = true
	_status.text = "Connecting…"
	var operation: Request
	if _registering:
		operation = Register.new(_username.text, _password.text)
	else:
		operation = Login.new(_username.text, _password.text)
	_password.clear()
	var result := await operation.send(self)
	_submit_button.disabled = false
	_login_tab.disabled = false
	_register_tab.disabled = false
	if result.has("username"):
		Session.account_name = result["username"]
		_refresh()
	else:
		_status.text = result["error"]


func _sign_out() -> void:
	Session.account_name = ""
	_refresh()


func _refresh() -> void:
	var guest := Session.account_name.is_empty()
	_forms.visible = guest
	_logout.visible = not guest
	if not guest:
		_show_account_name()
	elif _registering:
		_status.text = "Choose a username and a password of at least 8 characters."
	else:
		_status.text = "Playing as a guest"



func _show_account_name() -> void:
	_status.text = tr("Signed in as %s") % Session.account_name
