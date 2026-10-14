@tool
class_name PlazaStreetlamp
extends PlazaProp

@export_group("参考图路灯")
## 灯头顶盖到地面的高度，米。横臂沿本地 X，两盏灯向下照明。
@export_range(2.4, 4.5, 0.05, "suffix:m") var height := 3.35:
	set(value): height = value; _queue_build()
@export_range(0.8, 2.0, 0.05, "suffix:m") var arm_span := 1.35:
	set(value): arm_span = value; _queue_build()
@export var metal_texture: Texture2D = GRAPHITE:
	set(value): metal_texture = value; _queue_build()

@export_group("灯光与光晕")
@export var light_enabled := true:
	set(value): light_enabled = value; _queue_lighting()
@export var light_color := Color(1.0, 0.74, 0.43):
	set(value): light_color = value; _queue_lighting()
## 每个灯头的直接照明强度；已有公共框架同时处理阴影、水面与金色粒子。
@export_range(0.0, 5.0, 0.05) var light_energy := 2.1:
	set(value): light_energy = value; _queue_lighting()
@export_range(3.0, 9.0, 0.1, "suffix:m") var light_range := 6.0:
	set(value): light_range = value; _queue_lighting()
@export_range(0.0, 1.5, 0.05) var halo_energy := 0.7:
	set(value): halo_energy = value; _queue_lighting()
@export var shadows_enabled := true:
	set(value): shadows_enabled = value; _queue_lighting()

var _heads: Array[Node3D] = []
var _lighting_queued := false

func _build_geometry() -> void:
	_heads.clear()
	_materials["metal"] = _metal(metal_texture, 0.48, Color.WHITE, 0.55)
	_materials["brass"] = _metal(BRASS, 0.34)
	_box(Vector3(0, 0.08, 0), Vector3(0.58, 0.16, 0.58), "metal")
	_box(Vector3(0, 0.21, 0), Vector3(0.4, 0.12, 0.4), "metal")
	_cylinder(Vector3(0, 0.48, 0), 0.15, 0.11, 0.44, "metal", 8)
	_cylinder(Vector3(0, (height + 0.6) * 0.5, 0), 0.075, 0.055, height - 0.6, "metal", 12)
	for level in [0.69, height - 0.63, height - 0.31]:
		_cylinder(Vector3(0, level, 0), 0.105, 0.105, 0.055, "brass", 12)
	_box(Vector3(0, height - 0.3, 0), Vector3(arm_span + 0.12, 0.065, 0.09), "metal")
	_sphere(Vector3(0, height + 0.08, 0), 0.08, "brass")
	var lamp_y := height - 0.65
	for side: float in [-1.0, 1.0]:
		var x: float = side * arm_span * 0.5
		_box(Vector3(x, height - 0.36, 0), Vector3(0.05, 0.12, 0.05), "metal")
		# Squared lanterns with a tapered dark roof, four ribs and a narrow brass lip.
		_box(Vector3(x, lamp_y - 0.24, 0), Vector3(0.36, 0.065, 0.36), "metal")
		_box(Vector3(x, lamp_y + 0.22, 0), Vector3(0.36, 0.05, 0.36), "brass")
		_cylinder(Vector3(x, lamp_y + 0.285, 0), 0.27, 0.07, 0.1, "metal", 4, Vector3(0, PI * 0.25, 0))
		for edge_x in [-1.0, 1.0]:
			for edge_z in [-1.0, 1.0]:
				_box(Vector3(x + edge_x * 0.145, lamp_y, edge_z * 0.145), Vector3(0.03, 0.44, 0.03), "metal")
		var head := _lantern("HeadLeft" if side < 0 else "HeadRight", Vector3(x, lamp_y, 0), light_energy, light_color, halo_energy)
		head.get_node("Post").hide()
		head.get_node("Cap").hide()
		var glass: MeshInstance3D = head.get_node("Lamp")
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.25, 0.39, 0.25)
		mesh.material = (glass.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
		glass.mesh = mesh
		_heads.append(head)
	if collision_enabled:
		var body := _body("LampCollision")
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.58, 0.27, 0.58)
		_collider(body, shape, Vector3(0, shape.size.y * 0.5, 0))
		var pole := CylinderShape3D.new()
		pole.radius = 0.15
		pole.height = height - 0.27
		_collider(body, pole, Vector3(0, 0.27 + pole.height * 0.5, 0))
	apply()

func _queue_lighting() -> void:
	if not is_inside_tree() or _lighting_queued: return
	_lighting_queued = true
	apply.call_deferred()

func apply() -> void:
	_lighting_queued = false
	for head in _heads:
		if not is_instance_valid(head): continue
		head.visible = light_enabled
		head.set("light_color", light_color)
		head.set("direct_energy", light_energy if light_enabled else 0.0)
		head.set("fill_energy", light_energy * 0.45 if light_enabled else 0.0)
		head.set("water_energy", light_energy * 0.45 if light_enabled else 0.0)
		head.set("light_range", light_range)
		head.set("water_range", light_range)
		head.set("halo_energy", halo_energy if light_enabled else 0.0)
		head.set("shadows_enabled", shadows_enabled)
		head.call("apply")
