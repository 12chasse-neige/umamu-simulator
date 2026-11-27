extends Node3D

const Music := preload("res://game/app/background-music.gd")
const Preferences := preload("res://game/app/game-preferences.gd")
const Course := preload("res://game/race/race-course.gd")
const Progress := preload("res://game/race/race-progress.gd")
const Runner := preload("res://game/runner/runner.gd")
const RunnerScene := preload("res://game/runner/runner.tscn")
const Field := preload("res://game/race/race-field.gd")
const EntryMenu := preload("res://game/race/race-entry-menu.gd")
const HUD := preload("res://game/race/race-hud.gd")
const Roster := preload("res://game/ui/character-roster.gd")
const Lineup := preload("res://game/race/race-lineup.gd")
const Result := preload("res://game/race/race-result.gd")
# Gate numbers increase from the inside line toward the outside rail.
const GRID := [-11.9, -10.0, -8.1, -6.2, -4.3, -2.4, -0.5, 0.8, 2.55]
const Pace := preload("res://game/race/race-pace.gd")
const Profile := preload("res://game/race/race-profile.gd")
const RIVAL_CLEAR_DISTANCE := 6.0
const START_OFFSET := -3.7
const RUNNER_LAYER := 2

enum Phase { IDLE, COUNTDOWN, RACING, FINISHED }


class Entrant:
	var runner: Runner
	var title: String
	var gate: int
	var progress := Progress.new(START_OFFSET)
	var target_offset: float
	var course_position: Vector2
	var last_valid: Vector3


@export var player: Runner
@export var campus: Node3D

var phase := Phase.IDLE
var _entrants: Array[Entrant] = []
var _player: Entrant
var _field: Field
var _menu: EntryMenu
var _hud: HUD
var _countdown := 0.0
var _elapsed := 0.0
var _cue_time := 0.0
var _mudland := false
var _opening_strategy := Pace.Strategy.PACE
var _player_mask := 0
var _selected_rivals: Array[Lineup.Rival] = []

@onready var _music := get_node("/root/BackgroundMusic") as Music


func _ready() -> void:
	process_physics_priority = -10
	_field = Field.new()
	add_child(_field)
	_field.install(campus)
	_menu = EntryMenu.new()
	add_child(_menu)
	_menu.build(_start, _solo)
	_menu.visibility_changed.connect(_entry_visibility_changed)


func _entry_visibility_changed() -> void:
	if _menu.visible:
		_music.play_race_cue(Music.RaceCue.ENTRY)
	else:
		_resume_music_if_idle.call_deferred()


func _resume_music_if_idle() -> void:
	if phase == Phase.IDLE and not _menu.visible:
		_music.resume_ambient()


func _start(mudland: bool, rivals: Array[Lineup.Rival] = [], opening_strategy := Pace.Strategy.PACE) -> void:
	_start_at_gate(mudland, rivals, opening_strategy, randi_range(1, GRID.size()))


func _start_at_gate(mudland: bool, rivals: Array[Lineup.Rival], opening_strategy: Pace.Strategy, player_gate: int) -> void:
	if rivals.size() != Lineup.RIVALS:
		rivals = Lineup.available(player.active_character_path).slice(0, Lineup.RIVALS)
	_selected_rivals = rivals.duplicate()
	_mudland = mudland
	_countdown = 3.0
	_elapsed = 0.0
	_cue_time = 0.0
	phase = Phase.COUNTDOWN
	_player_mask = player.collision_mask
	_player = _place(player, player_gate)
	_player.title = Roster.display_name(player.active_character_path)
	_opening_strategy = opening_strategy
	var profile := Profile.new(player.active_character_path, "Runner proxy")
	player.race_pace = Pace.new(profile, opening_strategy, mudland)
	var field_styles: Array[int] = [0, 0, 0, 0]
	field_styles[opening_strategy] += 1
	player.mouse_motion = Vector2.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.race_hint.hide()
	_field.set_surface(mudland)
	for index in range(1, rivals.size() + 1):
		var gate := index if index < player_gate else index + 1
		var choice := rivals[index - 1]
		var rival := RunnerScene.instantiate() as Runner
		rival.name = "Rival%d" % index
		rival.character_path = ""
		rival.computer_controlled = true
		rival.get_node("CameraArm/Camera3D").free()
		rival.position = _grid_point(gate)
		add_child(rival)
		var entrant := _place(rival, gate)
		var loaded := choice.path.is_empty() or rival.change_character(choice.path)
		entrant.title = choice.display_title() if loaded else tr("Academy runner %d") % index
		var rival_profile := Profile.new(choice.path, choice.title)
		var strategy := rival_profile.preferred_style(field_styles) as Pace.Strategy
		field_styles[strategy] += 1
		rival.race_pace = Pace.new(rival_profile, strategy, mudland)
		_label_rival(entrant, index)

	_hud = HUD.new()
	add_child(_hud)
	_hud.build("Mudland" if mudland else "Grassland", _retry, _leave)
	_hud.update_pace(player.race_pace)
	_hud.update_countdown(player_gate, GRID.size(), ceili(_countdown))
	_music.play_race_cue(Music.RaceCue.START)


func _solo() -> void:
	player.race.update(player.global_position, true, 0.0)


func _physics_process(delta: float) -> void:
	match phase:
		Phase.IDLE:
			if not player.race.active() and player.race.at_start(player.global_position) 					and Input.is_action_just_pressed(&"race"):
				player.mouse_motion = Vector2.ZERO
				_menu.open(player.active_character_path)
		Phase.COUNTDOWN:
			_countdown = maxf(_countdown - delta, 0.0)
			if _countdown > 0.001:
				_hud.update_countdown(_player.gate, GRID.size(), ceili(_countdown))
			else:
				phase = Phase.RACING
				_music.play_race_cue(Music.RaceCue.RUN)
				for entrant in _entrants:
					entrant.runner.movement_locked = false
		Phase.RACING:
			_update_race(delta)
		Phase.FINISHED:
			pass


func _update_race(delta: float) -> void:
	var finished := 0
	_elapsed += delta
	_cue_time = maxf(0.0, _cue_time - delta)
	for entrant in _entrants:
		var runner := entrant.runner
		if entrant.progress.finish_time >= 0.0:
			finished += 1
			if runner.computer_controlled and not runner.movement_locked:
				entrant.course_position = Course.project(runner.global_position)
				if wrapf(entrant.course_position.x, -Course.LAP * 0.5, Course.LAP * 0.5) >= RIVAL_CLEAR_DISTANCE:
					runner.movement_locked = true
			continue
		var point := Course.project(runner.global_position)
		var legal := Course.contains_offset(point.y) and absf(runner.global_position.y) < 0.8
		if legal and entrant.progress.advance(point.x, _elapsed, delta):
			if entrant.progress.finish_time >= 0.0:
				finished += 1
			entrant.last_valid = runner.global_position
			entrant.course_position = point
		else:
			runner._recover_at(entrant.last_valid)
			if entrant == _player:
				_cue_time = 0.9

	var leader := minf(_entrants[0].progress.distance, Course.DISTANCE)
	for entrant in _entrants:
		leader = maxf(leader, minf(entrant.progress.distance, Course.DISTANCE))
	for entrant in _entrants:
		if entrant.progress.finish_time >= 0.0:
			continue
		var runner := entrant.runner
		var actual := runner.get_real_velocity().slide(Vector3.UP).length()
		var pace := runner.race_pace
		var gap := leader - entrant.progress.distance
		pace.spend(actual, delta)
		pace.update_limits(entrant.progress.distance, gap, actual)
		if runner.computer_controlled:
			pace.pushing = pace.rival_should_push(entrant.progress.distance, gap)
	for index in range(1, _entrants.size()):
		var entrant := _entrants[index]
		if not entrant.runner.movement_locked:
			_steer_rival(entrant, delta)

	var rank := _rank()
	var lap := mini(Course.LAPS, _player.progress.completed_laps() + 1)
	var cue := "Go!" if _elapsed < 0.7 else ""
	if _cue_time > 0.0:
		cue = "Stay on track"
	if _player.progress.finish_time >= 0.0:
		player.movement_locked = true
		_hud.wait_for_field(rank, _player.progress.finish_time, finished, _entrants.size())
	else:
		_hud.update_pace(player.race_pace)
		_hud.update_race(lap, rank, _entrants.size(), _elapsed, cue)
	if finished == _entrants.size():
		phase = Phase.FINISHED
		for entrant in _entrants:
			entrant.runner.movement_locked = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_hud.show_results(_final_order())
		_music.play_race_cue(Music.RaceCue.RESULTS)


func _final_order() -> Array[Result]:
	var ordered := _entrants.duplicate()
	ordered.sort_custom(func(a: Entrant, b: Entrant) -> bool:
		if a.progress.finish_time == b.progress.finish_time:
			return _entrants.find(a) < _entrants.find(b)
		return a.progress.finish_time < b.progress.finish_time)
	var results: Array[Result] = []
	for entrant in ordered:
		results.append(Result.new(entrant.title, entrant.runner.active_character_path,
			entrant.progress.finish_time, entrant == _player))
	return results


func _steer_rival(entrant: Entrant, delta: float) -> void:
	var lateral := entrant.course_position.y
	var pace := entrant.runner.race_pace
	# Claim a short bend when clear. Rearward styles leave passing room as
	# the field forms, then contest the rail on their finishing run.
	var ideal := Course.INNER_EDGE + 0.9
	if pace.stage < Pace.Stage.FINAL:
		ideal += 0.38 * pace.strategy
	var toward_inside := move_toward(lateral, ideal, 2.7)
	var best_offset := entrant.target_offset
	var best_cost := INF
	for offset: float in [toward_inside, lateral, lateral - 1.4, lateral + 1.4]:
		offset = clampf(offset, Course.INNER_EDGE + 0.55, Course.HALF_WIDTH - 0.55)
		var cost := absf(offset - ideal) * 0.65 + absf(offset - entrant.target_offset) * 0.25
		for other in _entrants:
			if other == entrant:
				continue
			var ahead := wrapf(other.course_position.x - entrant.course_position.x, -Course.LAP * 0.5, Course.LAP * 0.5)
			if ahead > -0.65 and ahead < 4.2:
				var outward := Course.forward_at(other.course_position.x).cross(Vector3.UP)
				var expected := other.course_position.y + other.runner.velocity.dot(outward) * 0.32
				var space := absf(expected - offset)
				cost += (1.0 - smoothstep(0.55, 1.35, space)) * (1.0 - smoothstep(0.5, 4.2, ahead)) * 5.0
		if cost < best_cost:
			best_cost = cost
			best_offset = offset
	entrant.target_offset = move_toward(entrant.target_offset, best_offset, delta * 2.8)
	var target := Course.point_at(entrant.course_position.x + 2.6, entrant.target_offset)
	entrant.runner.rival_direction = (target - entrant.runner.global_position).slide(Vector3.UP).normalized()


func _rank() -> int:
	var rank := 1
	for index in range(1, _entrants.size()):
		var rival := _entrants[index].progress
		if rival.finish_time >= 0.0 and (_player.progress.finish_time < 0.0 				or rival.finish_time < _player.progress.finish_time):
			rank += 1
		elif _player.progress.finish_time < 0.0 and rival.distance > _player.progress.distance + 0.001:
			rank += 1
	return rank


func _grid_point(gate: int) -> Vector3:
	return Course.point_at(START_OFFSET, GRID[gate - 1]) + Vector3.UP * 0.06


func _place(runner: Runner, gate: int) -> Entrant:
	var entrant := Entrant.new()
	entrant.runner = runner
	entrant.gate = gate
	entrant.target_offset = GRID[gate - 1]
	entrant.last_valid = _grid_point(gate)
	entrant.course_position = Course.project(entrant.last_valid)
	runner._recover_at(entrant.last_valid)
	runner.competition = true
	runner.movement_locked = true
	runner.facing.rotation.y = PI * 0.5
	runner.camera_arm.rotation.y = -PI * 0.5
	runner.set_collision_mask_value(RUNNER_LAYER, true)
	runner.reset_physics_interpolation()
	_entrants.append(entrant)
	return entrant


func _label_rival(entrant: Entrant, index: int) -> void:
	var runner := entrant.runner
	var tag := Label3D.new()
	if runner.active_character_path.is_empty():
		var proxy_color := StandardMaterial3D.new()
		proxy_color.albedo_color = Color.from_hsv(fposmod(0.045 + 0.151 * index, 1.0), 0.43, 0.72)
		runner.model_proxy.material_override = proxy_color
	tag.text = "%s  ·  %s" % [entrant.title, tr(Pace.NAMES[runner.race_pace.strategy])]
	tag.visible = Preferences.show_npc_names
	tag.position.y = 1.98
	tag.font_size = 32
	tag.pixel_size = 0.0036
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	runner.add_child(tag)


func _input(event: InputEvent) -> void:
	if phase != Phase.IDLE and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_leave()


func _retry() -> void:
	var mudland := _mudland
	var rivals := _selected_rivals.duplicate()
	_leave(false)
	_start(mudland, rivals, _opening_strategy)


func _leave(restore_music := true) -> void:
	if restore_music:
		_music.resume_ambient()
	phase = Phase.IDLE
	for index in range(1, _entrants.size()):
		var rival := _entrants[index].runner
		remove_child(rival)
		rival.queue_free()
	_entrants.clear()
	_player = null
	_hud.hide()
	_hud.queue_free()
	_hud = null
	player.competition = false
	player.movement_locked = false
	player.race_pace = null
	player.collision_mask = _player_mask
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
