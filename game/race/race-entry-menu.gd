extends CanvasLayer

const Portraits := preload("res://game/ui/character-portraits.gd")
const Style := preload("res://game/ui/meet-theme.gd")
const Grid := preload("res://game/ui/character-grid.gd")
const Lineup := preload("res://game/race/race-lineup.gd")
const Roster := preload("res://game/ui/character-roster.gd")

const Pace := preload("res://game/race/race-pace.gd")
const Profile := preload("res://game/race/race-profile.gd")

var _strategy_buttons: Array[Button] = []
var _strategy := Pace.Strategy.PACE
var _profile: Profile
var _profile_path := ""
var _stats: Label
var _strategy_hint: Label
var _create_race: Callable
var _restore_mouse := false
var _mudland := false
var _candidates: Array[Lineup.Rival] = []
var _last_picks: Array[Lineup.Rival] = []
var _grid := Grid.new()
var _lineup: VBoxContainer
var _count: Label
var _start_button: Button


func build(start: Callable, solo: Callable) -> void:
	_create_race = start
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	layer = 5
	hide()
	var screen := Control.new()
	screen.theme = Style.make()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	screen.add_child(Style.scrim())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var content := Style.column(13)
	center.add_child(Style.panel(content, 902, 19))
	var header := Style.row(12)
	content.add_child(header)
	var heading := Style.label("Race entry", 33)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	header.add_child(Style.label("Two laps  ·  Nine runners", 16, Style.MUTED))
	var columns := Style.row(14)
	content.add_child(columns)
	var rivals := Style.column(8)
	rivals.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(rivals)
	var tools := Style.row(7)
	rivals.add_child(tools)
	var label := Style.label("Choose your rivals", 21, Style.ACCENT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(label)
	tools.add_child(Style.button("Clear", _clear))
	tools.add_child(Style.button("Auto-fill", _fill))
	_grid.configure(5, 106, 74, 338)
	_grid.select_mode = ItemList.SELECT_TOGGLE
	_grid.multi_selected.connect(_changed)
	rivals.add_child(_grid)

	var side := Style.column(7)
	columns.add_child(Style.panel(side, 230, 11))
	_count = Style.label("", 20, Style.ACCENT)
	side.add_child(_count)
	_lineup = Style.column(4)
	side.add_child(_lineup)

	_stats = Style.label("", 15)
	content.add_child(_stats)
	var strategies := Style.row(7)
	content.add_child(strategies)
	strategies.add_child(Style.label("Style aptitude", 17))
	var styles := ButtonGroup.new()
	for index in Pace.NAMES.size():
		var button := Style.button(Pace.NAMES[index], _select_strategy.bind(index))
		button.toggle_mode = true
		button.button_group = styles
		strategies.add_child(button)
		_strategy_buttons.append(button)
	_strategy_hint = Style.label("", 15, Style.MUTED)
	content.add_child(_strategy_hint)
	var actions := Style.row(8)
	content.add_child(actions)
	var group := ButtonGroup.new()
	for mud in [false, true]:
		var surface := Style.button("Mudland" if mud else "Grassland", _set_surface.bind(mud))
		surface.toggle_mode = true
		surface.button_group = group
		actions.add_child(surface)
		surface.set_pressed_no_signal(mud == _mudland)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	actions.add_child(Style.button("Solo practice", _choose.bind(solo)))
	actions.add_child(Style.button("Cancel", close))
	_start_button = Style.button("Start race", _start, true)
	actions.add_child(_start_button)


func open(player_path: String) -> void:
	_restore_mouse = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _profile == null or _profile_path != player_path:
		_profile_path = player_path
		_profile = Profile.new(player_path, "Runner proxy")
		_strategy = _profile.preferred_style([0, 0, 0, 0]) as Pace.Strategy
	for index in Pace.NAMES.size():
		_strategy_buttons[index].text = "%s  %s" % [tr(Pace.NAMES[index]), _profile.styles[index]]
	_stats.text = tr("%s    ·    Speed %d    Stamina %d    Power %d    Guts %d    Wit %d") % [
		Roster.display_name(player_path), _profile.speed, _profile.stamina, _profile.power, _profile.guts, _profile.wit]
	_select_strategy(_strategy)
	_candidates = Lineup.available(player_path)
	_grid.clear()
	for rival in _candidates:
		_grid.add_profile(rival.display_title(), rival.path)
	for previous in _last_picks:
		for index in _candidates.size():
			if _candidates[index].title == previous.title and _candidates[index].path == previous.path:
				_grid.select(index, false)
				break
	_fill()
	show()
	get_tree().paused = true
	_grid.grab_focus()


func selected_rivals() -> Array[Lineup.Rival]:
	var rivals: Array[Lineup.Rival] = []
	for index in _grid.get_selected_items():
		rivals.append(_candidates[index])
	return rivals


func close() -> void:
	hide()
	get_tree().paused = false
	if _restore_mouse and get_window().has_focus():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _changed(index: int, chosen: bool) -> void:
	if chosen and _grid.get_selected_items().size() > Lineup.RIVALS:
		_grid.deselect(index)
	_update_lineup()


func _update_lineup() -> void:
	for child in _lineup.get_children():
		_lineup.remove_child(child)
		child.queue_free()
	var picks := selected_rivals()
	_count.text = tr("%d / %d rivals") % [picks.size(), Lineup.RIVALS]
	for index in Lineup.RIVALS:
		var entry := Style.row(6)
		entry.custom_minimum_size.y = 30
		_lineup.add_child(entry)
		if index >= picks.size():
			entry.add_child(Style.label("Open spot", 14, Style.MUTED))
			continue
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(25, 29)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = Portraits.for_node(self, picks[index].path)
		entry.add_child(icon)
		var name_label := Style.label(picks[index].display_title(), 14)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.add_child(name_label)
	_start_button.disabled = picks.size() != Lineup.RIVALS


func _clear() -> void:
	_grid.deselect_all()
	_update_lineup()


func _fill() -> void:
	var remaining := Lineup.RIVALS - _grid.get_selected_items().size()
	for index in _candidates.size():
		if remaining <= 0:
			break
		if not _grid.is_selected(index):
			_grid.select(index, false)
			remaining -= 1
	_update_lineup()


func _select_strategy(value: Pace.Strategy) -> void:
	_strategy = value
	_strategy_buttons[value].set_pressed_no_signal(true)
	_strategy_hint.text = tr("%s.  This style is fixed for both laps.") % tr(Pace.PLAN[value])


func _set_surface(mudland: bool) -> void:
	_mudland = mudland


func _start() -> void:
	var picks := selected_rivals()
	if picks.size() == Lineup.RIVALS:
		_last_picks = picks
		close()
		_create_race.call(_mudland, picks, _strategy)


func _choose(action: Callable) -> void:
	close()
	action.call()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
