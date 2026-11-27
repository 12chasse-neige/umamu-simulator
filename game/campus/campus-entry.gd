extends Node3D

const Session := preload("res://game/app/game-session.gd")


func _enter_tree() -> void:
	$Campus/Grass.reserve_race_course = true
	if Session.character_selected:
		$SpecialWeek.character_path = Session.character_path


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F2 and not $SpecialWeek.competition:
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file("res://game/ui/meet-menu.tscn")
