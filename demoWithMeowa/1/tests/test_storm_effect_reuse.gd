extends SceneTree
const LEGACY := preload("res://tests/fixtures/legacy_storm_effect.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func piece(node: MeshInstance3D, names: Array) -> Array:
	var result: Array = [node.visible]
	if not node.visible: return result
	result.append(node.global_transform)
	for key in names: result.append(node.get_instance_shader_parameter(key))
	return result

func state(effect: Node3D) -> Array:
	var result: Array = [effect._bolts.size(),effect._patches.size(),effect.is_processing()]
	for bolt in effect._bolts:
		var parts := []
		for node in bolt.parts: parts.append(piece(node,["source_rect","phase","show_spine","intensity"]))
		result.append([bolt.age,parts,piece(bolt.head,["intensity"])])
	for patch in effect._patches: result.append(piece(patch.mesh,["phase","frame_rect","progress","intensity"]))
	return result

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var current: RicochetStormEffect = load("res://scenes/combat/ricochet_storm_effect_world.tscn").instantiate()
	var old := LEGACY.new()
	for field in ["arc_texture","head_texture","impact_frames","pixel_size","arc_duration","reveal_seconds","impact_duration","sky_height","impact_height","effect_energy","arc_energy_multiplier","effect_opacity","patch_enabled","patch_duration","patch_opacity","patch_height"]: old.set(field,current.get(field))
	world.add_child(current)
	world.add_child(old)
	for step in 48:
		if step == 16:
			current.effect_opacity *= 0.7
			old.effect_opacity = current.effect_opacity
		if step == 25:
			current.stop()
			old.stop()
		if step % 4 == 0:
			for effect in [current,old]:
				effect.show_link(Vector3.ZERO,Vector3(1.5+step*0.1,0.4,0.1),0.8,step%3,1.0)
				effect.show_patch(PackedVector3Array([Vector3.ZERO,Vector3.RIGHT]))
		for effect in [current,old]: effect._process(0.016)
		check(state(current) == state(old),"雷弧、雷头、电涌逐帧参数与原实现一致，包括池复用、启停和热调")
	world.free()
	await process_frame
	print("Storm effect reuse: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
