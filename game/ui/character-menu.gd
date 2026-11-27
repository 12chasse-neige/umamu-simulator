extends Control

const Runner := preload("res://game/runner/runner.gd")
const Roster := preload("res://game/ui/character-roster.gd")
const Style := preload("res://game/ui/meet-theme.gd")
const Grid := preload("res://game/ui/character-grid.gd")
const Session := preload("res://game/app/game-session.gd")

signal character_chosen(path: String)

@export var runner: Runner

var _initial_path := ""
var _restore_mouse_capture := false
var _was_paused := false

@onready var _choices: Grid = %Choices
@onready var _status: Label = %Status
@onready var _switch: Button = %Switch


func _ready() -> void:
	theme = Style.make()
	$Backdrop.color = Style.SCRIM
	$Center/Panel.add_theme_stylebox_override("panel", Style.box(Style.PANEL, Style.EDGE, 22, 14))
	_choices.configure(6, 128, 96, 410)
	_choices.item_selected.connect(_select)
	_choices.item_activated.connect(_choose)
	_switch.pressed.connect(_confirm)
	%Cancel.pressed.connect(_close)


func _input(event: InputEvent) -> void:
	if (runner != null and runner.competition) or (get_tree().paused and not visible):
		return
	if (runner != null and event.is_action_pressed(&"choose_character")) \
			or (visible and event.is_action_pressed(&"ui_cancel")):
		get_viewport().set_input_as_handled()
		if visible:
			_close()
		else:
			open(runner.active_character_path)


func open(current_path: String) -> void:
	_initial_path = current_path
	_was_paused = get_tree().paused
	_restore_mouse_capture = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if runner != null:
		runner.mouse_motion = Vector2.ZERO
	get_tree().paused = true
	show()

	_choices.clear()
	var paths := Roster.paths()
	if not _initial_path.is_empty() and _initial_path not in paths:
		paths.append(_initial_path)
	for path in paths:
		_add_choice(path)
	_add_choice("")
	if _choices.item_count == 1:
		_show_status("No local character models installed.")
	else:
		_show_status("")
	_switch.disabled = true
	_choices.grab_focus()
	_choices.ensure_current_is_visible()


func _add_choice(path: String) -> void:
	var display_name := Roster.display_name(path)
	var active := path == _initial_path
	var index := _choices.add_profile(display_name, path)
	_choices.set_item_metadata(index, path)
	_choices.set_item_tooltip(index, tr("%s · Playing") % display_name if active else display_name)
	if active:
		_choices.select(index)


func _select(index: int) -> void:
	_switch.disabled = _choices.get_item_metadata(index) == _initial_path
	_show_status("")


func _confirm() -> void:
	var selected := _choices.get_selected_items()
	if not selected.is_empty():
		_choose(selected[0])


func _choose(index: int) -> void:
	var path: String = _choices.get_item_metadata(index)
	if runner == null or runner.change_character(path):
		Session.character_path = path
		Session.character_selected = true
		_close()
		character_chosen.emit(path)
	else:
		_show_status("Could not load this character. Choose another model.")


func _show_status(message: String) -> void:
	_status.text = message
	_status.visible = not message.is_empty()


func _close() -> void:
	hide()
	get_tree().paused = _was_paused
	if _restore_mouse_capture and get_window().has_focus():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
