@tool
class_name BattleArea
extends Node3D

## 连续地图南侧战场。地形显式重建，运行时沿用保存数据，保留地表画笔的修改。
const HOME_DATA := preload("res://data/world/spawn_terrain.tres")
const DATA_PATH := "res://data/world/world_terrain.tres"

@export_group("地图连接")
@export var terrain: Terrain
@export var dressing: Node3D
@export var wave_controller: Node3D

@export_group("开场刷新（即时生效）")
## 相对开战入口的左右距离／向场内前进距离，米；只移动两处开场刷新区，不重建地形与地编。
@export var opening_spawn_offset := Vector2(6.4, 6.4):
	set(value):
		opening_spawn_offset = value.abs()
		if is_node_ready(): _apply_spawn_positions()

@export_group("场地布局（修改后重建）")
## 主战斗面的 X/Z 尺寸，米；中心为此节点的位置，内部保持同高。
@export var core_size := Vector2(32.0, 32.0)
## 核心外的宽阔绕行带，米。
@export_range(4.8, 16.0, 1.6, "suffix:m") var loop_width := 8.0
## 活动范围外的可见地形，米；给连续 QE 旋转留出地面背景。
@export_range(16.0, 40.0, 1.6, "suffix:m") var scenery_margin := 28.0
## 南侧道路向场地展开的宽度，米。
@export_range(3.2, 12.8, 1.6, "suffix:m") var entry_width := 6.4
## 两侧台地的高度层数；每层沿用 TerrainData.layer_height，默认 0.8 米。
@export_range(0, 2, 1) var terrace_levels := 1
## 台地坡道的通行宽度，米；至少三格，较大体型也可经过。
@export_range(4.8, 8.0, 1.6, "suffix:m") var ramp_width := 4.8
## 固定远侧台地轮廓和零散卵石的位置；不改变小院的花草随机种子。
@export var layout_seed := 13102026
## 已追加区域的地表不参与旧战区重建；坐标采用 Terrain 的 X/Z 米数。
@export var preserved_areas: Array[Rect2] = []
## 锁定旧区域的地编外框，避免地图向东扩展时改变小院与原战区的随机分布。
@export var dressing_bounds := Rect2()
@export_tool_button("重建战斗区地形", "Reload") var rebuild_button = rebuild_terrain
@export_tool_button("保存战斗区地形", "Save") var save_button = save_terrain

@export_group("花草密度（即时预览）")
## 乘以现有 GroundDressing 密度。中心只选择低矮草与前三种矮花。
@export_range(0.0, 1.0, 0.01) var core_density := 0.08:
	set(value): core_density = value; _queue_dressing()
## 绕行带的花草簇密度；沿用已有资源、风摆和受光。
@export_range(0.0, 1.0, 0.01) var edge_density := 0.38:
	set(value): edge_density = value; _queue_dressing()
## 远侧地形低密铺设，避免整张大地图堆满贴片。
@export_range(0.0, 1.0, 0.01) var scenery_density := 0.10:
	set(value): scenery_density = value; _queue_dressing()

var _regions: Array[GroundDressingRegion] = []
var _dressing_queued := false

func _ready() -> void:
	_apply_layout()

func _exit_tree() -> void:
	for region in _regions:
		if is_instance_valid(region): region.queue_free()
	_regions.clear()

func _center() -> Vector2:
	var point := terrain.to_local(global_position) if terrain and is_inside_tree() else position
	return Vector2(point.x, point.z)

func get_core_rect() -> Rect2:
	var size := core_size.abs().max(Vector2(16.0, 16.0))
	return Rect2(_center() - size * 0.5, size)

func get_activity_rect() -> Rect2:
	return get_core_rect().grow(loop_width)

func get_entry_position() -> Vector3:
	var rect := get_core_rect()
	return Vector3(rect.get_center().x, 0.0, rect.position.y - 3.2)

## 只在按钮或制作工具中执行；小院范围保留已有数据，战场范围重新生成。
func make_terrain(source: TerrainData) -> TerrainData:
	if is_instance_valid(get_parent()) and get_parent().get_meta("battle_only", false):
		var cropped: TerrainData = source.duplicate(true)
		var rect := get_activity_rect()
		var first := Vector2i((rect.position / source.cell_size + Vector2.ONE * 0.5).floor())
		var last := Vector2i((rect.end / source.cell_size - Vector2.ONE * 0.5).ceil())
		cropped.resize(first, last - first + Vector2i.ONE)
		return cropped
	var result := TerrainData.new()
	result.cell_size = source.cell_size
	result.layer_height = source.layer_height
	var home_rect := HOME_DATA.get_world_rect()
	var core := get_core_rect()
	var activity := get_activity_rect()
	var generated_bounds := activity.grow(scenery_margin).merge(home_rect)
	var bounds := generated_bounds
	if not preserved_areas.is_empty(): bounds = bounds.merge(source.get_world_rect())
	var first := Vector2i((bounds.position / result.cell_size + Vector2.ONE * 0.5).floor())
	var last := Vector2i((bounds.end / result.cell_size - Vector2.ONE * 0.5).ceil())
	result.size = Vector2i.ZERO
	result.resize(first, last - first + Vector2i.ONE)
	result.biomes.fill(TerrainData.Biome.WILD)
	var noise := FastNoiseLite.new()
	noise.seed = layout_seed
	noise.frequency = 0.045
	for z in result.size.y:
		for x in result.size.x:
			var cell := result.origin + Vector2i(x, z)
			var index := z * result.size.x + x
			var point := Vector2(cell) * result.cell_size
			var preserved := not generated_bounds.has_point(point) and not preserved_areas.is_empty()
			for rect in preserved_areas:
				if rect.has_point(point): preserved = true; break
			if HOME_DATA.has_cell(cell) or (preserved and source.has_cell(cell)):
				var existing := source if source.has_cell(cell) else HOME_DATA
				var local := cell - existing.origin
				var old_index := local.y * existing.size.x + local.x
				result.biomes[index] = existing.biomes[old_index]
				result.overlays[index] = existing.overlays[old_index]
				result.heights[index] = existing.heights[old_index]
				result.paints[index] = existing.paint_at_index(old_index)
			elif not activity.grow(6.4).has_point(point):
				# 外围采用顶面平整的自然台地，不把主场地改成连续起伏地面。
				var edge := maxf(absf(point.x - core.get_center().x) - activity.size.x * 0.5,
					point.y - activity.end.y)
				var ridge := edge + noise.get_noise_2d(point.x, point.y) * 8.0
				result.heights[index] = TerrainData.HEIGHT_OFFSET + (2 if ridge > 20.8 else 1 if ridge > 11.2 else 0)
	var ramp_extension := maxi(0, terrace_levels - 1) * result.cell_size * 2.0
	_stamp_terrace(result, Rect2(core.position.x - loop_width - ramp_extension, core.get_center().y - 3.2, 6.4, 9.6), 1)
	_stamp_terrace(result, Rect2(core.end.x + loop_width - 6.4 + ramp_extension, core.get_center().y + 8.0, 6.4, 9.6), -1)
	# 延续小院南侧道路，入口展开为一块卵石地面；沿用四角过渡图集。
	var entry := get_entry_position()
	var road := Rect2(entry.x - entry_width * 0.5, 12.8, entry_width, maxf(0.0, core.position.y - 12.8))
	_stamp_path(result, road)
	_stamp_path(result, Rect2(entry.x - 6.4, entry.z - 3.2, 12.8, 6.4))
	# 两侧绕行带上的稀疏卵石碎块：是现有铺装纹理，均不进入核心中心。
	for z in result.size.y:
		for x in result.size.x:
			var cell := result.origin + Vector2i(x, z)
			var point := Vector2(cell) * result.cell_size
			if activity.has_point(point) and not core.grow(1.6).has_point(point) and not home_rect.has_point(point):
				if absf(noise.get_noise_2d(point.x + 431.0, point.y - 179.0)) > 0.48:
					var index := z * result.size.x + x
					if result.overlays[index] == 0: result.paints[index] = 1
	return result

func _stamp_path(data: TerrainData, rect: Rect2) -> void:
	for z in data.size.y:
		for x in data.size.x:
			var cell := data.origin + Vector2i(x, z)
			if rect.has_point(Vector2(cell) * data.cell_size):
				data.overlays[z * data.size.x + x] |= TerrainData.OVERLAY_PATH

func _stamp_terrace(data: TerrainData, rect: Rect2, approach: int) -> void:
	if terrace_levels == 0: return
	var first := Vector2i((rect.position / data.cell_size).ceil())
	var last := Vector2i((rect.end / data.cell_size).ceil()) - Vector2i.ONE
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, z)
			if data.has_cell(cell): data.heights[data._index(cell)] = TerrainData.HEIGHT_OFFSET + terrace_levels
	var ramp_cells := maxi(3, roundi(ramp_width / data.cell_size))
	var middle := roundi(rect.get_center().y / data.cell_size)
	var side := last.x if approach > 0 else first.x
	for step in terrace_levels:
		for z in range(middle - ramp_cells / 2, middle - ramp_cells / 2 + ramp_cells):
			var cell := Vector2i(side + approach * (step * 2 + 1), z)
			if not data.has_cell(cell): continue
			data.heights[data._index(cell)] = TerrainData.HEIGHT_OFFSET + terrace_levels - step - 1
			data.overlays[data._index(cell)] = TerrainData.OVERLAY_RAMP | TerrainData.OVERLAY_PATH
			if step < terrace_levels - 1:
				cell.x += approach
				data.heights[data._index(cell)] = TerrainData.HEIGHT_OFFSET + terrace_levels - step - 1
				data.overlays[data._index(cell)] = TerrainData.OVERLAY_PATH

func rebuild_terrain() -> void:
	if not terrain or not terrain.data: return
	terrain.data = make_terrain(terrain.data)
	_apply_layout()
	var effects := get_parent().get_node_or_null("MapEffects")
	if effects: effects.connect_map()

func save_terrain() -> void:
	if not Engine.is_editor_hint() or not terrain or not terrain.data: return
	var uid := ResourceLoader.get_resource_uid(DATA_PATH)
	var error := ResourceSaver.save(terrain.data, DATA_PATH, ResourceSaver.FLAG_CHANGE_PATH)
	if error == OK and uid != ResourceUID.INVALID_ID: error = ResourceSaver.set_uid(DATA_PATH, uid)
	if error != OK: push_error("战斗区地形保存失败：" + error_string(error))

func _apply_layout() -> void:
	_apply_dressing()
	var entry := get_entry_position()
	if wave_controller:
		wave_controller.position = entry
		wave_controller.set("battle_area", get_activity_rect())
	var candidates := get_node_or_null("SpawnCandidates")
	if candidates:
		if wave_controller:
			wave_controller.set("spawn_zone_root", candidates)
			var excluded: Array[Rect2] = [Rect2(entry.x - 6.4, entry.z - 3.2, 12.8, 6.4)]
			wave_controller.set("spawn_excluded_areas", excluded)
	_apply_spawn_positions()

func _apply_spawn_positions() -> void:
	var candidates := get_node_or_null("SpawnCandidates")
	if not candidates: return
	var half := get_core_rect().size * 0.5
	var opening_z := -half.y - 3.2 + opening_spawn_offset.y
	var positions := [Vector2(-opening_spawn_offset.x, opening_z), Vector2(opening_spawn_offset.x, opening_z),
		Vector2(-half.x-loop_width+1.6, half.y-4.8), Vector2(half.x+loop_width-1.6, 1.6),
		Vector2(-9.6, half.y+loop_width-3.2), Vector2(9.6, half.y+loop_width-3.2)]
	for index in mini(candidates.get_child_count(), positions.size()):
		candidates.get_child(index).position = Vector3(positions[index].x, 0.0, positions[index].y)

func _queue_dressing() -> void:
	if not is_inside_tree() or _dressing_queued: return
	_dressing_queued = true
	_apply_dressing.call_deferred()

func _region(name_value: String, rect: Rect2, density: float, low_only := false) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0: return
	var region := GroundDressingRegion.new()
	region.name = "Battle" + name_value
	region.position = Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	region.area_size = rect.size
	region.density_multiplier = density
	if low_only:
		region.grass_variants = 3
		region.flower_variants = 7
	dressing.add_child(region)
	_regions.append(region)

func _apply_dressing() -> void:
	_dressing_queued = false
	if not dressing or not terrain or not terrain.data: return
	for region in _regions:
		if is_instance_valid(region): region.free()
	_regions.clear()
	var core := get_core_rect()
	var ring := get_activity_rect()
	if get_parent().get_meta("battle_only", false):
		_region("Core", core, core_density, true)
		_region("West", Rect2(ring.position, Vector2(loop_width, ring.size.y)), edge_density)
		_region("East", Rect2(core.end.x, ring.position.y, loop_width, ring.size.y), edge_density)
		_region("North", Rect2(core.position.x, ring.position.y, core.size.x, loop_width), edge_density)
		_region("South", Rect2(core.position.x, core.end.y, core.size.x, loop_width), edge_density)
		return
	var home := HOME_DATA.get_world_rect()
	var bounds := dressing_bounds if dressing_bounds.has_area() else terrain.data.get_world_rect()
	_region("Core", core, core_density, true)
	_region("West", Rect2(ring.position, Vector2(loop_width, ring.size.y)), edge_density)
	_region("East", Rect2(core.end.x, ring.position.y, loop_width, ring.size.y), edge_density)
	_region("North", Rect2(core.position.x, maxf(home.end.y, ring.position.y), core.size.x, maxf(0, core.position.y - maxf(home.end.y, ring.position.y))), edge_density)
	_region("South", Rect2(core.position.x, core.end.y, core.size.x, loop_width), edge_density)
	_region("SceneryWest", Rect2(bounds.position.x, home.end.y, ring.position.x - bounds.position.x, ring.end.y - home.end.y), scenery_density, true)
	_region("SceneryEast", Rect2(ring.end.x, home.end.y, bounds.end.x - ring.end.x, ring.end.y - home.end.y), scenery_density, true)
	_region("ScenerySouth", Rect2(bounds.position.x, ring.end.y, bounds.size.x, bounds.end.y - ring.end.y), scenery_density)
	_region("HomeWest", Rect2(bounds.position, Vector2(home.position.x - bounds.position.x, home.size.y)), scenery_density, true)
	_region("HomeEast", Rect2(home.end.x, bounds.position.y, bounds.end.x - home.end.x, home.size.y), scenery_density, true)
