@tool
class_name EnvironmentDynamics
extends Node3D

const HOME_DATA = preload("res://data/world/spawn_terrain.tres")

@export_group("环境动态")
## 只调节自然风与装饰光点；关闭恢复原自然风，新增战区光点隐藏。
@export var enabled := true:
	set(value): enabled = value; _queue_apply()
@export var editor_preview := true:
	set(value): editor_preview = value; _queue_apply()
## Style 改变时动态倍率的渐变时间，秒；不改变光照预设的切换方式。
@export_range(0.1, 6.0, 0.1, "suffix:s") var transition_seconds := 1.5
## 区域边界两侧的柔和过渡宽度，米。
@export_range(0.5, 12.0, 0.5, "suffix:m") var region_blend_width := 4.0:
	set(value): region_blend_width = value; _queue_apply()

@export_group("时段倍率（原始／黄金／细雨／夜晚）")
## X 原始、Y 黄金、Z 细雨、W 夜晚；乘以 Weather 的现有自然风力，不影响闪身。
@export var style_wind := Vector4(1.0, 0.7, 1.1, 0.5)
## 同一顺序；自然风时间推进倍率，渐变时不重置摆动相位。
@export var style_wind_tempo := Vector4(1.0, 0.8, 1.05, 0.65)
## 同一顺序；稳定选择可见光点的比例，0 全隐藏、1 全保留，雨天稀少。
@export var style_fireflies := Vector4(1.0, 0.18, 0.04, 1.0)
## 夜晚对原光点尺寸的轻微放大；1 保留原尺寸，不修改 ArtDirection 的基础设置。
@export_range(1.0, 3.0, 0.1) var night_firefly_size := 1.8

@export_group("区域倍率（家园／战区中心／绕行带／远侧）")
## X 家园、Y 战区中心、Z 绕行带、W 远侧地形；只影响自然风的摆幅。
@export var region_wind := Vector4(0.7, 0.55, 1.0, 0.9):
	set(value): region_wind = value; _queue_apply()
## 同一顺序；中心保持安静，外围允许较多光点。
@export var region_fireflies := Vector4(1.0, 0.05, 0.8, 0.45):
	set(value): region_fireflies = value; _queue_apply()
## 复用现有光点组件的三处战区外围光点；可独立关闭。
@export var battle_fireflies_enabled := true:
	set(value): battle_fireflies_enabled = value; _queue_apply()
## 战区光点相对当地地面的高度，米。
@export_range(0.2, 2.0, 0.1, "suffix:m") var battle_firefly_height := 0.9:
	set(value): battle_firefly_height = value; _queue_apply()

@export_group("场景连接")
@export var visual_sample: Node
@export var weather: Node
@export var dressing: Node3D
@export var terrain: Terrain
@export var battle_area: BattleArea
@export var art_direction: Node

var _plants: Array[ShaderMaterial] = []
var _lights: Array[ShaderMaterial] = []
var _current := Vector3.ONE
var _clock := 0.0
var _light_size := 1.0
var _queued := false
var _last_active := false

func _ready() -> void:
	process_priority = 45
	if dressing and not dressing.is_connected("dressing_rebuilt", _refresh_bindings):
		dressing.connect("dressing_rebuilt", _refresh_bindings)
	_current = _target()
	_light_size = _target_light_size()
	if weather: _clock = weather.get("_clock")
	_refresh_bindings()
	if art_direction: art_direction.call("_apply_fireflies")

func _active() -> bool:
	return enabled and (not Engine.is_editor_hint() or editor_preview)

func _target() -> Vector3:
	var index: int = clampi(int(visual_sample.get("style")), 0, 3) if visual_sample else 0
	return Vector3(maxf(style_wind[index], 0.0), maxf(style_wind_tempo[index], 0.0), clampf(style_fireflies[index], 0.0, 1.0))

func _target_light_size() -> float:
	return night_firefly_size if visual_sample and int(visual_sample.get("style")) == 3 else 1.0

func _queue_apply() -> void:
	if not is_inside_tree() or _queued: return
	_queued = true
	apply_settings.call_deferred()

func _refresh_bindings() -> void:
	_plants.clear()
	_lights.clear()
	if dressing:
		for batch in dressing.find_children("*", "MultiMeshInstance3D", true, false):
			var material: ShaderMaterial = batch.multimesh.mesh.material as ShaderMaterial
			if material and not _plants.has(material): _plants.append(material)
	var world := get_parent()
	for particles in get_tree().get_nodes_in_group("fireflies"):
		if not world.is_ancestor_of(particles): continue
		var mesh: Mesh = particles.draw_pass_1
		var material: ShaderMaterial = mesh.material as ShaderMaterial if mesh is PrimitiveMesh else null
		if material and not _lights.has(material): _lights.append(material)
	apply_settings()

func _world_rect(rect: Rect2) -> Rect2:
	var result := Rect2(Vector2(terrain.to_global(Vector3(rect.position.x, 0, rect.position.y)).x,
		terrain.to_global(Vector3(rect.position.x, 0, rect.position.y)).z), Vector2.ZERO)
	for point in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
		var world := terrain.to_global(Vector3(point.x, 0, point.y))
		result = result.expand(Vector2(world.x, world.z))
	return result

func _bounds(rect: Rect2) -> Vector4:
	return Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)

func apply_settings() -> void:
	_queued = false
	if not terrain or not battle_area: return
	var home := _bounds(_world_rect(HOME_DATA.get_world_rect()))
	var core := _bounds(_world_rect(battle_area.get_core_rect()))
	var activity := _bounds(_world_rect(battle_area.get_activity_rect()))
	for material in _plants + _lights:
		material.set_shader_parameter("ambient_home_bounds", home)
		material.set_shader_parameter("ambient_core_bounds", core)
		material.set_shader_parameter("ambient_activity_bounds", activity)
		material.set_shader_parameter("ambient_region_blend", region_blend_width)
	for material in _plants: material.set_shader_parameter("ambient_region_wind", region_wind.max(Vector4.ZERO))
	for material in _lights: material.set_shader_parameter("ambient_region_fireflies", region_fireflies.clamp(Vector4.ZERO, Vector4.ONE))
	_position_battle_lights()
	_write_values()

func _position_battle_lights() -> void:
	var rect := battle_area.get_core_rect()
	var center := rect.get_center()
	var offsets := [Vector2(rect.position.x - battle_area.loop_width * 0.5, center.y),
		Vector2(rect.end.x + battle_area.loop_width * 0.5, center.y),
		Vector2(center.x, rect.end.y + battle_area.loop_width * 0.5)]
	var lamps := get_children()
	for index in mini(lamps.size(), offsets.size()):
		var lamp := lamps[index] as GPUParticles3D
		if not lamp: continue
		var point: Vector2 = offsets[index]
		var cell := terrain.data.world_to_cell(Vector3(point.x, 0, point.y))
		var ground := terrain.data.get_level(cell) * terrain.data.layer_height if terrain.data.has_cell(cell) else 0.0
		lamp.global_position = terrain.to_global(Vector3(point.x, ground + battle_firefly_height, point.y))

func _write_values() -> void:
	var active := _active()
	for material in _plants:
		material.set_shader_parameter("ambient_dynamics_enabled", active)
		material.set_shader_parameter("ambient_wind_multiplier", _current.x)
		material.set_shader_parameter("ambient_wind_time", _clock)
	for material in _lights:
		material.set_shader_parameter("ambient_dynamics_enabled", active)
		material.set_shader_parameter("ambient_firefly_visibility", _current.z)
		material.set_shader_parameter("ambient_firefly_size", _light_size)
	_update_battle_visibility()
	_last_active = active

func _update_battle_visibility() -> void:
	var global_enabled := bool(art_direction.get("fireflies_enabled")) if art_direction else true
	for lamp in get_children():
		if lamp is GPUParticles3D:
			lamp.visible = _active() and battle_fireflies_enabled and global_enabled

func _process(delta: float) -> void:
	if not _active():
		if _last_active: _write_values()
		_update_battle_visibility()
		if weather: _clock = weather.get("_clock")
		return
	var weight := 1.0 - exp(-4.6 * delta / maxf(transition_seconds, 0.1))
	_current = _current.lerp(_target(), weight)
	_light_size = lerpf(_light_size, _target_light_size(), weight)
	_clock += delta * _current.y
	_write_values()

func _exit_tree() -> void:
	for material in _plants + _lights: material.set_shader_parameter("ambient_dynamics_enabled", false)
