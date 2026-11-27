extends AcceptDialog

const Style := preload("res://game/ui/meet-theme.gd")
const CONTROLS := [
	["WASD", "Move or steer. Run automatically during a race."],
	["Mouse", "Look around"],
	["Alt / Shift", "Walk or run while exploring"],
	["Hold RMB", "Accelerate while running"],
	["Space", "Jump. Press again in the air to double-jump."],
	["C / Z", "Crouch or lie down"],
	["F", "Grab a wall, ledge, ladder or tree. Press again to let go."],
	["WASD / W and S", "Climb walls or move up and down trees and ladders"],
	["G", "Open race entry at the start stripe or cancel solo practice"],
	["E / T", "Use a nearby door or advance the time of day"],
	["Tab / R", "Choose a character or return to the gate"],
	["Esc / Left mouse", "Leave a meet, release the mouse, or click to recapture"],
	["F2", "Return to the main menu from campus"],
]


func _ready() -> void:
	var dialog_theme := Style.make().duplicate() as Theme
	dialog_theme.set_stylebox("panel", "AcceptDialog", Style.box(Style.PANEL, Style.EDGE, 16))
	theme = dialog_theme
	get_ok_button().theme_type_variation = &"PrimaryButton"
	var list := GridContainer.new()
	list.columns = 2
	list.add_theme_constant_override("h_separation", 24)
	list.add_theme_constant_override("v_separation", 7)
	for binding in CONTROLS:
		list.add_child(Style.label(binding[0], 15, Style.ACCENT))
		var description := Style.label(binding[1], 16)
		description.custom_minimum_size.x = 400
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(description)
	add_child(list)


func open() -> void:
	title = tr("Controls")
	get_ok_button().text = tr("Close")
	popup_centered()
