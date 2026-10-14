extends SceneTree

## 区域检索优化必须保留负坐标、旋转缩放区域和道路避让的几何面积。
func _initialize() -> void:
	create_timer(10.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func area(dressing: Node3D, region: GroundDressingRegion) -> float:
	var triangles: Array = dressing._region_surface(region)
	return float(triangles.back().cumulative) if not triangles.is_empty() else 0.0

func run() -> void:
	var ground := Terrain.new()
	ground.data = TerrainData.new()
	ground.data.size = Vector2i.ZERO
	ground.data.resize(Vector2i(-10, -10), Vector2i(20, 20))
	ground.data.biomes.fill(TerrainData.Biome.WILD)
	root.add_child(ground)
	var dressing: Node3D = load("res://scripts/world/ground_dressing.gd").new()
	dressing.terrain = ground
	dressing.grass_density = 0.0
	dressing.flower_density = 0.0
	dressing.pebble_density = 0.0
	root.add_child(dressing)
	var region := GroundDressingRegion.new()
	dressing.add_child(region)
	region.position = Vector3(-3.2, 0, 4.8)
	region.area_size = Vector2(6.4, 3.2)
	assert(is_equal_approx(area(dressing, region), 20.48), "Negative map coordinates preserve region area")
	region.rotation.y = deg_to_rad(37.0)
	region.scale = Vector3(1.25, 1.0, 0.75)
	assert(absf(area(dressing, region) - 19.2) < 0.001, "Rotated and scaled regions preserve physical area")
	region.position = Vector3(100, 0, -100)
	assert(area(dressing, region) == 0.0, "Regions outside terrain produce no placements")
	region.position = Vector3(-16, 0, 0)
	region.rotation = Vector3.ZERO
	region.scale = Vector3.ONE
	region.area_size = Vector2(3.2, 3.2)
	assert(absf(area(dressing, region) - 6.24) < 0.001, "Partially overlapping regions preserve the terrain-edge setback")
	region.position = Vector3.ZERO
	region.area_size = Vector2(0.2, 0.2)
	region.rotation.y = deg_to_rad(31.0)
	assert(absf(area(dressing, region) - 0.04) < 0.0001, "Regions smaller than one cell still generate their full area")
	ground.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_PATH, true)
	assert(area(dressing, region) == 0.0, "Roads remain excluded from vegetation")
	dressing.free()
	ground.free()
	await process_frame
	print("PASS: 6 region checks: negative origin, rotation/scale, outside terrain, partial overlap, subcell area, road exclusion")
	quit()
