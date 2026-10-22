extends SceneTree

const SURFACES := preload("res://scripts/core/collision_surface.gd")
const MIRROR := preload("res://scripts/combat/mirror_reflection_surface.gd")

class BoundaryFixture extends MapEffects:
	func _ready() -> void:
		pass

var checks := 0
var failures := 0
var building_count := 0
var shape_count := 0

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func audit_parts(node: Node, path: String) -> void:
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		for owner_id in body.get_shape_owners():
			for local_index in body.shape_owner_get_shape_count(owner_id):
				var index := body.shape_owner_get_shape_index(owner_id, local_index)
				var part := body.shape_owner_get_owner(owner_id) as Node
				shape_count += 1
				check(SURFACES.resolve(body, index) != &"", "建筑碰撞部位需要有效材质：%s / %s" % [path, part.name])
	for child in node.get_children(): audit_parts(child, path)

func audit_library(path: String, world: Node3D) -> void:
	for file in DirAccess.get_files_at(path):
		if not file.ends_with(".tscn"): continue
		var scene: Node = load(path.path_join(file)).instantiate()
		world.add_child(scene)
		await process_frame
		audit_parts(scene, path.path_join(file))
		building_count += 1
		scene.queue_free()
		await process_frame
	for folder in DirAccess.get_directories_at(path):
		await audit_library(path.path_join(folder), world)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	await audit_library("res://scenes/buildings", world)
	var fence: RicochetProp = load("res://scenes/buildings/ricochet/iron_fence.tscn").instantiate()
	world.add_child(fence)
	for frame in 3: await physics_frame
	for height in [0.18, fence.dimensions.y - 0.16]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(0, height, 2), Vector3(0, height, -2), 1)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty(), "围栏底座与铁横杆维持原有碰撞")
		if not hit.is_empty():
			check(SURFACES.resolve(hit.collider, hit.shape) == (&"stone" if height < 0.36 else &"metal"), "真实命中区分围栏石底与铁杆")
	var before := fence._collision_body.get_child_count()
	fence.build()
	check(fence._collision_body.get_child_count() == before, "重建标记不改变形状数量")
	audit_parts(fence, "rebuilt fence")
	fence.free()
	var bench: TownDetailProp = load("res://scenes/buildings/town_details/park_bench.tscn").instantiate()
	world.add_child(bench)
	expect_parts(bench._collision_body, "SeatSlat", &"wood")
	expect_parts(bench._collision_body, "BenchLeg", &"metal")
	bench.free()
	var cart: TownDetailProp = load("res://scenes/buildings/town_details/flower_cart.tscn").instantiate()
	world.add_child(cart)
	expect_parts(cart._collision_body, "CartSide", &"wood")
	expect_parts(cart._collision_body, "CartHandle", &"metal")
	expect_parts(cart._collision_body, "WheelHub", &"metal")
	cart.free()
	var lamp: PlazaStreetlamp = load("res://scenes/buildings/plaza_streetlamp.tscn").instantiate()
	world.add_child(lamp)
	var lamp_body := lamp._generated.get_node("LampCollision") as StaticBody3D
	check(lamp_body.get_child_count() == 2, "路灯保留原底座和灯杆碰撞")
	check(SURFACES.resolve(lamp_body, 0) == &"metal" and SURFACES.resolve(lamp_body, 1) == &"metal", "路灯底座和灯杆都使用金属材质")
	lamp.free()
	var planter: TreePlanter = load("res://scenes/buildings/tree_planter.tscn").instantiate()
	world.add_child(planter)
	var planter_body := planter._generated.get_node("PlanterCollision") as StaticBody3D
	check(planter_body.get_child_count() == 3, "花坛在原占地内分开标记金属槽体、石压顶与木座椅")
	check(SURFACES.resolve(planter_body, 0) == &"metal" and SURFACES.resolve(planter_body, 1) == &"stone" and SURFACES.resolve(planter_body, 2) == &"wood", "花坛真实接触材质对应金属槽体、石压顶与木座椅")
	planter.free()
	var boundary := BoundaryFixture.new()
	world.add_child(boundary)
	boundary._update_boundary_collision(Rect2(-10, -10, 20, 20), 0.0)
	check(boundary._boundary.get_child_count() == 4, "地图仍保持四面真实边界")
	check(SURFACES.resolve(boundary._boundary, 0) == &"boundary", "空气墙显式标记为边界")
	var mirror := MIRROR.new()
	world.add_child(mirror)
	check(SURFACES.resolve(mirror, 0) == &"mirror", "镜印显式标记为镜面")
	var ground := Terrain.new()
	ground.data = TerrainData.new()
	ground.data.size = Vector2i.ZERO
	ground.data.resize(Vector2i.ZERO, Vector2i(2, 2))
	ground.data.overlays[0] = TerrainData.OVERLAY_WATER
	ground.water_boundary_reflection_enabled = true
	world.add_child(ground)
	check(is_instance_valid(ground._water_collision_body), "地形保持真实水域挡块")
	if is_instance_valid(ground._water_collision_body):
		check(SURFACES.resolve(ground._water_collision_body, 0) == &"water", "水域挡块显式标记为水边")
		check(ground.is_reflective_water_shape(ground._water_collision_body, 0), "保留原水边识别规则")
	world.queue_free()
	for frame in 3: await process_frame
	print("Building surfaces: %d buildings, %d shapes, %d checks, %d failures" % [building_count, shape_count, checks, failures])
	quit(1 if failures else 0)

func expect_parts(body: CollisionObject3D, prefix: String, expected: StringName) -> void:
	var found := false
	for owner_id in body.get_shape_owners():
		var part := body.shape_owner_get_owner(owner_id) as Node
		if not String(part.name).begins_with(prefix): continue
		found = true
		var index := body.shape_owner_get_shape_index(owner_id, 0)
		check(SURFACES.resolve(body, index) == expected, "碰撞部位材质对应实际建材：%s / %s" % [body.get_parent().name, part.name])
	check(found, "存在需要覆盖的混合材质部位：" + prefix)
