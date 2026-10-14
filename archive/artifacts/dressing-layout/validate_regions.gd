extends "D:/Project/HD-2DMap/artifacts/dressing-layout/validate_controls.gd"

func inside(point: Vector3, region: GroundDressingRegion) -> bool:
	var local := region.to_local(dressing.to_global(point))
	return absf(local.x) <= region.area_size.x * 0.5 + 0.001 and absf(local.z) <= region.area_size.y * 0.5 + 0.001

func run_checks() -> void:
	root.size = Vector2i(1280, 800)
	scene = load("res://scenes/four_realms.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in 25:
		await physics_frame
	dressing = scene.get_node("World/GroundDressing")
	var spawn: GroundDressingRegion = dressing.get_node("SpawnGrass")
	var upper: GroundDressingRegion = dressing.get_node("UpperGrass")
	var original := {"position": upper.position, "size": upper.area_size, "rotation": upper.rotation, "density": upper.density_multiplier, "enabled": upper.enabled, "categories": upper.categories}
	var grass_density: float = dressing.grass_density
	var flower_density: float = dressing.flower_density
	var seed_value: int = dressing.scatter_seed
	var base := snapshot()
	check(base.size() > 0, "No plants generated in default regions")
	check(dressing.pebble_density == 0.0 and dressing.get_node("Layers/pebbles").get_child_count() == 0, "Default scene displays stones")
	for item in base:
		check(inside(item["point"], spawn) or inside(item["point"], upper), "Plant escaped default regions")
	check_surfaces(base)
	await capture("regions-random.png")
	spawn.enabled = false
	await settle()
	var upper_only := snapshot()
	check(upper_only.size() > 0 and upper_only.size() < base.size(), "Disabling a region did not remove only its plants")
	for item in upper_only:
		check(inside(item["point"], upper), "Disabled region still generated plants")
	upper.position = Vector3(30.0, 0.0, 5.6)
	upper.area_size = Vector2(6.0, 4.0)
	upper.rotation.y = 0.35
	upper.categories = 1
	upper.grass_variants = 4
	await settle()
	var moved := snapshot()
	check(moved.size() > 0, "Moved and resized region is empty")
	for item in moved:
		check(inside(item["point"], upper), "Plant escaped a rotated region")
		check(item["texture"].ends_with("grass_03.png"), "Region category or resource selection ignored")
	check_surfaces(moved)
	upper.density_multiplier = 2.0
	await settle()
	check(snapshot().size() > moved.size(), "Local region density did not increase quantity")
	upper.enabled = false
	await settle()
	check(snapshot().is_empty(), "All disabled regions still generate plants")
	var clone: GroundDressingRegion = upper.duplicate()
	clone.name = "ExtraFlowers"
	clone.position = Vector3(10.0, 0.0, 5.0)
	clone.rotation = Vector3.ZERO
	clone.area_size = Vector2(4.0, 4.0)
	clone.categories = 2
	clone.density_multiplier = 1.0
	clone.enabled = true
	dressing.add_child(clone)
	clone.owner = scene
	await settle()
	var added := snapshot()
	check(added.size() > 0, "Adding a region did not refresh scatter")
	for item in added:
		check(inside(item["point"], clone) and item["texture"].contains("/flowers/"), "New region range or category ignored")
	clone.free()
	await settle()
	check(snapshot().is_empty(), "Deleting a region did not refresh scatter")
	spawn.enabled = true
	upper.position = original["position"]
	upper.area_size = original["size"]
	upper.rotation = original["rotation"]
	upper.density_multiplier = original["density"]
	upper.categories = original["categories"]
	upper.grass_variants = 63
	upper.enabled = original["enabled"]
	await settle()
	check(snapshot() == base, "Restoring regions did not reproduce the same random layout")
	dressing.scatter_seed += 1
	await settle()
	check(snapshot() != base, "Seed did not change the random layout")
	dressing.scatter_seed = seed_value
	dressing.grass_variants = 1
	dressing.flower_variants = 16
	await settle()
	var selected := snapshot()
	check(selected.size() == base.size(), "Resource selection changed quantity")
	for item in selected:
		check(item["texture"].ends_with("grass_01.png") or item["texture"].ends_with("flower_05.png"), "Unselected resource generated")
		check(base.any(func(before: Dictionary) -> bool: return before["point"].is_equal_approx(item["point"])), "Resource selection changed a point")
	await capture("regions-selected.png")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, "Could not serialize scatter settings")
	var restored: Node3D = packed.instantiate()
	var restored_dressing := restored.get_node("World/GroundDressing")
	check(restored_dressing.flower_variants == 16 and restored_dressing.get_node("UpperGrass").area_size == original["size"], "Serialized settings or regions lost")
	check(not restored_dressing.has_node("Layers"), "Generated batches were serialized")
	restored.free()
	dressing.grass_variants = 63
	dressing.flower_variants = 63
	dressing.grass_density = grass_density * 2.0
	dressing.flower_density = flower_density * 2.0
	await settle()
	var doubled := snapshot()
	check(doubled.size() > base.size(), "Increasing density did not add plants")
	check_surfaces(doubled)
	await capture("regions-dense.png")
	dressing.grass_density = 2.0
	await settle()
	var beyond_one := snapshot()
	check(beyond_one.size() > doubled.size(), "Density above 1 has no effect")
	check_surfaces(beyond_one)
	dressing.grass_density = grass_density
	dressing.flower_density = flower_density
	await settle()
	check(snapshot() == base, "Restoring defaults did not reproduce random layout")
	var report := {"default": base.size(), "upper_only": upper_only.size(), "moved_region": moved.size(), "added_region": added.size(), "double_density": doubled.size(), "grass_density_2": beyond_one.size(), "failures": failures}
	FileAccess.open(OUTPUT + "regions-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
