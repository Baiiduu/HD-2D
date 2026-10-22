extends SceneTree

func _initialize() -> void:
	run_check.call_deferred()

func run_check() -> void:
	var scene: Node3D = load("res://scenes/four_realms.tscn").instantiate()
	root.add_child(scene)
	var dressing: Node3D = scene.get_node("World/GroundDressing")
	var region: GroundDressingRegion = dressing.get_node("UpperGrass")
	for frame in 5:
		await process_frame
	var baseline: int = dressing.instance_count
	var outline_exists := region.has_node("AreaOutline")
	region.enabled = false
	for frame in 3:
		await process_frame
	var disabled_count: int = dressing.instance_count
	region.enabled = true
	dressing.grass_density = 10.0
	dressing.flower_density = 10.0
	var start_time := Time.get_ticks_msec()
	for frame in 3:
		await process_frame
	var high_count: int = dressing.instance_count
	var ok := Engine.is_editor_hint() and outline_exists and disabled_count < baseline and high_count > baseline
	var report := {"editor_hint": Engine.is_editor_hint(), "outline": outline_exists, "default": baseline, "region_disabled": disabled_count, "density_10": high_count, "rebuild_ms": Time.get_ticks_msec() - start_time, "passed": ok}
	FileAccess.open("D:/Project/HD-2DMap/artifacts/dressing-layout/editor-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0 if ok else 1)
