extends SceneTree

const CAMPUS := preload("res://game/campus/campus-walk.tscn")
const Runner := preload("res://game/runner/runner.gd")
const CharacterMenu := preload("res://game/ui/character-menu.gd")

var failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var campus := CAMPUS.instantiate()
	root.add_child(campus)
	var runner := campus.get_node("SpecialWeek") as Runner
	var menu := campus.get_node("Controls/CharacterMenu") as CharacterMenu
	var choices := menu.get_node("%Choices") as ItemList
	var switch := menu.get_node("%Switch") as Button
	var initial := runner.active_character_path
	await physics_frame
	_press_key(KEY_TAB)
	_check(menu.visible and paused, "Tab should open the character picker and pause the campus.")
	var paths: Array[String] = []
	for index in choices.item_count:
		var path: String = choices.get_item_metadata(index)
		if not path.is_empty():
			paths.append(path)
	_check(choices.item_count == paths.size() + 1, "The picker should include a single runner proxy.")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_check(paths.size() == args[0].to_int(), "Expected %s character models, found %d." % [args[0], paths.size()])
	_press_key(KEY_ESCAPE)
	_check(not menu.visible and not paused, "Escape should close the picker and resume play.")

	paths.erase(initial)
	if not initial.is_empty():
		paths.append(initial)
	paths.append("")
	for path in paths:
		if path == runner.active_character_path:
			continue
		_press_key(KEY_TAB)
		var target := -1
		for index in choices.item_count:
			if choices.get_item_metadata(index) == path:
				target = index
				break
		_check(target >= 0, "The picker lost %s between switches." % path)
		if target < 0:
			break
		var location := runner.global_position
		choices.select(target)
		choices.item_selected.emit(target)
		_check(not switch.disabled, "Switch should be available for %s." % path)
		if path == paths[0]:
			_press_key(KEY_ENTER)
		else:
			switch.pressed.emit()
		_check(not menu.visible and not paused, "Switching should resume play for %s." % path)
		_check(runner.active_character_path == path, "The picker did not activate %s." % path)
		_check(runner.global_position == location, "Switching should preserve the player position.")
		_check((runner.motion != null) == not path.is_empty(), "Unexpected pose solver for %s." % path)
		await process_frame

	print("Character switching checked for %d models and the proxy." % (paths.size() - 1))
	quit(1 if failed else 0)


func _press_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	root.push_input(event)


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failed = true
