extends Node3D

const Preferences := preload("res://game/app/game-preferences.gd")
const Runner := preload("res://game/runner/runner.gd")
const RunnerScene := preload("res://game/runner/runner.tscn")
const Doors := preload("res://game/campus/campus-doors.gd")
const Walkways := preload("res://game/campus/academy-walkways.gd")
const Roster := preload("res://game/ui/character-roster.gd")

const LOAD_RADIUS := 28.0
const RELEASE_RADIUS := 36.0
const OUTFIT_OWNERS := {
	"meisho-doto-halloween": "meisho-doto",
	"mayano-top-gun-halloween": "mayano-top-gun",
	"super-creek-mummy": "super-creek",
	"special-week-trial": "special-week",
}


class Resident:
	var path: String
	var title: String
	var identity: String
	var actor: Runner
	var unavailable := false
	var place: int
	var current_exit := -1
	var previous_exit := -1
	var waypoint: int
	var step: int
	var location: Vector3
	var idle_left := 0.0
	var no_progress := 0.0
	var closest := INF


@export var player: Runner
@export var doors: Doors
var residents: Array[Resident] = []
var walkways := Walkways.new()
var _needs_walkways := false
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	process_physics_priority = -5
	var represented := {}
	for path in Roster.paths():
		var identity := _identity(path)
		if represented.has(identity):
			continue
		represented[identity] = true
		var resident := Resident.new()
		resident.path = path
		resident.title = Roster.display_name(path)
		resident.identity = identity
		residents.append(resident)
	_needs_walkways = not residents.is_empty()
	set_physics_process(_needs_walkways)


func _place_roster() -> void:
	walkways.build(doors, get_world_3d().direct_space_state)
	var starts: Array[int] = []
	var outdoor_count := mini(walkways.outdoor_starts.size(), ceili(residents.size() / 3.0))
	for index in outdoor_count:
		var slot := floori(float(index) * walkways.outdoor_starts.size() / outdoor_count)
		starts.append(walkways.outdoor_starts[slot])
	# Spread the remaining roster across the campus. A new visit picks
	# different characters for the same neighborhoods.
	var candidates: Array[int] = []
	for index in walkways.places.size():
		var place := walkways.places[index]
		if place.sheltered and not place.exits.is_empty():
			candidates.append(index)
	var indoor_count := residents.size() - starts.size()
	for index in indoor_count:
		var slot := floori(float(index) * (candidates.size() - 1) / maxi(1, indoor_count - 1))
		starts.append(candidates[slot])
	residents.shuffle()
	for index in residents.size():
		var resident := residents[index]
		resident.place = starts[index]
		resident.location = walkways.places[resident.place].position + Vector3.UP * 0.06
		resident.idle_left = _random.randf_range(0.0, 2.0)


func _identity(path: String) -> String:
	var slug := path.get_file().get_basename()
	return OUTFIT_OWNERS.get(slug, slug)


func _physics_process(delta: float) -> void:
	if _needs_walkways:
		_place_roster()
		_needs_walkways = false
	var player_id := _identity(player.active_character_path)
	var nearest: Resident
	var nearest_distance := LOAD_RADIUS
	for resident in residents:
		var excluded := player.competition or resident.unavailable or resident.identity == player_id
		if resident.actor != null:
			if excluded or player.global_position.distance_to(resident.actor.position) > RELEASE_RADIUS:
				resident.location = resident.actor.position
				remove_child(resident.actor)
				resident.actor.queue_free()
				resident.actor = null
			else:
				_walk(resident, delta)
		elif not excluded:
			var distance := player.global_position.distance_to(resident.location)
			if distance < nearest_distance:
				nearest = resident
				nearest_distance = distance
	if nearest != null:
		_spawn(nearest)


func _spawn(resident: Resident) -> void:
	var actor := RunnerScene.instantiate() as Runner
	actor.character_path = resident.path
	actor.computer_controlled = true
	actor.collision_layer = 4
	actor.set_collision_mask_value(2, true)
	actor.get_node("CameraArm/Camera3D").free()
	actor.position = resident.location
	add_child(actor)
	if actor.active_character_path != resident.path:
		resident.unavailable = true
		remove_child(actor)
		actor.queue_free()
		return
	resident.actor = actor
	var label := Label3D.new()
	label.text = resident.title
	label.visible = Preferences.show_npc_names
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.003
	label.position.y = 1.95
	label.visibility_range_end = 12.0
	actor.add_child(label)


func _choose_exit(resident: Resident) -> void:
	var exits := walkways.places[resident.place].exits.duplicate()
	if exits.size() > 1 and _random.randf() < 0.85:
		exits.erase(resident.previous_exit)
	if exits.is_empty():
		return
	_take_exit(resident, exits[_random.randi_range(0, exits.size() - 1)])


func _take_exit(resident: Resident, exit: int) -> void:
	resident.current_exit = exit
	var passage := walkways.passages[resident.current_exit]
	resident.step = 1 if passage.ends.x == resident.place else -1
	resident.waypoint = 1 if resident.step == 1 else passage.points.size() - 2
	resident.no_progress = 0.0
	resident.closest = INF


func _walk(resident: Resident, delta: float) -> void:
	var actor := resident.actor
	if resident.idle_left > 0.0:
		resident.idle_left -= delta
		actor.rival_direction = Vector3.ZERO
		return
	if resident.current_exit < 0:
		_choose_exit(resident)
		if resident.current_exit < 0:
			return

	var passage := walkways.passages[resident.current_exit]
	var offset := passage.points[resident.waypoint] - actor.position
	var direction := offset.slide(Vector3.UP)
	var distance := direction.length()
	if distance < 0.105 and absf(offset.y) < 0.30:
		resident.waypoint += resident.step
		resident.closest = INF
		resident.no_progress = 0.0
		if resident.waypoint < 0 or resident.waypoint >= passage.points.size():
			resident.place = passage.ends.x if resident.step < 0 else passage.ends.y
			resident.previous_exit = resident.current_exit
			resident.current_exit = -1
			resident.idle_left = _random.randf_range(0.2, 2.8)
		actor.rival_direction = Vector3.ZERO
		return

	if distance < resident.closest - 0.04:
		resident.closest = distance
		resident.no_progress = 0.0
	else:
		resident.no_progress += delta
	var beside_player := actor.position.distance_squared_to(player.position) < 0.68 * 0.68
	if resident.no_progress > (0.8 if beside_player else 5.0):
		# Yield quickly to the player in a narrow passage.
		resident.waypoint -= resident.step
		resident.step = -resident.step
		resident.closest = INF
		resident.no_progress = 0.0
		actor.rival_direction = Vector3.ZERO
		return

	var door := passage.door
	if door != null and actor.position.distance_squared_to(door.position) < 2.25:
		door.wants_open = true
		if door.opening < 0.99:
			actor.rival_direction = Vector3.ZERO
			return
	actor.rival_direction = direction.normalized() * clampf(0.42 + distance * 1.7, 0.5, 1.0)
