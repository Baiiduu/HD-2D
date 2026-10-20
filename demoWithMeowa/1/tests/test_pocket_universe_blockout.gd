extends SceneTree
## 只验尺寸、资源归属和实体入口；白模观感由预览场景人工验收。

const BUILDING := "res://scenes/buildings/pocket_universe_nursery.tscn"
const PREVIEW := "res://scenes/previews/pocket_universe_blockout.tscn"
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
	check(ResourceLoader.exists(BUILDING), "袖珍宇宙培育馆需要可独立实例化的建筑场景")
	check(ResourceLoader.exists(PREVIEW), "独立对照预览需要保存为场景")
	if failures:
		quit(1)
		return
	var building: Node3D = load(BUILDING).instantiate()
	root.add_child(building)
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in building.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		if mesh.mesh is ArrayMesh:
			var arrays := mesh.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var valid := true
			for i in range(0, vertices.size(), 3):
				var facing := (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i])
				valid = valid and normals[i].is_normalized() and facing.dot(normals[i]) < 0.0
			check(valid, "弧形实体和门洞的表面朝外，顶面、内壁没有翻面：" + String(mesh.name))
	check(bounds.position.y >= -0.001, "白模贴地，无外露地基")
	check(absf(bounds.end.y - 3.8) < 0.005, "总高含天线为 3.80 米")
	check(absf(bounds.size.x - 3.6) < 0.015 and absf(bounds.size.z - 3.2) < 0.015, "全部实体控制在 3.60 × 3.20 米占地内")
	var entrance: Marker3D = building.get_node("MainEntrance")
	var opening: Vector2 = entrance.get_meta("clear_opening")
	check(is_equal_approx(opening.x, 0.8) and is_equal_approx(opening.y, 1.3), "入口净宽 0.80 米、净高 1.30 米")
	check(entrance.position.z > 1.2 and entrance.position.z < 1.4, "主门真实内凹，保留门洞侧壁")
	var world_state := (load("res://scenes/world/world.tscn") as PackedScene).get_state()
	var capsule: CapsuleShape3D
	var sprite_transform: Transform3D
	var pixel_size := 0.0
	for i in world_state.get_node_count():
		for prop in world_state.get_node_property_count(i):
			var key := world_state.get_node_property_name(i, prop)
			var value: Variant = world_state.get_node_property_value(i, prop)
			if String(world_state.get_node_path(i)).ends_with("Player/Collision") and key == &"shape":
				capsule = value
			if String(world_state.get_node_path(i)).ends_with("Player/Sprite"):
				if key == &"transform": sprite_transform = value
				if key == &"pixel_size": pixel_size = value
	check(capsule != null and opening.y > capsule.height + 0.2 and opening.x > capsule.radius * 2.0 + 0.2, "真实人物胶囊有足够头顶与肩侧余量")
	for frame in 3: await physics_frame
	var space := building.get_world_3d().direct_space_state
	var recess := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 0.6, 1.85), Vector3(0, 0.6, 1.4), 1))
	check(recess.is_empty(), "入口前段没有整栋大盒子封住凹口")
	var door := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 0.6, 1.85), Vector3(0, 0.6, 1.1), 1))
	check(not door.is_empty(), "白模门后仍是实体，无未经授权的室内玩法")
	if not door.is_empty(): check(door.position.z < 1.4, "门后碰撞与实际内凹门平面对齐")
	var actor_query := PhysicsShapeQueryParameters3D.new()
	actor_query.shape = capsule
	actor_query.transform = Transform3D(Basis.IDENTITY, Vector3(0, capsule.height * 0.5, 1.55))
	check(space.intersect_shape(actor_query).is_empty(), "真实人物胶囊可进入门前凹口，不被侧壁或门楣卡住")
	actor_query.transform.origin.z = 1.25
	check(not space.intersect_shape(actor_query).is_empty(), "人物在关闭门后被实际实体挡住")
	var sky_gap := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 2.52, 2), Vector3(0, 2.52, 0.8), 1))
	check(sky_gap.is_empty(), "上下舱之间保留真实观测开口，没有包住整栋的空碰撞盒")
	building.free()
	var stage: Node3D = load(PREVIEW).instantiate()
	root.add_child(stage)
	await process_frame
	for name in [&"Hospital", &"ConvenienceStore"]:
		check(stage.get_node("Samples/" + String(name)).scale.is_equal_approx(Vector3.ONE * 0.5), "对照建筑沿用正式地图 0.5 缩放：" + String(name))
	var actor: Player = stage.get_node("Player")
	check(actor.get_node("Sprite").transform.is_equal_approx(sprite_transform), "预览人物使用正式 Sprite 变换与脚底锚点")
	check(is_equal_approx(actor.get_node("Sprite").pixel_size, pixel_size), "人物不因预览放大像素或改变比例")
	check(is_equal_approx(actor.get_node("Collision").shape.height, capsule.height), "预览人物碰撞尺寸与正式地图相同")
	check(actor.animations == load("res://data/combat/scenes/world/player/character_movement.tres"), "预览使用正式人物动作资源")
	var camera: FollowCamera = stage.get_node("Camera3D")
	check(is_equal_approx(camera.fov, 28.0) and is_equal_approx(camera.distance, 30.0) and is_equal_approx(camera.pitch_degrees, 30.627), "默认对照采用正式 FOV、距离与俯角")
	stage.show_view("front")
	check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL and is_zero_approx(camera.pitch_degrees), "正面采用水平正交投影，不重复概念图的俯视误差")
	stage.show_view("top")
	check(camera.pitch_degrees > 89.0, "顶面采用接近垂直的正交检查视角")
	stage._set_comparison_white(true)
	stage._set_comparison_white(false)
	stage.show_view("follow")
	check(camera.target == actor and is_equal_approx(camera.distance, 30.0), "跟随预设复用真实人物与正式距离")
	stage.show_view("overview")
	check(camera.target == stage.get_node("Focus") and camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "返回对照恢复透视和固定焦点")
	stage.free()
	await process_frame
	print("Pocket universe blockout: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
