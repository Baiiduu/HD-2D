class_name Farming
extends Node3D

signal interaction_feedback(message: String, success: bool)

@export var terrain: Terrain
@export var player: Player
@export var loadout: LoadoutUI
@export var dressing: Node3D
## 存档中的地图标识；已有种植记录通过此名称找回。
@export var world_id := "homestead"
@export_group("种植操作")
@export var enabled := true
@export var use_button: MouseButton = MOUSE_BUTTON_LEFT
## 持有锄头时，使用此按键将耕地恢复为原草地。
@export var restore_button: MouseButton = MOUSE_BUTTON_RIGHT
## 当前尚未进入作物生长阶段，取消播种默认退回种子。
@export var refund_seed_on_restore := true
## 人物到目标格中心的水平距离，米。
@export_range(0.8, 4.0, 0.1) var reach := 2.8
@export_range(0.1, 0.6, 0.05) var height_tolerance := 0.35
@export_range(0.0, 1.0, 0.05) var action_interval := 0.35
@export var only_grass := true
## 使用 Terrain.paint_palette 中的固定画笔编号，默认是现有细颗粒泥土。
@export_range(1, 255, 1) var soil_paint_id := 3
@export_group("耕地显示")
## 浇水后相对于干土的颜色倍率；越低越深。
@export_range(0.3, 1.0, 0.05) var watered_darkening := 0.68
@export_range(0.2, 1.0, 0.05) var watered_roughness := 0.72
@export var seed_texture: Texture2D = preload("res://assets/meowa/farming/seed.png")
@export_range(0.08, 0.4, 0.02) var seed_size := 0.24
@export var valid_color := Color(0.9, 0.77, 0.47, 0.8)
@export var invalid_color := Color(0.67, 0.32, 0.22, 0.7)

var state: LoadoutState
var _base_data: TerrainData
var _plots_snapshot: Dictionary = {}
var _applied: Array[Vector2i] = []
var _mask: ImageTexture
var _cursor := MeshInstance3D.new()
var _cursor_material := ShaderMaterial.new()
var _seeds := MultiMeshInstance3D.new()
var _cooldown := 0.0
var _target := Vector2i.ZERO
var _has_target := false

func _ready() -> void:
	if not terrain or not terrain.data or not player or not loadout or not loadout.state:
		push_error("种植系统缺少地形、人物或背包连接。")
		set_process(false)
		set_process_unhandled_input(false)
		return
	state = loadout.state
	_base_data = terrain.data
	# 修改运行时副本，正式地编及其他地图继续引用原资源。
	terrain.data = terrain.data.duplicate(true)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * terrain.data.cell_size * 0.97
	_cursor.mesh = plane
	_cursor.name = "TargetCell"
	_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cursor_material.shader = preload("res://shaders/farming_target.gdshader")
	_cursor.material_override = _cursor_material
	add_child(_cursor)
	_seeds.name = "SownSeeds"
	_seeds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_seeds)
	state.changed.connect(_sync_visuals)
	if dressing and dressing.has_signal("dressing_rebuilt"):
		dressing.connect("dressing_rebuilt", _bind_dressing)
	_sync_visuals(true)

func active_item() -> ItemDefinition:
	if not state: return null
	return state.catalog.get_item(state.get_quick_slots()[state.active_quick_slot])

func _blocked() -> bool:
	if loadout and loadout.wave_session and not loadout.wave_session.management_allowed(): return true
	return not enabled or get_tree().paused or get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if terrain.top_material:
		terrain.top_material.set_shader_parameter("farming_wet_darkening", watered_darkening)
		terrain.top_material.set_shader_parameter("farming_wet_roughness", watered_roughness)
	if _blocked():
		_cursor.hide()
		return
	var entry := active_item()
	var usable := entry != null and entry.farm_action != ItemDefinition.FarmAction.NONE
	_cursor.visible = false
	if usable:
		_pick(get_viewport().get_mouse_position())
		var view := get_interaction_state()
		if _has_target:
			_cursor.show()
			_cursor.global_position = cell_position(_target) + Vector3.UP * 0.018
			_cursor_material.set_shader_parameter("target_color", valid_color if view.target_valid else invalid_color)

func _action_name(action: int) -> String:
	return {ItemDefinition.FarmAction.HOE: "锄地", ItemDefinition.FarmAction.SEED: "播种", ItemDefinition.FarmAction.WATER: "浇水"}.get(action, "使用")

## 提示界面读取当前目标与真实操作校验，不修改地块或库存。
func get_interaction_state() -> Dictionary:
	var entry := active_item()
	if _blocked() or not entry or entry.farm_action == ItemDefinition.FarmAction.NONE:
		return {"visible": false}
	var plot := state.get_farm_plot(world_id, _target) if _has_target else {}
	var primary_error := action_error(_target) if _has_target else "指向身边的平整地面"
	var can_restore := _has_target and entry.farm_action == ItemDefinition.FarmAction.HOE and not plot.is_empty()
	var restore_error := action_error(_target, true) if can_restore else ""
	var position := cell_position(_target) if _has_target else Vector3.ZERO
	var offset := position - player.global_position
	return {
		"visible": true, "item": entry, "quantity": state.get_quantity(entry.id),
		"has_target": _has_target, "position": position,
		"in_reach": _has_target and Vector2(offset.x, offset.z).length() <= reach and absf(offset.y) <= height_tolerance,
		"cooldown": _cooldown > 0.0,
		"tilled": not plot.is_empty(), "sown": not plot.get("seed", "").is_empty(),
		"watered": plot.get("watered", false), "action": _action_name(entry.farm_action),
		"primary_error": primary_error, "can_restore": can_restore, "restore_error": restore_error,
		"target_valid": _has_target and (primary_error.is_empty() or (can_restore and restore_error.is_empty()))
	}

func _unhandled_input(event: InputEvent) -> void:
	if _blocked() or not event is InputEventMouseButton or not event.pressed: return
	var entry := active_item()
	if not entry or entry.farm_action == ItemDefinition.FarmAction.NONE: return
	var restoring: bool = event.button_index == restore_button and entry.farm_action == ItemDefinition.FarmAction.HOE
	if event.button_index != use_button and not restoring: return
	_pick(event.position)
	if _has_target: use_at(_target, restoring)
	else: _feedback("请点击身边的平整地面", false)
	get_viewport().set_input_as_handled()

func _pick(screen: Vector2) -> void:
	_has_target = false
	var camera := get_viewport().get_camera_3d()
	if not camera: return
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 100.0, player.collision_mask, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < 0.95: return
	var node: Node = hit.collider
	while node and node != terrain: node = node.get_parent()
	if node != terrain: return
	_target = terrain.data.world_to_cell(terrain.to_local(hit.position))
	_has_target = terrain.data.has_cell(_target)

func cell_position(cell: Vector2i) -> Vector3:
	return terrain.to_global(Vector3(cell.x * terrain.data.cell_size, terrain.data.get_level(cell) * terrain.data.layer_height, cell.y * terrain.data.cell_size))

func _is_grass(cell: Vector2i) -> bool:
	var index := _base_data._index(cell)
	var paint := _base_data.paint_at_index(index)
	if paint != 0:
		var brush := terrain.paint_palette.brush_for_id(paint) if terrain.paint_palette else null
		return brush != null and brush.is_grass
	return _base_data.get_biome(cell) == TerrainData.Biome.WILD

func _surface_error(cell: Vector2i) -> String:
	if not _base_data.has_cell(cell): return "超出地图范围"
	for flag in [TerrainData.OVERLAY_PATH, TerrainData.OVERLAY_DIRT, TerrainData.OVERLAY_WATER, TerrainData.OVERLAY_BRIDGE, TerrainData.OVERLAY_RAMP]:
		if _base_data.has_overlay(cell, flag): return "道路、坡道和水面不能耕作"
	if only_grass and not _is_grass(cell): return "只能在草地上锄地"
	return ""

func action_error(cell: Vector2i, restoring := false) -> String:
	if _blocked(): return "先关闭界面或恢复游戏"
	if loadout._save_blocked: return "存档未读取，暂不能修改地块"
	var entry := active_item()
	if not entry or state.get_quantity(entry.id) <= 0: return "请先选择工具或种子"
	if entry.farm_action == ItemDefinition.FarmAction.NONE: return "此物品暂不能用于种植"
	var problem := _surface_error(cell)
	if not problem.is_empty(): return problem
	var brush := terrain.paint_palette.brush_for_id(soil_paint_id) if terrain.paint_palette else null
	if not brush or not brush.validation_error().is_empty() or brush.is_grass: return "请配置有效的泥土画笔"
	var center := cell_position(cell)
	if Vector2(center.x - player.global_position.x, center.z - player.global_position.z).length() > reach: return "距离太远，走近一点"
	if absf(center.y - player.global_position.y) > height_tolerance: return "需要站在同一层地面"
	if not player.is_on_floor() or (player._blink and player._blink.active): return "先落地并完成当前动作"
	if not _clear_footprint(cell): return "地块被建筑或物体占用"
	if not _line_of_sight(center): return "前方有障碍物"
	if _cooldown > 0.0: return "稍等一下"
	var plot := state.get_farm_plot(world_id, cell)
	if restoring:
		if entry.farm_action != ItemDefinition.FarmAction.HOE: return "请用锄头恢复草地"
		return "这格没有耕地" if plot.is_empty() else ""
	if entry.farm_action == ItemDefinition.FarmAction.HOE:
		return "已开垦，可用右键恢复草地" if not plot.is_empty() else ""
	if plot.is_empty(): return "先用锄头开垦草地"
	if entry.farm_action == ItemDefinition.FarmAction.SEED and not plot.seed.is_empty(): return "这格已经播种"
	if entry.farm_action == ItemDefinition.FarmAction.WATER and plot.watered: return "这格已经浇水"
	return ""

func _clear_footprint(cell: Vector2i) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(terrain.data.cell_size * 0.96, 0.45, terrain.data.cell_size * 0.96)
	query.shape = box
	query.transform.origin = cell_position(cell) + Vector3.UP * 0.24
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid(), terrain._generated.get_node("Body").get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _line_of_sight(center: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 0.65, center + Vector3.UP * 0.08, player.collision_mask, [player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func use_at(cell: Vector2i, restoring := false) -> bool:
	var problem := action_error(cell, restoring)
	if not problem.is_empty():
		_feedback(problem, false)
		return false
	var entry := active_item()
	var success := false
	if restoring:
		success = state.restore_farm_plot(world_id, cell, refund_seed_on_restore)
	else:
		match entry.farm_action:
			ItemDefinition.FarmAction.HOE: success = state.till_farm_plot(world_id, cell)
			ItemDefinition.FarmAction.SEED: success = state.plant_farm_plot(world_id, cell, entry.id)
			ItemDefinition.FarmAction.WATER: success = state.water_farm_plot(world_id, cell)
	if success: _cooldown = action_interval
	_feedback(("恢复草地" if restoring else _action_name(entry.farm_action)) + ("完成" if success else "未成功"), success)
	return success

func _feedback(text: String, success: bool) -> void:
	loadout._audio.play(&"confirm" if success else &"error")
	interaction_feedback.emit(text, success)

func _sync_visuals(force := false) -> void:
	var plots := state.get_farm_plots(world_id)
	if not force and plots == _plots_snapshot: return
	_plots_snapshot = plots
	for cell in _applied: terrain.data.set_paint_at_index(terrain.data._index(cell), _base_data.paint_at_index(_base_data._index(cell)))
	_applied.clear()
	var image := Image.create_empty(terrain.data.size.x, terrain.data.size.y, false, Image.FORMAT_RGBA8)
	var planted: Array[Vector2i] = []
	for key in plots:
		var parts: PackedStringArray = key.split(",")
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		if not _surface_error(cell).is_empty(): continue
		_applied.append(cell)
		terrain.data.set_paint_at_index(terrain.data._index(cell), soil_paint_id)
		var point := cell - terrain.data.origin
		image.set_pixel(point.x, point.y, Color(1.0, float(plots[key].watered), 0.0, 1.0))
		if not plots[key].seed.is_empty(): planted.append(cell)
	if _mask: _mask.update(image)
	else: _mask = ImageTexture.create_from_image(image)
	terrain.refresh_surface()
	if terrain.top_material:
		terrain.top_material.set_shader_parameter("farming_enabled", true)
		RenderingServer.material_set_param(terrain.top_material.get_rid(), "farming_map", _mask.get_rid())
	_bind_dressing()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var plane := PlaneMesh.new()
	plane.size = Vector2(seed_size, seed_size * 0.66)
	var material := StandardMaterial3D.new()
	material.albedo_texture = seed_texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 1.0
	plane.material = material
	multimesh.mesh = plane
	multimesh.instance_count = planted.size()
	for index in planted.size():
		var position := _seeds.to_local(cell_position(planted[index]) + Vector3.UP * 0.025)
		var angle := float((planted[index].x * 917 + planted[index].y * 137) % 11) * 0.6
		multimesh.set_instance_transform(index, Transform3D(Basis(Vector3.UP, angle), position))
	_seeds.multimesh = multimesh

func _bind_dressing() -> void:
	if not dressing or not dressing.has_method("set_farming_mask") or not _mask: return
	var bounds := terrain.data.get_world_rect()
	var origin := terrain.to_global(Vector3(bounds.position.x, 0.0, bounds.position.y))
	dressing.call("set_farming_mask", _mask, Vector4(origin.x, origin.z, bounds.size.x, bounds.size.y))
