extends SceneTree

## 战场生成不能改动小院台地或在普通加载时丢失手工绘制；参数变化必须扩大真实地形。
func _initialize() -> void:
	create_timer(10.0).timeout.connect(func(): quit(2))
	var area: BattleArea = load("res://scenes/world/battle_area.tscn").instantiate()
	# Exercise the retained continuous-map generator using its home prototype.
	# The formal world now stores only battle cells.
	var source: TerrainData = load("res://data/world/spawn_terrain.tres")
	var source_hash := FileAccess.get_sha256("res://data/world/world_terrain.tres")
	var edited := source.duplicate(true) as TerrainData
	var home_cell := Vector2i(-4, 2)
	edited.paints[edited._index(home_cell)] = 6
	var generated := area.make_terrain(edited)
	assert(generated.paint_at_index(generated._index(home_cell)) == 6, "Home paint survives arena rebuilding")
	var home: TerrainData = load("res://data/world/spawn_terrain.tres")
	for z in home.size.y:
		for x in home.size.x:
			var cell := home.origin + Vector2i(x, z)
			assert(generated.get_level(cell) == source.get_level(cell), "Home heights survive rebuilding")
			assert(generated.get_biome(cell) == source.get_biome(cell), "Home biomes survive rebuilding")
			if cell.y * generated.cell_size < 12.8:
				assert(generated.overlays[generated._index(cell)] == source.overlays[source._index(cell)], "Home paths and ramps stay intact")
	assert(source.heights == load("res://data/world/spawn_terrain.tres").heights)
	var original_bounds := generated.get_world_rect()
	area.core_size = Vector2(40, 36.8)
	area.scenery_margin = 32
	area.terrace_levels = 2
	area.ramp_width = 6.4
	var expanded := area.make_terrain(source)
	assert(expanded.get_world_rect().encloses(original_bounds), "Larger settings expand real terrain")
	var core := area.get_core_rect()
	for z in expanded.size.y:
		for x in expanded.size.x:
			var cell := expanded.origin + Vector2i(x, z)
			if core.has_point(Vector2(cell) * expanded.cell_size):
				assert(expanded.get_level(cell) == 0 and not expanded.has_overlay(cell, TerrainData.OVERLAY_RAMP), "Core stays flat with taller edge terraces")
	area.free()
	assert(FileAccess.get_sha256("res://data/world/world_terrain.tres") == source_hash, "Tests and normal setup do not save source data")
	print("PASS: protected home heights/biomes/paint/paths, real geometry parameter rebuild, flat core, no source writes")
	quit()
