extends Control

const Portraits := preload("res://game/ui/character-portraits.gd")
const Style := preload("res://game/ui/meet-theme.gd")
const Result := preload("res://game/race/race-result.gd")

var _mode: String
var _retry_action: Callable
var _leave_action: Callable
var _retry: Button
var _finish_order: Array[Result] = []


func build(title: String, retry: Callable, leave: Callable) -> void:
	_mode = title
	_retry_action = retry
	_leave_action = leave
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()


func reveal(order: Array[Result]) -> void:
	_finish_order = order
	var dim := Style.scrim()
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var sheet := Style.column(10)
	var panel := Style.panel(sheet, 858, 20)
	center.add_child(panel)
	var header := Style.row(10)
	sheet.add_child(header)
	var title := Style.label("Race results", 35)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(Style.label(tr("%s  ·  2 laps") % tr(_mode), 17, Style.MUTED))
	var columns := Style.row(12)
	sheet.add_child(columns)
	var winner := _winner(order[0])
	columns.add_child(winner)
	var scores := Style.column(3)
	scores.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(scores)
	var headings := Style.row(8)
	headings.add_child(Style.label("Place   Runner", 14, Style.MUTED))
	headings.add_spacer(false)
	headings.add_child(Style.label("Total time", 14, Style.MUTED))
	scores.add_child(headings)
	var entries: Array[Control] = []
	for index in order.size():
		var cell := _row(order[index], index + 1)
		scores.add_child(cell)
		entries.append(cell)

	var controls := Style.row(8)
	controls.alignment = BoxContainer.ALIGNMENT_END
	sheet.add_child(controls)
	controls.add_child(Style.button("Back to track", _leave_action))
	_retry = Style.button("Race again", _retry_action, true)
	controls.add_child(_retry)
	show()
	_animate(dim, panel, winner, entries)


func _winner(result: Result) -> PanelContainer:
	var card := Style.column(8)
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	var block := PanelContainer.new()
	block.custom_minimum_size.x = 236
	block.add_theme_stylebox_override("panel", Style.box(Style.LAVENDER, Style.EDGE, 13, 11))
	block.add_child(card)
	var honour := Style.label("1st place", 22, Style.ACCENT)
	honour.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(honour)
	card.add_child(_photo(result.model, Vector2(204, 211)))
	var winner_name := Style.label(result.title, 23)
	winner_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	winner_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(winner_name)
	var time := Style.label(Result.clock(result.seconds), 26, Style.ACCENT)
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(time)
	return block


func _row(result: Result, rank: int) -> PanelContainer:
	var line := Style.row(9)
	line.custom_minimum_size.y = 32
	var number := Style.label(str(rank), 17, Style.ACCENT)
	number.custom_minimum_size.x = 28
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_child(number)
	line.add_child(_photo(result.model, Vector2(32, 32)))
	var runner := Style.label(result.title, 15)
	runner.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	runner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(runner)
	if result.is_player:
		line.add_child(Style.label("You", 13, Style.ACCENT))
	var time := Style.label(Result.clock(result.seconds), 17)
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time.custom_minimum_size.x = 80
	line.add_child(time)
	var cell := PanelContainer.new()
	cell.add_theme_stylebox_override("panel", Style.box(
		Style.MINT if result.is_player else (Color("#fff2d6") if rank == 1 else Color("#f8f5fd")),
		Style.EDGE, 2, 5))
	cell.add_child(line)
	return cell


func _photo(model: String, dimensions: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.custom_minimum_size = dimensions
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture = Portraits.for_node(self, model)
	return image


func _animate(dim: ColorRect, panel: Control, winner: Control, entries: Array[Control]) -> void:
	dim.modulate.a = 0.0
	panel.modulate.a = 0.0
	winner.modulate.a = 0.0
	winner.scale = Vector2(0.92, 0.92)
	for entry in entries:
		entry.modulate.a = 0.0
	var motion := create_tween().set_parallel()
	motion.tween_property(dim, "modulate:a", 1.0, 0.28)
	motion.tween_property(panel, "modulate:a", 1.0, 0.32).set_delay(0.16)
	motion.tween_property(winner, "modulate:a", 1.0, 0.42).set_delay(0.38)
	motion.tween_property(winner, "scale", Vector2.ONE, 0.56).set_delay(0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for index in entries.size():
		motion.tween_property(entries[index], "modulate:a", 1.0, 0.23).set_delay(0.58 + index * 0.065)
	_retry.grab_focus()
