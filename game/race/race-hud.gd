extends CanvasLayer

const Style := preload("res://game/ui/meet-theme.gd")
const Result := preload("res://game/race/race-result.gd")
const Results := preload("res://game/race/race-results.gd")

const Pace := preload("res://game/race/race-pace.gd")

var _pace: Label
var _limits: Label
var _effort: Label
var _summary: Label
var _time: Label
var _cue: Label
var _waiting: Label
var _finish: Results
var _live: Control


func build(title: String, retry: Callable, leave: Callable) -> void:
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.theme = Style.make()
	add_child(screen)
	_live = Control.new()
	_live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(_live)
	var details := Style.column(3)
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var info := Style.panel(details, 220, 12)
	info.position = Vector2(24, 24)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live.add_child(info)
	details.add_child(Style.label(title, 19, Style.ACCENT))
	_summary = Style.label("", 16)
	_time = Style.label("00:00.00", 27)
	_waiting = Style.label("", 14, Style.MUTED)
	_waiting.hide()
	details.add_child(_summary)
	details.add_child(_time)
	_pace = Style.label("", 16, Style.ACCENT)
	details.add_child(_pace)
	_limits = Style.label("", 14, Style.MUTED)
	details.add_child(_limits)
	_effort = Style.label("", 14, Style.ACCENT)
	details.add_child(_effort)
	details.add_child(_waiting)

	_cue = Style.label("", 56, Style.WHITE)
	_cue.add_theme_color_override("font_outline_color", Style.ACCENT)
	_cue.add_theme_constant_override("outline_size", 12)
	_cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cue.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_cue.offset_left = -180.0
	_cue.offset_right = 180.0
	_cue.offset_top = 142.0
	_cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live.add_child(_cue)

	_finish = Results.new()
	screen.add_child(_finish)
	_finish.build(title, retry, leave)


func update_pace(pace: Pace) -> void:
	_pace.text = "%s  ·  %s" % [tr(Pace.NAMES[pace.strategy]), tr(Pace.STAGES[pace.stage])]
	_limits.text = tr("Energy %d%%    Cap %.2f m/s    Accel %.2f m/s²") % [
		roundi(100.0 * pace.energy / pace.capacity), pace.speed_cap, pace.acceleration]
	var effort := "Pushing" if pace.pushing else "Saving energy"
	if pace.freshness < 1.0:
		effort = "Fatigued"
	elif pace.spurt >= 0.5:
		effort = "Final spurt"
	_effort.text = effort


func update_countdown(gate: int, count: int, seconds: int) -> void:
	_summary.text = tr("Starting gate %d / %d") % [gate, count]
	_cue.text = str(seconds)


func update_race(lap: int, rank: int, count: int, elapsed: float, cue: String) -> void:
	_summary.text = tr("Lap %d / 2     Position %d / %d") % [lap, rank, count]
	_time.text = Result.clock(elapsed)
	_cue.text = cue


func wait_for_field(rank: int, seconds: float, finished: int, count: int) -> void:
	_summary.text = tr("Finished  ·  Position %d / %d") % [rank, count]
	_time.text = Result.clock(seconds)
	_cue.text = ""
	_waiting.text = tr("%d / %d runners finished") % [finished, count]
	_waiting.show()


func show_results(order: Array[Result]) -> void:
	_live.hide()
	_finish.reveal(order)
