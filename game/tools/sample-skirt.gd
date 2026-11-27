extends SceneTree

# Record body and garment skinning matrices during each playable ground gait.
const Runner := preload("res://game/runner/runner.gd")

func _initialize() -> void:
	call_deferred("_sample")


func _sample() -> void:
	var campus := preload("res://game/campus/campus-walk.tscn").instantiate()
	root.add_child(campus)
	var runner := campus.get_node("SpecialWeek") as Runner
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass a JSONL output path and optionally --rendered.")
		quit(1)
		return
	var rendered := args.has("--rendered")
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if runner.motion == null or runner.motion._skirt_clearance.panels.size() != 10 or file == null:
		push_error("Build and import the local detail skin before sampling garment poses.")
		quit(1)
		return
	for gait: StringName in Runner.Locomotion.GAITS:
		for key in [&"move_forward", &"walk", &"sprint"]:
			Input.action_release(key)
		runner._recover_at(Vector3(0, 0.08, 19))
		runner.camera_arm.rotation.y = 0.0
		for tick in 15:
			await physics_frame
		if gait == &"walk":
			Input.action_press(&"walk")
		if gait == &"run":
			Input.action_press(&"sprint")
		Input.action_press(&"move_forward")
		var period := runner.motion._clips.period(gait, 1.0)
		var warmup := 67 if rendered else 60
		for tick in warmup + ceili(60.0 * period):
			await physics_frame
			if tick < warmup:
				continue
			var driver := runner.motion
			if driver._clips.action != gait:
				push_error("Runner did not sustain %s on the sample course." % gait)
				quit(1)
				return
			var matrices := {}
			var rig_to_model := runner.facing.global_transform.affine_inverse() * driver.rig.global_transform
			for bone in driver.rig.get_bone_count():
				var skin := driver._pose(bone) * driver._global_rest[bone].affine_inverse()
				if rendered:
					skin = rig_to_model * driver.rig.get_bone_global_pose(bone) * driver.rig.get_bone_global_rest(bone).affine_inverse() * rig_to_model.affine_inverse()
				matrices[driver.rig.get_bone_name(bone)] = [
					skin.basis.x.x, skin.basis.y.x, skin.basis.z.x, skin.origin.x,
					skin.basis.x.y, skin.basis.y.y, skin.basis.z.y, skin.origin.y,
					skin.basis.x.z, skin.basis.y.z, skin.basis.z.z, skin.origin.z]
			file.store_line(JSON.stringify([gait, driver._phase, matrices]))
	file.close()
	quit()
