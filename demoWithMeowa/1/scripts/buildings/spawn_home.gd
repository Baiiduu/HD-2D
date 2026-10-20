@tool
extends Node3D

const COLLISION_SURFACE := preload("res://scripts/core/collision_surface.gd")

const ART := "res://assets/meowa/home/"
const MATERIALS := ["plaster", "brick", "roof", "wood", "stone", "glass"]
const LUMINA_SURFACE := preload("res://shaders/environment/lumina_building.gdshader")

@export_group("建筑尺寸")
## 主体宽度（米），正门位于本地 +Z 方向。
@export_range(4.0, 12.0, 0.1) var width := 7.0:
	set(value): width = value; _queue_build()
## 主体前后深度（米）。
@export_range(3.0, 9.0, 0.1) var depth := 4.8:
	set(value): depth = value; _queue_build()
## 从地面到主屋檐的高度（米）。
@export_range(2.8, 4.5, 0.1) var eave_height := 3.1:
	set(value): eave_height = value; _queue_build()
## 主屋顶从屋檐到屋脊的高度（米）。
@export_range(0.7, 2.5, 0.1) var roof_rise := 1.5:
	set(value): roof_rise = value; _queue_build()
## 屋面实体厚度（米），封闭檐口和底面，避免侧下方观察时消失。
@export_range(0.04, 0.3, 0.01) var roof_thickness := 0.12:
	set(value): roof_thickness = value; _queue_build()

@export_group("材质")
## 使用现有纹理对应的独立法线；没有对应数据时保留原凹凸方式。
@export var surface_normals_enabled := false:
	set(value): surface_normals_enabled = value; _queue_visual_materials()
## 独立法线的受光起伏，不改变颜色纹理或建筑形状。
@export_range(0.0, 1.5, 0.05) var surface_normal_strength := 0.8:
	set(value): surface_normal_strength = value; _queue_visual_materials()
## 一张材质铺满的物理长度（米）；越小，纹理越密。
@export_range(0.5, 4.0, 0.1) var texture_meters := 2.0:
	set(value): texture_meters = value; _queue_build()
## 最近邻采样保留像素边缘；关闭使用线性采样。
@export var pixel_filter := true:
	set(value): pixel_filter = value; _queue_build()
## 不透明表面的粗糙度；越低，高光越明显。玻璃单独保持较低粗糙度。
@export_range(0.2, 1.0, 0.05) var roughness := 0.9:
	set(value): roughness = value; _queue_build()
@export_tool_button("导出当前建筑 GLB", "Save") var export_button = export_glb

@export_group("像素材质覆盖")
## 墙面材质样张；为空时使用原 Meowa 墙面，不改变建筑形状。
@export var plaster_texture_override: Texture2D:
	set(value): plaster_texture_override = value; _queue_build()
## 屋瓦材质样张；为空时使用原 Meowa 屋瓦。
@export var roof_texture_override: Texture2D:
	set(value): roof_texture_override = value; _queue_build()
## 5×4 有限色阶色板；第 2 行用于墙面、第 3 行用于屋瓦（从 0 开始）。
## 仅作用于上方已覆盖的像素墙面和屋瓦，留空保持原颜色。
@export var override_palette_texture: Texture2D:
	set(value):
		if override_palette_texture == value:
			return
		override_palette_texture = value
		if is_inside_tree():
			_refresh_palette_materials.call_deferred()
## 覆盖纹理每块的物理长度（米）；64 像素 / 1.6 米约为 40 像素/米。
@export_range(0.5, 4.0, 0.1) var override_texture_meters := 1.6:
	set(value): override_texture_meters = value; _queue_build()
## 覆盖纹理的凹凸邻域（原图像素）；原生像素素材通常设为 1。
@export_range(1.0, 16.0, 1.0) var override_relief_sample_pixels := 1.0:
	set(value): override_relief_sample_pixels = value; _queue_build()
## 覆盖屋瓦的局部对比；1 保持原图，降低后深缝与亮边靠近平均色。
@export_range(0.0, 1.2, 0.05) var override_roof_contrast := 1.0:
	set(value): override_roof_contrast = value; _queue_build()

@export_group("Lumina 材质样板")
## 使用原 Meowa 纹理推导浅凹凸和亮暖暗冷色阶；关闭恢复既有材质。
@export var lumina_relief_enabled := false:
	set(value): lumina_relief_enabled = value; _queue_visual_materials()
## 凹凸受光强度，不改变屋面、门廊或碰撞形状。
@export_range(0.0, 1.5, 0.05) var lumina_relief_strength := 0.8:
	set(value): lumina_relief_strength = value; _queue_visual_materials()
## 原图暗部偏冷、亮部偏暖的轻微变化。
@export_range(0.0, 0.25, 0.01) var lumina_tone_strength := 0.08:
	set(value): lumina_tone_strength = value; _queue_visual_materials()
## 哑光粗糙度下限；降低后高光更集中。
@export_range(0.0, 1.0, 0.01) var lumina_matte_floor := 0.48:
	set(value): lumina_matte_floor = value; _queue_visual_materials()
## 仅使已有玻璃纹理发暖光，不新增灯具或碰撞。
@export var window_glow_enabled := false:
	set(value): window_glow_enabled = value; _queue_visual_materials()
@export_range(0.0, 4.0, 0.05) var window_glow_energy := 0.8:
	set(value): window_glow_energy = value; _queue_visual_materials()
@export var window_glow_color := Color(1.0, 0.67, 0.32):
	set(value): window_glow_color = value; _queue_visual_materials()

var _queued := false
var _visual_materials_queued := false
var _streams: Dictionary = {}
var _triangle_count := 0

func _ready() -> void:
	build()

func _queue_build() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	build.call_deferred()

func _queue_visual_materials() -> void:
	if not is_inside_tree() or _visual_materials_queued: return
	_visual_materials_queued = true
	_refresh_palette_materials.call_deferred()

func build() -> void:
	_queued = false
	var old := get_node_or_null("Geometry")
	if old:
		remove_child(old)
		old.free()
	_streams.clear()
	_triangle_count = 0
	for key: String in MATERIALS:
		var stream := SurfaceTool.new()
		stream.begin(Mesh.PRIMITIVE_TRIANGLES)
		_streams[key] = stream
	var half_width := width * 0.5
	var half_depth := depth * 0.5
	var foundation := 0.55
	_box(Vector3(0, foundation * 0.5, 0), Vector3(width, foundation, depth), "brick")
	_box(Vector3(0, (eave_height + foundation) * 0.5, 0), Vector3(width, eave_height - foundation, depth), "plaster")
	_main_roof(half_width, half_depth)
	# 木梁、檐板、屋脊与转角具有真实厚度。
	for x: float in [-half_width + 0.07, half_width - 0.07]:
		for z: float in [-half_depth + 0.07, half_depth - 0.07]:
			_box(Vector3(x, (eave_height + foundation) * 0.5, z), Vector3(0.16, eave_height - foundation, 0.16), "wood")
		_box(Vector3(x, eave_height - 0.03, 0), Vector3(0.15, 0.18, depth), "wood")
	for z: float in [-half_depth, half_depth]:
		_box(Vector3(0, eave_height - 0.06, z), Vector3(width, 0.18, 0.18), "wood")
		_box(Vector3(0, 0.12, z), Vector3(width + 0.04, 0.24, 0.12), "stone")
	_box(Vector3(0, eave_height + roof_rise + 0.03, 0), Vector3(width + 0.7, 0.16, 0.18), "roof")
	for x: float in [-half_width - 0.22, half_width + 0.22]:
		var slope := atan2(roof_rise, half_depth + 0.3)
		var length := sqrt(roof_rise * roof_rise + pow(half_depth + 0.3, 2))
		for side: float in [-1.0, 1.0]:
			_box(Vector3(x, eave_height + roof_rise * 0.5, side * (half_depth + 0.3) * 0.5), Vector3(0.16, 0.17, length), "wood", Vector3(side * slope, 0, 0))
	# 两个正面窗、两个背面窗，两侧各一个窗；右侧窗保留修补木板。
	for x: float in [-width * 0.31, width * 0.31]:
		_window(Vector3(x, 1.95, half_depth + 0.06), 0.0, x > 0.0)
		_window(Vector3(-x, 1.95, -half_depth - 0.06), PI, x > 0.0)
	_window(Vector3(half_width + 0.06, 1.95, 0), PI * 0.5, true)
	_window(Vector3(-half_width - 0.06, 1.95, 0), -PI * 0.5, false)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(side * (half_width + 0.02), eave_height - 0.03, 0), Vector3(0.11, 0.12, depth), "wood")
		_box(Vector3(side * (half_width + 0.03), eave_height + roof_rise * 0.35, 0), Vector3(0.08, 0.42, 0.42), "wood")
	_front_door(half_depth, foundation)
	_porch(half_depth, foundation)
	_chimney(half_width, half_depth)
	var geometry := Node3D.new()
	geometry.name = "Geometry"
	add_child(geometry)
	geometry.owner = self
	for key: String in MATERIALS:
		var stream: SurfaceTool = _streams[key]
		stream.index()
		var mesh := stream.commit()
		var material := StandardMaterial3D.new()
		material.resource_name = key
		material.albedo_texture = _surface_texture(key, ART)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS if pixel_filter else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if key == "roof":
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC if pixel_filter else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		material.texture_repeat = true
		material.roughness = 0.3 if key == "glass" else roughness
		material.metallic = 0.12 if key == "glass" else 0.0
		mesh.surface_set_material(0, _lumina_material(material, key))
		var instance := MeshInstance3D.new()
		instance.name = key.capitalize()
		instance.mesh = mesh
		geometry.add_child(instance)
		instance.owner = self
	var body := StaticBody3D.new()
	body.name = "Collision"
	geometry.add_child(body)
	body.owner = self
	_collision(body, "House", Vector3(0, eave_height * 0.5, 0), Vector3(width, eave_height, depth))
	_collision(body, "Porch", Vector3(0, foundation * 0.5, half_depth + 0.74), Vector3(2.4, foundation, 1.5))
	for step in 3:
		var height := foundation * float(3 - step) / 4.0
		_collision(body, "Step%d" % step, Vector3(0, height * 0.5, half_depth + 1.63 + step * 0.3), Vector3(2.2, height, 0.3))
	set_meta("triangle_count", _triangle_count)

func _texture_override(key: String) -> Texture2D:
	if key == "plaster":
		return plaster_texture_override
	if key == "roof":
		return roof_texture_override
	return null

func _surface_texture(key: String, art_directory: String) -> Texture2D:
	var replacement := _texture_override(key)
	return replacement if replacement != null else load(art_directory + key + ".png") as Texture2D

func _refresh_palette_materials() -> void:
	_visual_materials_queued = false
	# 色阶、受光和窗光只更新材质，保留网格、UV、碰撞与交互点。
	var geometry := get_node_or_null("Geometry")
	if not geometry: return
	for child in geometry.get_children():
		var instance := child as MeshInstance3D
		if instance == null or instance.mesh == null: continue
		var current: Material = instance.mesh.surface_get_material(0)
		var base := current as StandardMaterial3D
		if base == null and current is ShaderMaterial:
			base = current.get_meta("base_surface_material", null) as StandardMaterial3D
		if base != null:
			instance.mesh.surface_set_material(0, _lumina_material(base, base.resource_name))

func _lumina_material(base: StandardMaterial3D, key: String) -> Material:
	if key == "glass":
		base.emission_enabled = window_glow_enabled
		base.albedo_color = Color.WHITE
		if window_glow_enabled:
			base.albedo_color = Color.WHITE.lerp(window_glow_color, 0.32)
			base.emission_enabled = true
			base.emission = window_glow_color
			base.emission_texture = base.albedo_texture
			base.emission_energy_multiplier = window_glow_energy
		return base
	var use_palette := override_palette_texture != null and _texture_override(key) != null
	var normal := SurfaceNormalMaps.for_texture(base.albedo_texture) if surface_normals_enabled else null
	if key == "metal" or (not lumina_relief_enabled and not use_palette and not normal):
		return base
	var material := ShaderMaterial.new()
	material.resource_name = key
	material.shader = LUMINA_SURFACE
	material.set_meta("base_surface_material", base)
	material.set_shader_parameter("surface_texture", base.albedo_texture)
	material.set_shader_parameter("surface_texture_linear", base.albedo_texture)
	material.set_shader_parameter("pixel_sampling", pixel_filter)
	material.set_shader_parameter("surface_roughness", base.roughness)
	material.set_shader_parameter("surface_normal_enabled", normal != null)
	material.set_shader_parameter("surface_normal_texture", normal)
	material.set_shader_parameter("surface_normal_strength", surface_normal_strength)
	material.set_shader_parameter("lumina_relief_enabled", lumina_relief_enabled)
	material.set_shader_parameter("lumina_relief_strength", lumina_relief_strength)
	material.set_shader_parameter("lumina_tone_strength", lumina_tone_strength)
	material.set_shader_parameter("lumina_matte_floor", lumina_matte_floor)
	material.set_shader_parameter("pixel_palette_enabled", use_palette)
	if use_palette:
		material.set_shader_parameter("pixel_palette_texture", override_palette_texture)
		material.set_shader_parameter("pixel_palette_row", 2 if key == "plaster" else 3)
	material.set_shader_parameter("relief_sample_pixels", override_relief_sample_pixels if _texture_override(key) != null else 6.0)
	material.set_shader_parameter("relief_height", 0.005 if key in ["plaster", "canvas", "leather"] else 0.012)
	if key == "roof" and roof_texture_override != null and override_roof_contrast != 1.0:
		material.set_shader_parameter("surface_contrast", override_roof_contrast)
		material.set_shader_parameter("surface_contrast_center", _mean_texture_color(roof_texture_override))
	return material

func _mean_texture_color(texture: Texture2D) -> Color:
	var image := texture.get_image()
	var total := Color(0.0, 0.0, 0.0, 0.0)
	# 与 source_color 纹理的线性色彩域一致，降低对比时保留平均亮度。
	for y in image.get_height():
		for x in image.get_width():
			total += image.get_pixel(x, y).srgb_to_linear()
	return (total / float(image.get_width() * image.get_height())).linear_to_srgb()

func _face(points: Array[Vector3], key: String) -> void:
	var stream: SurfaceTool = _streams[key]
	var normal := -(points[1] - points[0]).cross(points[2] - points[0]).normalized()
	var meters := override_texture_meters if _texture_override(key) != null else texture_meters
	var span := Vector2(points[0].distance_to(points[1]), points[0].distance_to(points[-1])) / meters
	var uvs := [Vector2.ZERO, Vector2(span.x, 0), span, Vector2(0, span.y)]
	if key == "roof" and points.size() == 4:
		uvs = [Vector2.ZERO, Vector2(0, span.x), Vector2(span.y, span.x), Vector2(span.y, 0)]
	if points.size() == 3:
		uvs = [Vector2.ZERO, Vector2(span.x, 0), Vector2(span.x * 0.5, span.y)]
	for triangle in range(1, points.size() - 1):
		for index in [0, triangle, triangle + 1]:
			stream.set_normal(normal)
			stream.set_uv(uvs[index])
			stream.add_vertex(points[index])
		_triangle_count += 1

func _box(center: Vector3, size: Vector3, key: String, angles := Vector3.ZERO) -> void:
	var h := size * 0.5
	var basis := Basis.from_euler(angles)
	var faces := [
		[Vector3(-h.x,h.y,-h.z),Vector3(h.x,h.y,-h.z),Vector3(h.x,h.y,h.z),Vector3(-h.x,h.y,h.z)],
		[Vector3(-h.x,-h.y,h.z),Vector3(h.x,-h.y,h.z),Vector3(h.x,-h.y,-h.z),Vector3(-h.x,-h.y,-h.z)],
		[Vector3(-h.x,h.y,h.z),Vector3(h.x,h.y,h.z),Vector3(h.x,-h.y,h.z),Vector3(-h.x,-h.y,h.z)],
		[Vector3(h.x,h.y,-h.z),Vector3(-h.x,h.y,-h.z),Vector3(-h.x,-h.y,-h.z),Vector3(h.x,-h.y,-h.z)],
		[Vector3(h.x,h.y,h.z),Vector3(h.x,h.y,-h.z),Vector3(h.x,-h.y,-h.z),Vector3(h.x,-h.y,h.z)],
		[Vector3(-h.x,h.y,-h.z),Vector3(-h.x,h.y,h.z),Vector3(-h.x,-h.y,h.z),Vector3(-h.x,-h.y,-h.z)]]
	for corners: Array in faces:
		var points: Array[Vector3] = []
		for point: Vector3 in corners:
			points.append(center + basis * point)
		_face(points, key)

func _roof_slab(points: Array[Vector3]) -> void:
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for point in points:
		top.append(point + Vector3.UP * roof_thickness * 0.5)
		bottom.append(point - Vector3.UP * roof_thickness * 0.5)
	_face(top, "roof")
	var underside := bottom.duplicate()
	underside.reverse()
	_face(underside, "roof")
	for i in points.size():
		var next := (i + 1) % points.size()
		_face([top[i], bottom[i], bottom[next], top[next]], "roof")

func _gable_face(a: Vector3, b: Vector3, peak: Vector3, roof_half_span: float, key: String) -> void:
	# 山墙封到带外挑的实际屋面坡线，不再用主体跨度产生斜向空隙。
	var edge_y := lerpf(peak.y, a.y, a.distance_to(b) * 0.5 / roof_half_span)
	var upper_a := Vector3(a.x, edge_y, a.z)
	var upper_b := Vector3(b.x, edge_y, b.z)
	_face([a, b, upper_b, upper_a], key)
	_face([upper_a, upper_b, peak], key)

func _main_roof(x: float, z: float) -> void:
	var y := eave_height
	var top := y + roof_rise
	# 主屋脊沿 X 轴，正面坡屋顶，左右两面为山墙。
	_gable_face(Vector3(x,y,-z),Vector3(x,y,z),Vector3(x,top,0),z+0.3,"plaster")
	_gable_face(Vector3(-x,y,z),Vector3(-x,y,-z),Vector3(-x,top,0),z+0.3,"plaster")
	_roof_slab([Vector3(-x-0.35,y,z+0.3),Vector3(-x-0.35,top,0),Vector3(x+0.35,top,0),Vector3(x+0.35,y,z+0.3)])
	_roof_slab([Vector3(x+0.35,y,-z-0.3),Vector3(x+0.35,top,0),Vector3(-x-0.35,top,0),Vector3(-x-0.35,y,-z-0.3)])

func _window(center: Vector3, yaw: float, boarded: bool) -> void:
	var basis := Basis(Vector3.UP, yaw)
	_box(center, Vector3(1.0, 1.0, 0.07), "glass", Vector3(0, yaw, 0))
	for x: float in [-0.57, 0.57, 0.0]:
		_box(center + basis * Vector3(x, 0, 0.045), Vector3(0.09, 1.22, 0.16), "wood", Vector3(0, yaw, 0))
	for y: float in [-0.57, 0.57, 0.0]:
		_box(center + basis * Vector3(0, y, 0.055), Vector3(1.25, 0.09, 0.19), "wood", Vector3(0, yaw, 0))
	_box(center + basis * Vector3(0, -0.64, 0.12), Vector3(1.37, 0.14, 0.32), "wood", Vector3(0, yaw, 0))
	if boarded:
		for side: float in [-1.0, 1.0]:
			var rotation := (basis * Basis(Vector3.FORWARD, side * 0.24)).get_euler()
			_box(center + basis * Vector3(0, side * 0.22, 0.2), Vector3(1.35, 0.16, 0.09), "wood", rotation)

func _front_door(z: float, ground: float) -> void:
	_box(Vector3(0, ground + 1.0, z + 0.05), Vector3(1.0, 2.0, 0.1), "wood")
	for x: float in [-0.59, 0.59]:
		_box(Vector3(x, ground + 1.04, z + 0.12), Vector3(0.15, 2.15, 0.22), "wood")
	_box(Vector3(0, ground + 2.06, z + 0.12), Vector3(1.34, 0.16, 0.22), "wood")
	_box(Vector3(0, ground + 1.57, z + 0.13), Vector3(0.35, 0.38, 0.06), "glass")
	_box(Vector3(0, ground + 0.87, z + 0.15), Vector3(0.98, 0.14, 0.1), "wood")
	_box(Vector3(0.35, ground + 0.9, z + 0.21), Vector3(0.08, 0.16, 0.06), "stone")

func _porch(z: float, ground: float) -> void:
	var porch_eave := eave_height - 0.3
	var porch_top := porch_eave + 0.65
	_box(Vector3(0, ground * 0.5, z + 0.74), Vector3(2.4, ground, 1.5), "stone")
	_box(Vector3(0, ground + 0.02, z + 0.74), Vector3(2.4, 0.04, 1.5), "wood")
	for step in 3:
		var height := ground * float(3 - step) / 4.0
		_box(Vector3(0, height * 0.5, z + 1.63 + step * 0.3), Vector3(2.2, height, 0.3), "stone")
	for x: float in [-1.1, 1.1]:
		_box(Vector3(x, (ground + porch_eave) * 0.5, z + 1.35), Vector3(0.14, porch_eave - ground, 0.14), "wood")
		for y: float in [ground + 0.15, ground + 0.75]:
			_box(Vector3(x, y, z + 0.67), Vector3(0.12, 0.1, 1.35), "wood")
		for i in 4:
			_box(Vector3(x, ground + 0.44, z + 0.2 + i * 0.29), Vector3(0.06, 0.58, 0.07), "wood")
	var front := z + 1.65
	var back := z - 0.1
	_roof_slab([Vector3(-1.35,porch_eave,back),Vector3(0,porch_top,back),Vector3(0,porch_top,front),Vector3(-1.35,porch_eave,front)])
	_roof_slab([Vector3(0,porch_top,back),Vector3(1.35,porch_eave,back),Vector3(1.35,porch_eave,front),Vector3(0,porch_top,front)])
	_gable_face(Vector3(1.22,porch_eave,front-0.05),Vector3(-1.22,porch_eave,front-0.05),Vector3(0,porch_top,front-0.05),1.35,"wood")
	_box(Vector3(0, porch_top, z + 0.77), Vector3(0.16, 0.15, 1.8), "roof")
	for side: float in [-1.0, 1.0]:
		_box(Vector3(side * 0.67, porch_eave + 0.33, front), Vector3(1.5, 0.14, 0.16), "wood", Vector3(0,0,-side*atan2(0.65,1.35)))

func _chimney(x: float, z: float) -> void:
	var center := Vector3(-x * 0.62, eave_height + roof_rise - 0.1, -z * 0.45)
	_box(center, Vector3(0.58, 1.75, 0.58), "brick")
	for offset in [Vector3(-0.31,0,0),Vector3(0.31,0,0),Vector3(0,0,-0.31),Vector3(0,0,0.31)]:
		var size := Vector3(0.14,0.15,0.76) if offset.x != 0 else Vector3(0.5,0.15,0.14)
		_box(center + offset + Vector3.UP * 0.92, size, "stone")

func _collision(parent: Node, label: String, center: Vector3, size: Vector3, surface: StringName = &"") -> void:
	var node := CollisionShape3D.new()
	COLLISION_SURFACE.mark(node, surface if surface != &"" else (&"wood" if label == "Porch" else &"stone"))
	node.name = label
	node.position = center
	var shape := BoxShape3D.new()
	shape.size = size
	node.shape = shape
	parent.add_child(node)
	node.owner = self

func export_glb() -> void:
	if not has_node("Geometry"):
		build()
	var root := Node3D.new()
	root.name = "SpawnHome"
	for child in $Geometry.get_children():
		if child is MeshInstance3D:
			var instance := MeshInstance3D.new()
			instance.name = child.name
			instance.mesh = child.mesh
			root.add_child(instance)
			instance.owner = root
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	var error := document.append_from_scene(root, state)
	if error == OK:
		error = document.write_to_filesystem(state, ART + "home.glb")
	root.free()
	if error != OK:
		push_error("Home GLB export failed: %s" % error_string(error))
	else:
		print("Exported spawn home: %d triangles" % _triangle_count)
