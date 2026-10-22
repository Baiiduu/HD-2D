extends SceneTree

const BUILDING := "res://scenes/buildings/pocket_universe_nursery.tscn"
const CYBER := "res://assets/models/cyber_armillary/"
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var building: Node3D = load(BUILDING).instantiate()
	var orbit: MeshInstance3D = building.get_node("Model/Orbit")
	check(orbit.get_meta("shared_orbit_atlas", false), "旧蓝线替换为中央球体的高科技轨道")
	check(building.has_node("Model/OrbitDetails"), "新轨道配有分段光条与连接块")
	if failures:
		building.free()
		quit(1)
		return
	var material: ShaderMaterial = load(CYBER + "material.tres")
	check(orbit.mesh == load(CYBER + "orbit_a.res"), "实体轨道直接复用中央球体原网格和 UV")
	check(orbit.material_override == material, "轨道共用中央球体原材质")
	var details: MeshInstance3D = building.get_node("Model/OrbitDetails")
	check(details.material_override == material, "分段青蓝光条与暖色连接块使用同一高科技材质")
	for key in ["albedo_atlas", "orm_atlas"]:
		check((material.get_shader_parameter(key) as Texture2D).get_size() == Vector2(512, 512), "复用原生图集：" + key)
	var vertices: PackedVector3Array = orbit.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var average := Vector3.ZERO
	var clear := true
	for vertex in vertices:
		var point := orbit.transform * vertex
		average += point
		var radius := point.distance_to(Vector3(0, 2.52, 0))
		clear = clear and radius > 0.66 and radius < 0.77
	average /= vertices.size()
	check(average.distance_to(Vector3(0, 2.52, 0)) < 0.001, "缩小后的轨道与培育馆球心对齐")
	check(clear, "轨道按小球尺度缩小，并与半径 0.55 米的球体留出空隙")
	check(building.get_script() == null, "轨道为静态模型，无逐帧处理")
	check(building.find_children("*", "Light3D", true, false).is_empty(), "局部发光不新增场景光源")
	building.free()
	var preview: Node3D = load("res://scenes/previews/pocket_universe_blockout.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	preview._set_nursery_white(true)
	preview._set_nursery_white(false)
	check(preview.get_node("Samples/Nursery/Model/Orbit").material_override == material, "切回正式材质后仍保留高科技轨道材质")
	preview.free()
	await process_frame
	print("Pocket universe orbit: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
