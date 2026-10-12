@tool
extends Node3D

signal surfaces_rebuilt

const GROUND_SHADER := preload("res://shaders/homestead_ground.gdshader")
const WATER_SHADER := preload("res://shaders/homestead_water.gdshader")
const GRASS := preload("res://assets/meowa/homestead/grass.png")
const DIRT := preload("res://assets/meowa/homestead/soil.png")
const STONE := preload("res://assets/ground/cultivation/精致像素风灰青色青石板地面材质_长方形石板规则错缝铺设_细而清晰的深色砖缝_40699501/texture.png")
const WORLD_RECT := Rect2(-40.0, -35.0, 80.0, 70.0)
const POND_CENTER := Vector2(9.0, -3.0)
const POND_RADIUS := Vector2(3.4, 2.5)

@export_group("小院地表")
## 土路半宽，米；小院空地和石板门前地坪保持独立。
@export_range(0.4, 2.5, 0.05) var path_width := 1.05:
	set(value): path_width = value; _queue_rebuild()
## 院心活动空地的大小倍率；周围草花随边缘一起退让。
@export_range(0.6, 1.8, 0.05) var courtyard_scale := 1.0:
	set(value): courtyard_scale = value; _queue_rebuild()
## 每次重复材质在地面上的宽度，米。
@export_range(0.6, 4.0, 0.1) var texture_scale := 1.65:
	set(value): texture_scale = value; _apply_material()
## 草地色块的细微明暗变化；0 使用均匀底色。
@export_range(0.0, 0.5, 0.01) var meadow_variation := 0.17:
	set(value): meadow_variation = value; _apply_material()
## 草地材质的整体色调；保留纹理的像素细节。
@export var grass_tint := Color(0.86, 0.94, 0.82):
	set(value): grass_tint = value; _apply_material()
## 步道的基础颜色，用于收敛纹理里的深色裂隙。
@export var path_color := Color(0.54, 0.48, 0.36):
	set(value): path_color = value; _apply_material()
## 泥土纹理细节的对比，0 纯基础色，1 完整原纹理。
@export_range(0.0, 1.0, 0.05) var path_detail := 0.4:
	set(value): path_detail = value; _apply_material()
## 浅水洼只用于环境表现；尚未加入钓鱼等玩法。
@export var pond_enabled := true:
	set(value): pond_enabled = value; _queue_rebuild()
@export_tool_button("重建小院地表", "Reload") var refresh_ground = rebuild

var _generated: Node3D
var _queued := false
var _noise := FastNoiseLite.new()
var _paths: Array[PackedVector2Array] = []
var _ground_material: ShaderMaterial
var _water_material: ShaderMaterial

func get_world_rect() -> Rect2:
	return Rect2(WORLD_RECT.position + Vector2(global_position.x, global_position.z), WORLD_RECT.size)

func get_ground_material() -> ShaderMaterial:
	return _ground_material

func get_water_material() -> ShaderMaterial:
	return _water_material if pond_enabled else null

func get_water_surfaces() -> Array[MeshInstance3D]:
	var surfaces: Array[MeshInstance3D] = []
	if is_instance_valid(_generated) and _generated.has_node("Pond"):
		surfaces.append(_generated.get_node("Pond") as MeshInstance3D)
	return surfaces

func _ready() -> void:
	rebuild()
	if not Engine.is_editor_hint():
		var root := get_parent()
		var player := root.get_node("Player") as Player
		player.bounds = WORLD_RECT.grow(-2.0)
		player.global_position = root.get_node("SpawnPoint").global_position
		player.reset_physics_interpolation()
		var camera := root.get_node("MapEffects").get_map_camera() as FollowCamera
		camera.set_world_rect(WORLD_RECT.grow(-4.0))
		camera.snap_to_target.call_deferred()

func _queue_rebuild() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	rebuild.call_deferred()

func _apply_material() -> void:
	if not is_instance_valid(_generated) or not _generated.has_node("Ground"):
		return
	var material := (_generated.get_node("Ground") as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
	material.set_shader_parameter("texture_scale", texture_scale)
	material.set_shader_parameter("meadow_variation", meadow_variation)
	material.set_shader_parameter("grass_tint", grass_tint)
	material.set_shader_parameter("path_color", path_color)
	material.set_shader_parameter("path_detail", path_detail)

func rebuild() -> void:
	_queued = false
	if not is_inside_tree():
		return
	_noise.seed = 12102026
	_noise.frequency = 0.18
	_build_paths()
	if is_instance_valid(_generated):
		remove_child(_generated)
		_generated.queue_free()
	_generated = Node3D.new()
	_generated.name = "Generated"
	add_child(_generated)
	_water_material = null
	_build_ground()
	if pond_enabled:
		_build_pond()
	if has_node("Flora"):
		$Flora.rebuild()
	surfaces_rebuilt.emit()

func _build_paths() -> void:
	_paths.clear()
	for points in [
		PackedVector2Array([Vector2(-5, -5), Vector2(-4, -2), Vector2(0, 0), Vector2(7, 2), Vector2(15, 6), Vector2(42, 8)]),
		PackedVector2Array([Vector2(-4, -2), Vector2(-9, -1), Vector2(-11, 2), Vector2(-11, 7)])
	]:
		var curve := Curve3D.new()
		for i in points.size():
			var previous: Vector2 = points[maxi(0, i - 1)]
			var next: Vector2 = points[mini(points.size() - 1, i + 1)]
			var tangent := (next - previous) * 0.16
			curve.add_point(Vector3(points[i].x, 0, points[i].y), Vector3(-tangent.x, 0, -tangent.y), Vector3(tangent.x, 0, tangent.y))
		var sampled := PackedVector2Array()
		var count := ceili(curve.get_baked_length() / 1.2)
		for i in range(count + 1):
			var point := curve.sample_baked(curve.get_baked_length() * float(i) / count, true)
			sampled.append(Vector2(point.x, point.z))
		_paths.append(sampled)

func _path_distance(point: Vector2) -> float:
	var distance := INF
	for path in _paths:
		for i in range(path.size() - 1):
			var edge := path[i + 1] - path[i]
			var t := clampf((point - path[i]).dot(edge) / edge.length_squared(), 0, 1)
			distance = minf(distance, point.distance_to(path[i] + edge * t))
	return distance

func _box_distance(point: Vector2, center: Vector2, half_size: Vector2) -> float:
	var q := (point - center).abs() - half_size
	return q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0)

func _yard_distance(point: Vector2) -> float:
	return ((point - Vector2(-1, -0.5)) / (Vector2(3.5, 2.6) * courtyard_scale)).length() - 1.0

func clearance(point: Vector2) -> float:
	var distance := _path_distance(point) - path_width
	distance = minf(distance, _yard_distance(point) * 2.6)
	# 只留房屋用地，不生成建筑或占位建筑。
	distance = minf(distance, _box_distance(point, Vector2(-5, -7), Vector2(4, 2.8)))
	distance = minf(distance, _box_distance(point, Vector2(-8, 4), Vector2(2.8, 2.0)))
	distance = minf(distance, _box_distance(point, Vector2(-5, -4.0), Vector2(3.2, 0.85)))
	if pond_enabled:
		distance = minf(distance, (_pond_distance(point) - 1.0) * 2.5)
	return distance

func _pond_contour(angle: float) -> float:
	return 1.0 + sin(angle * 3.0 + 0.8) * 0.08 + sin(angle * 5.0 - 0.4) * 0.055

func _pond_distance(point: Vector2) -> float:
	var local := (point - POND_CENTER) / POND_RADIUS
	return local.length() / _pond_contour(local.angle())

func ground_height(point: Vector2) -> float:
	# 建筑、院子、道路和种植预留地共用水平基面；只有水洼局部下挖。
	var height := 0.0
	if pond_enabled:
		var radius := _pond_distance(point)
		height -= (1.0 - smoothstep(0.65, 1.13, radius)) * 0.43
	return height

func _soil_weight(point: Vector2) -> float:
	var weight := 0.0
	for x in [-9.7, -8.0, -6.3]:
		weight = maxf(weight, 1.0 - smoothstep(-0.08, 0.17, _box_distance(point, Vector2(x, 4), Vector2(0.62, 1.8))))
	return weight

func _surface_weights(point: Vector2) -> Color:
	var edge_noise := _noise.get_noise_2dv(point * 3.8) * 0.22
	var dirt := 1.0 - smoothstep(path_width - 0.2, path_width + 0.38, _path_distance(point) + edge_noise)
	dirt = maxf(dirt, 1.0 - smoothstep(-0.12, 0.2, _yard_distance(point) + edge_noise * 0.2))
	var stone := 1.0 - smoothstep(-0.07, 0.12, _box_distance(point, Vector2(-5, -4), Vector2(3.2, 0.85)))
	if pond_enabled:
		var radius := _pond_distance(point)
		dirt = maxf(dirt, 1.0 - smoothstep(1.0, 1.22, radius + edge_noise * 0.1))
	return Color(dirt, stone, _soil_weight(point), 1.0)

func _build_ground() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var columns := 160
	var rows := 140
	for z in range(rows + 1):
		for x in range(columns + 1):
			var point := WORLD_RECT.position + Vector2(float(x) / columns, float(z) / rows) * WORLD_RECT.size
			vertices.append(Vector3(point.x, ground_height(point), point.y))
			var dx := ground_height(point + Vector2(0.1, 0)) - ground_height(point - Vector2(0.1, 0))
			var dz := ground_height(point + Vector2(0, 0.1)) - ground_height(point - Vector2(0, 0.1))
			normals.append(Vector3(-dx, 0.2, -dz).normalized())
			uvs.append(point)
			colors.append(_surface_weights(point))
	for z in rows:
		for x in columns:
			var a := z * (columns + 1) + x
			indices.append_array(PackedInt32Array([a, a + 1, a + columns + 1, a + 1, a + columns + 2, a + columns + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	_ground_material = material
	material.set_shader_parameter("grass_texture", GRASS)
	material.set_shader_parameter("dirt_texture", DIRT)
	material.set_shader_parameter("stone_texture", STONE)
	material.set_shader_parameter("texture_scale", texture_scale)
	material.set_shader_parameter("meadow_variation", meadow_variation)
	mesh.surface_set_material(0, material)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = mesh
	_generated.add_child(ground)
	_apply_material()
	var body := StaticBody3D.new()
	body.name = "CollisionBody"
	ground.add_child(body)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)

func _build_pond() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 64:
		for point in [Vector2.ZERO, Vector2.from_angle(TAU * i / 64.0), Vector2.from_angle(TAU * (i + 1) / 64.0)]:
			surface.set_normal(Vector3.UP)
			surface.set_uv(point * 0.5 + Vector2.ONE * 0.5)
			var contour := _pond_contour(point.angle())
			surface.add_vertex(Vector3(POND_CENTER.x + point.x * POND_RADIUS.x * contour, -0.12, POND_CENTER.y + point.y * POND_RADIUS.y * contour))
	var water := MeshInstance3D.new()
	water.name = "Pond"
	water.mesh = surface.commit()
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	_water_material = material
	material.set_shader_parameter("pond_scale", POND_RADIUS)
	water.material_override = material
	_generated.add_child(water)
