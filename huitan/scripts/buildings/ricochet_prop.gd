@tool
class_name RicochetProp
extends PlazaProp

## 六类非房屋障碍物及同风格变种；每件包含自己的网格与形状碰撞，不改地图数据。
enum Kind { LOW_WALL, IRON_FENCE, CRATE_STACK, BARREL_CLUSTER, STONE_PILLAR, CORNER_WALL }
const WOOD := preload("res://assets/meowa/buildings/ricochet/wood.png")
const VARIANT_NAMES := ["标准长墙,短隔墙,斜角折墙", "标准直栏,开口围栏,折角围栏",
	"高低箱堆,斜向单箱,横排箱组", "三桶簇,单桶,横排桶组", "方形高柱,圆形高柱,八角矮柱",
	"直角墙,U形开口墙,钝角墙"]

@export_group("弹射障碍物")
@export_enum("矮石墙", "铁艺围栏", "木箱堆", "木桶组", "方形石柱", "L形挡墙") var kind: int = Kind.LOW_WALL:
	set(value):
		kind = clampi(value, 0, 5)
		if is_inside_tree(): notify_property_list_changed()
		_queue_build()
## 米。X 为宽、Y 为高、Z 为深；原点在占地中心的地面，+Z 为正面。
@export var dimensions := Vector3(3.6, 1.25, 0.55):
	set(value): dimensions = value.max(Vector3(1.0, 0.65, 0.4)); _queue_build()
@export var wood_texture: Texture2D = WOOD:
	set(value): wood_texture = value; _queue_build()

@export_group("独立道具石材")
@export var stone_texture: Texture2D = MASONRY:
	set(value): stone_texture = value; _queue_build()
@export var cap_texture: Texture2D = LIMESTONE:
	set(value): cap_texture = value; _queue_build()

@export_group("同风格变种")
## 各类别各有两种变形；标准模式保留已有六件场景的形状。
@export_enum("标准", "变种一", "变种二") var layout_variant := 0:
	set(value): layout_variant = clampi(value, 0, 2); _queue_build()
## 开口围栏两段之间的净宽；最终宽度受该道具总宽度限制。
@export_range(0.8, 4.0, 0.1, "suffix:m") var passage_width := 2.2:
	set(value): passage_width = value; _queue_build()
## 斜角墙和折角围栏的转折角；钝角墙取 90° 加此角度。
@export_range(15.0, 75.0, 5.0, "degrees") var turn_angle_degrees := 45.0:
	set(value): turn_angle_degrees = value; _queue_build()

var _collision_body: StaticBody3D

func _validate_property(property: Dictionary) -> void:
	if property.name == "layout_variant": property.hint_string = VARIANT_NAMES[kind]

func _ready() -> void:
	add_to_group(&"ricochet_obstacles")
	super()

func _build_geometry() -> void:
	_prepare_geometry()
	match kind:
		Kind.LOW_WALL: _low_wall()
		Kind.IRON_FENCE: _iron_fence()
		Kind.CRATE_STACK: _crate_stack()
		Kind.BARREL_CLUSTER: _barrel_cluster()
		Kind.STONE_PILLAR: _stone_pillar()
		Kind.CORNER_WALL: _corner_wall()

func _prepare_geometry() -> void:
	# Preserve existing editor instances when new exported fields are hot-reloaded.
	if get("stone_texture") == null: stone_texture = MASONRY
	if get("cap_texture") == null: cap_texture = LIMESTONE
	if get("layout_variant") == null: layout_variant = 0
	if get("passage_width") == null: passage_width = 2.2
	if get("turn_angle_degrees") == null: turn_angle_degrees = 45.0
	_collision_body = _body("RicochetCollision") if collision_enabled else null
	if _collision_body: _collision_body.add_to_group(&"ricochet_surfaces")
	_materials["stone"] = _stone(stone_texture)
	_materials["cap"] = _stone(cap_texture)
	_materials["metal"] = _metal(GRAPHITE, 0.58, Color.WHITE, 0.45)
	_materials["brass"] = _metal(BRASS, 0.48)
	var wood := _stone(wood_texture)
	wood.set_shader_parameter("surface_roughness", 0.95)
	wood.set_shader_parameter("lumina_relief_strength", 0.35)
	wood.set_shader_parameter("surface_contrast", 0.65)
	wood.set_shader_parameter("surface_contrast_center", Color(0.50, 0.35, 0.20))
	_materials["wood"] = wood
	var frame := wood.duplicate() as ShaderMaterial
	frame.set_shader_parameter("surface_contrast", 0.35)
	frame.set_shader_parameter("surface_contrast_center", Color(0.62, 0.43, 0.23))
	_materials["wood_frame"] = frame

func _solid_box(center: Vector3, size: Vector3, key: String, rotation := Vector3.ZERO, label := "Surface") -> void:
	_box(center, size, key, rotation)
	if not _collision_body: return
	var shape := BoxShape3D.new()
	shape.size = size
	_collide(shape, center, rotation, label, _surface_for_material(key))

func _surface_for_material(key: String) -> StringName:
	# 生成时由明确的建材键写入语义；声音端不读取贴图或建筑类型。
	match key:
		"wood", "wood_frame": return &"wood"
		"metal", "brass": return &"metal"
		"fabric", "rope": return &"fabric"
	return &"stone"

func _collide(shape: Shape3D, center: Vector3, rotation := Vector3.ZERO, label := "Surface", surface: StringName = &"stone") -> void:
	if not _collision_body: return
	var node := _collider(_collision_body, shape, center, surface)
	node.name = label + str(_collision_body.get_child_count())
	node.rotation = rotation

func _low_wall() -> void:
	var w := dimensions.x
	var h := dimensions.y
	var d := dimensions.z
	if layout_variant == 2:
		_folded_wall()
		return
	_solid_box(Vector3(0, h * 0.48, 0), Vector3(w, h * 0.96, d), "stone")
	_solid_box(Vector3(0, h - 0.035, 0), Vector3(w + 0.1, 0.12, d + 0.1), "cap")
	_solid_box(Vector3(0, 0.08, 0), Vector3(w + 0.08, 0.16, d + 0.08), "stone")
	if layout_variant == 1: return
	for side: float in [-1.0, 1.0]:
		_solid_box(Vector3(side * (w * 0.5 - 0.14), h * 0.5, 0), Vector3(0.3, h + 0.08, d + 0.04), "stone")
		_box(Vector3(side * (w * 0.5 - 0.14), h + 0.05, 0), Vector3(0.32, 0.025, d + 0.06), "metal")

func _iron_fence() -> void:
	if layout_variant == 1:
		var gap := clampf(passage_width, 0.4, maxf(0.4, dimensions.x - 1.4))
		var width := (dimensions.x - gap) * 0.5
		for side: float in [-1.0, 1.0]:
			_fence_section(width, Vector3(side * (gap + width) * 0.5, 0, 0), 0)
	elif layout_variant == 2:
		var width := dimensions.x * 0.5
		for side: float in [-1.0, 1.0]:
			var angle := side * deg_to_rad(turn_angle_degrees) * 0.5
			var center := Basis(Vector3.UP, angle) * Vector3(side * width * 0.5, 0, 0)
			_fence_section(width, center, angle, -side)
		_solid_box(Vector3(0, dimensions.y * 0.5, 0), Vector3(0.32, dimensions.y, dimensions.z), "stone", Vector3.ZERO, "FenceJoint")
		_box(Vector3(0, dimensions.y + 0.025, 0), Vector3(0.36, 0.05, dimensions.z + 0.04), "brass")
	else:
		_fence_section(dimensions.x, Vector3.ZERO, 0)

func _fence_section(w: float, offset: Vector3, yaw: float, shared_end := 0.0) -> void:
	var h := dimensions.y
	var d := dimensions.z
	var rotation := Vector3(0, yaw, 0)
	var basis := Basis.from_euler(rotation)
	var post_width := minf(0.32, w * 0.18)
	var span := w - post_width * 2.0
	_solid_box(offset + Vector3(0, 0.18, 0), Vector3(w, 0.36, d), "stone", rotation, "FenceBase")
	for side: float in [-1.0, 1.0]:
		if side == shared_end: continue
		var x := side * (w - post_width) * 0.5
		_solid_box(offset + basis * Vector3(x, h * 0.5, 0), Vector3(post_width, h, d), "stone", rotation, "FencePost")
		_box(offset + basis * Vector3(x, h + 0.025, 0), Vector3(post_width + 0.04, 0.05, d + 0.04), "brass", rotation)
	for y in [h * 0.48, h - 0.16]:
		_solid_box(offset + basis * Vector3(0, y, 0), Vector3(span + 0.04, 0.055, 0.065), "metal", rotation, "FenceRail")
	var count := maxi(3, ceili(span / 0.25) + 1)
	for index in count:
		var x := -span * 0.5 + span * index / (count - 1)
		_solid_box(offset + basis * Vector3(x, (h + 0.36) * 0.5, 0), Vector3(0.045, h - 0.36, 0.055), "metal", rotation, "FenceBar")
		_cylinder(offset + basis * Vector3(x, h + 0.045, 0), 0.04, 0, 0.09, "metal", 4, rotation)

func _crate_stack() -> void:
	var w := dimensions.x
	var h := dimensions.y
	var d := dimensions.z
	if layout_variant == 1:
		_crate(Vector3(0, h * 0.5, 0), dimensions, PI * 0.25)
		return
	if layout_variant == 2:
		for index in 3:
			var size := Vector3(w * 0.29, h * (1.0 - index * 0.1), d * 0.65)
			_crate(Vector3((index - 1) * w * 0.33, size.y * 0.5, (index - 1) * d * 0.12), size, deg_to_rad((index - 1) * 12.0))
		return
	var large := Vector3(w * 0.54, h * 0.65, d * 0.72)
	_crate(Vector3(-w * 0.19, large.y * 0.5, -d * 0.1), large, 0.0)
	var small := Vector3(w * 0.36, h * 0.5, d * 0.53)
	_crate(Vector3(w * 0.31, small.y * 0.5, d * 0.18), small, deg_to_rad(-18))
	var upper := Vector3(w * 0.34, h * 0.35, d * 0.46)
	_crate(Vector3(-w * 0.18, large.y + upper.y * 0.5, -d * 0.13), upper, deg_to_rad(12))

func _crate(center: Vector3, size: Vector3, yaw: float) -> void:
	var rotation := Vector3(0, yaw, 0)
	var basis := Basis.from_euler(rotation)
	_solid_box(center, size, "wood", rotation, "Crate")
	var rim := minf(0.1, minf(size.x, size.y) * 0.15)
	for side: float in [-1.0, 1.0]:
		for face: float in [-1.0, 1.0]:
			_box(center + basis * Vector3(side * (size.x - rim) * 0.5, 0, face * size.z * 0.5), Vector3(rim, size.y, 0.035), "wood_frame", rotation)
			_box(center + basis * Vector3(0, side * (size.y - rim) * 0.5, face * size.z * 0.5), Vector3(size.x, rim, 0.035), "wood_frame", rotation)
		_box(center + basis * Vector3(side * size.x * 0.5, 0, 0), Vector3(0.035, rim, size.z), "wood_frame", rotation)
	var brace_angle := atan2(size.y * 0.75, size.x * 0.75)
	var brace_size := Vector3(Vector2(size.x, size.y).length() * 0.77, rim * 0.75, 0.04)
	for face: float in [-1.0, 1.0]:
		_box(center + basis * Vector3(0, 0, face * (size.z * 0.5 + 0.005)), brace_size, "wood_frame", Vector3(0, yaw, brace_angle))
		for edge: float in [-1.0, 1.0]:
			_box(center + basis * Vector3(edge * (size.x * 0.5 - rim * 0.5), -size.y * 0.5 + rim * 0.5, face * (size.z * 0.5 + 0.022)), Vector3(rim * 0.8, rim * 0.8, 0.02), "metal", rotation)
	# Narrow recessed seams make the boards readable without changing source texels.
	for index in range(1, 4):
		var x := -size.x * 0.5 + size.x * index / 4.0
		_box(center + basis * Vector3(x, 0, size.z * 0.5 - 0.001), Vector3(0.009, size.y - rim * 2.0, 0.004), "metal", rotation)

func _barrel_cluster() -> void:
	if layout_variant == 1:
		_barrel(Vector3.ZERO, minf(dimensions.x, dimensions.z) * 0.43, dimensions.y)
		return
	if layout_variant == 2:
		var radius := minf(dimensions.x * 0.135, dimensions.z * 0.43)
		for index in 3:
			_barrel(Vector3((index - 1) * dimensions.x * 0.3, 0, 0), radius, dimensions.y * (1.0 - index * 0.05))
		return
	var radius := minf(dimensions.x * 0.2, dimensions.z * 0.28)
	_barrel(Vector3(-dimensions.x * 0.23, 0, -dimensions.z * 0.15), radius, dimensions.y)
	_barrel(Vector3(dimensions.x * 0.23, 0, -dimensions.z * 0.18), radius * 0.93, dimensions.y * 0.91)
	_barrel(Vector3(0, 0, dimensions.z * 0.3), radius * 0.82, dimensions.y * 0.78)

func _barrel(root: Vector3, radius: float, height: float) -> void:
	_cylinder(root + Vector3(0, height * 0.12, 0), radius * 0.87, radius, height * 0.24, "wood", 24, Vector3.ZERO, true)
	_cylinder(root + Vector3(0, height * 0.5, 0), radius, radius, height * 0.52, "wood", 24, Vector3.ZERO, true)
	_cylinder(root + Vector3(0, height * 0.88, 0), radius, radius * 0.87, height * 0.24, "wood", 24, Vector3.ZERO, true)
	for fraction in [0.14, 0.5, 0.86]:
		var ring_radius := radius if fraction == 0.5 else radius * 0.95
		_ring(root + Vector3(0, height * fraction, 0), ring_radius, 0.035, "metal")
	_cylinder(root + Vector3(0, height - 0.012, 0), radius * 0.86, radius * 0.86, 0.028, "wood")
	_box(root + Vector3(0, height + 0.004, radius * 0.13), Vector3(radius * 1.38, 0.012, 0.009), "metal")
	_box(root + Vector3(0, height + 0.004, -radius * 0.2), Vector3(radius * 1.38, 0.012, 0.009), "metal")
	_cylinder(root + Vector3(radius * 0.31, height + 0.016, 0), 0.045, 0.045, 0.025, "wood", 8)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height * 0.52
	_collide(shape, root + Vector3(0, height * 0.5, 0), Vector3.ZERO, "Barrel", &"wood")
	_barrel_end_collision(root + Vector3(0, height * 0.12, 0), radius * 0.87, radius, height * 0.24)
	_barrel_end_collision(root + Vector3(0, height * 0.88, 0), radius, radius * 0.87, height * 0.24)

func _barrel_end_collision(center: Vector3, bottom: float, top: float, height: float) -> void:
	if not _collision_body: return
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = 24
	var shape := ConvexPolygonShape3D.new()
	shape.points = mesh.get_mesh_arrays()[Mesh.ARRAY_VERTEX]
	_collide(shape, center, Vector3.ZERO, "BarrelTaper", &"wood")

func _stone_pillar() -> void:
	if layout_variant > 0:
		_round_pillar(layout_variant == 2)
		return
	var w := dimensions.x
	var h := dimensions.y
	var d := dimensions.z
	_solid_box(Vector3(0, h * 0.06, 0), Vector3(w, h * 0.12, d), "stone")
	_solid_box(Vector3(0, h * 0.145, 0), Vector3(w * 0.81, h * 0.05, d * 0.81), "cap")
	_solid_box(Vector3(0, h * 0.53, 0), Vector3(w * 0.58, h * 0.72, d * 0.58), "cap")
	_solid_box(Vector3(0, h * 0.92, 0), Vector3(w * 0.82, h * 0.08, d * 0.82), "cap")
	_solid_box(Vector3(0, h * 0.98, 0), Vector3(w * 0.94, h * 0.04, d * 0.94), "cap")
	_box(Vector3(0, h * 0.85, 0), Vector3(w * 0.61, 0.025, d * 0.61), "brass")
	_box(Vector3(0, h * 0.25, d * 0.296), Vector3(w * 0.18, h * 0.12, 0.02), "metal")

func _corner_wall() -> void:
	var w := dimensions.x
	var h := dimensions.y
	var d := dimensions.z
	var thickness := minf(0.45, minf(w, d) * 0.22)
	if layout_variant == 2:
		var joint := Vector3(-(w - thickness) * 0.5, 0, -(d - thickness) * 0.5)
		var yaw := -deg_to_rad(turn_angle_degrees)
		var direction := Basis(Vector3.UP, yaw) * Vector3.BACK
		_wall_segment(Vector3(0, 0, joint.z), w, thickness, 0)
		_wall_segment(joint + direction * (d - thickness) * 0.5, d, thickness, yaw + PI * 0.5)
		return
	_solid_box(Vector3(0, h * 0.5, -(d - thickness) * 0.5), Vector3(w, h, thickness), "stone", Vector3.ZERO, "CornerBack")
	_solid_box(Vector3(-(w - thickness) * 0.5, h * 0.5, 0), Vector3(thickness, h, d), "stone", Vector3.ZERO, "CornerSide")
	_solid_box(Vector3(0, h + 0.025, -(d - thickness) * 0.5), Vector3(w + 0.04, 0.1, thickness + 0.08), "cap")
	_solid_box(Vector3(-(w - thickness) * 0.5, h + 0.025, 0), Vector3(thickness + 0.08, 0.1, d + 0.04), "cap")
	if layout_variant == 1:
		_solid_box(Vector3((w - thickness) * 0.5, h * 0.5, 0), Vector3(thickness, h, d), "stone", Vector3.ZERO, "CornerRight")
		_solid_box(Vector3((w - thickness) * 0.5, h + 0.025, 0), Vector3(thickness + 0.08, 0.1, d + 0.04), "cap")
	_box(Vector3(-(w - thickness) * 0.5, h + 0.085, -(d - thickness) * 0.5), Vector3(thickness + 0.1, 0.02, thickness + 0.1), "metal")

func _wall_segment(center: Vector3, length: float, thickness: float, yaw: float) -> void:
	var rotation := Vector3(0, yaw, 0)
	_solid_box(center + Vector3(0, dimensions.y * 0.5, 0), Vector3(length, dimensions.y, thickness), "stone", rotation, "AngledWall")
	_solid_box(center + Vector3(0, dimensions.y + 0.025, 0), Vector3(length + 0.04, 0.1, thickness + 0.08), "cap", rotation)
	_solid_box(center + Vector3(0, 0.06, 0), Vector3(length + 0.02, 0.12, thickness + 0.04), "stone", rotation)

func _folded_wall() -> void:
	var length := dimensions.x * 0.5
	var yaw := -deg_to_rad(turn_angle_degrees)
	var joint := Vector3(0, 0, -dimensions.z * 0.2)
	var forward := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	_wall_segment(joint - Vector3(length * 0.5, 0, 0), length, 0.42, 0)
	_wall_segment(joint + forward * length * 0.5, length, 0.42, yaw)

func _round_pillar(faceted: bool) -> void:
	var radius := minf(dimensions.x, dimensions.z) * 0.5
	var h := dimensions.y
	var segments := 8 if faceted else 32
	_solid_cylinder(Vector3(0, h * 0.06, 0), radius, h * 0.12, segments, faceted)
	_solid_cylinder(Vector3(0, h * 0.145, 0), radius * 0.82, h * 0.05, segments, faceted)
	_solid_cylinder(Vector3(0, h * 0.53, 0), radius * 0.6, h * 0.72, segments, faceted)
	_solid_cylinder(Vector3(0, h * 0.92, 0), radius * 0.84, h * 0.08, segments, faceted)
	_solid_cylinder(Vector3(0, h * 0.98, 0), radius * 0.95, h * 0.04, segments, faceted)
	_ring(Vector3(0, h * 0.86, 0), radius * 0.62, 0.025, "brass")

func _solid_cylinder(center: Vector3, radius: float, height: float, segments: int, faceted: bool) -> void:
	_cylinder(center, radius, radius, height, "cap", segments)
	if not _collision_body: return
	if faceted:
		var mesh := CylinderMesh.new()
		mesh.bottom_radius = radius
		mesh.top_radius = radius
		mesh.height = height
		mesh.radial_segments = segments
		var shape := ConvexPolygonShape3D.new()
		shape.points = mesh.get_mesh_arrays()[Mesh.ARRAY_VERTEX]
		_collide(shape, center, Vector3.ZERO, "FacetedPillar")
	else:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		_collide(shape, center, Vector3.ZERO, "RoundPillar")
