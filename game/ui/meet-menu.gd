extends Control

const Portraits := preload("res://game/ui/character-portraits.gd")
const Session := preload("res://game/app/game-session.gd")
const Style := preload("res://game/ui/meet-theme.gd")
const Roster := preload("res://game/ui/character-roster.gd")
const AccountForm := preload("res://game/ui/account-form.gd")
const PickerScene := preload("res://game/ui/character-menu.tscn")
const Picker := preload("res://game/ui/character-menu.gd")
const Background := preload("res://art/race/meet-background.jpg")
const CAMPUS := "res://game/campus/campus-walk.tscn"

var _character_path := ""
var _character_name: Label
var _portrait: TextureRect
var _picker: Picker


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = Style.make()
	var backdrop := TextureRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.texture = Background
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	add_child(Style.scrim(0.53))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var layout := Style.column(15)
	center.add_child(layout)
	layout.add_child(Style.label("TRACEN ACADEMY", 17, Color("#efe1ff")))
	layout.add_child(Style.label("Running meet", 60, Style.WHITE))
	var columns := Style.row(15)
	layout.add_child(columns)
	columns.add_child(_runner_panel())
	columns.add_child(Style.panel(AccountForm.new(), 301, 22))
	_picker = PickerScene.instantiate() as Picker
	add_child(_picker)
	_picker.character_chosen.connect(_set_character)
	var paths := Roster.paths()
	_set_character(Session.character_path if Session.character_selected else (paths[0] if not paths.is_empty() else ""))


func _runner_panel() -> PanelContainer:
	var content := Style.column(14)
	content.add_child(Style.label("Your runner", 26))
	var profile := Style.row(16)
	content.add_child(profile)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(166, 184)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var photo := PanelContainer.new()
	photo.add_theme_stylebox_override("panel", Style.box(Style.LAVENDER, Style.EDGE, 2, 10))
	photo.add_child(_portrait)
	profile.add_child(photo)
	var details := Style.column(11)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.alignment = BoxContainer.ALIGNMENT_CENTER
	profile.add_child(details)
	_character_name = Style.label("", 29, Style.ACCENT)
	_character_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_character_name)
	details.add_child(Style.button("Choose character", _open_picker))
	var directions := Style.label("Find the training oval on campus and press G at the start line.", 15, Style.MUTED)
	directions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(directions)
	content.add_child(Style.button("Enter Academy", _enter, true))
	return Style.panel(content, 510, 22)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _character_name != null:
		_character_name.text = Roster.display_name(_character_path)


func _open_picker() -> void:
	_picker.open(_character_path)


func _set_character(path: String) -> void:
	_character_path = path
	_character_name.text = Roster.display_name(path)
	_portrait.texture = Portraits.for_node(self, path)


func _enter() -> void:
	Session.character_path = _character_path
	Session.character_selected = true
	get_tree().change_scene_to_file(CAMPUS)
