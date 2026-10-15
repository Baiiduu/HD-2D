extends SceneTree

func _initialize() -> void:
	run_check.call_deferred()

func run_check() -> void:
	var scene: Node3D = load("res://scenes/four_realms.tscn").instantiate()
	root.add_child(scene)
	for frame in 5:
		await process_frame
	var dressing: Node3D = scene.get_node("World/GroundDressing")
	var baseline: int = dressing.instance_count
	dressing.editor_preview_enabled = false
	for frame in 3:
		await process_frame
	var unaffected: bool = dressing.instance_count == baseline and dressing.has_node("Layers")
	dressing.refresh_preview.call()
	for frame in 3:
		await process_frame
	var ok: bool = not Engine.is_editor_hint() and baseline > 0 and unaffected and dressing.instance_count == baseline and not dressing.get_node("UpperGrass").has_node("AreaOutline")
	print(JSON.stringify({"editor_hint": Engine.is_editor_hint(), "default": baseline, "editor_toggle_does_not_hide_game": unaffected, "passed": ok}))
	scene.free()
	await process_frame
	quit(0 if ok else 1)
