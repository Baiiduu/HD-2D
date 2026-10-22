extends SceneTree

class Collision extends ProjectileCollision:
	var native_calls := 0
	func wall_contact(space: PhysicsDirectSpaceState3D, start: Vector3, end: Vector3, radius: float, excluded: Array[RID], mask := 1) -> Dictionary:
		native_calls += 1
		return super.wall_contact(space, start, end, radius, excluded, mask)

var checks := 0
var failures := 0
var world: Node3D
var terrain: Terrain
var collision := ProjectileCollision.new()
var reference := ProjectileCollision.new()

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func settle() -> void:
	for frame in 3: await physics_frame

func wall(point: Vector3) -> StaticBody3D:
	var result := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.02, 3, 3)
	shape.shape = box
	result.add_child(shape)
	result.position = point
	world.add_child(result)
	result.force_update_transform()
	return result

func compare(label: String, start := Vector3(0, 1, 0), end := Vector3(2, 1, 0), excluded: Array[RID] = [], expect_saved := false) -> void:
	var space := world.get_world_3d().direct_space_state
	var expected := reference.wall_contact(space, start, end, 0.04, excluded)
	var before := collision.visual_sweeps_certified
	var actual: Dictionary = collision.call("visual_wall_contact", space, start, end, 0.04, excluded, terrain)
	check(actual == expected, "碰点、距离、法线、起点重叠与身体完全匹配原生查询：" + label)
	if expect_saved:
		check(terrain._obstacle_field.clear_sphere_sweep(start, end, 0.04 + collision._sphere.margin + collision._query.margin, 1, excluded), "当前完整球体确有空路段资格：" + label)
	check(collision.visual_sweeps_certified - before == (1 if expect_saved else 0), "实际入口只在完整资格成立时省去扫掠：" + label)

func run() -> void:
	if not collision.has_method("visual_wall_contact"):
		check(false, "尸体需要专用的保守空路段资格和实时扫掠回退")
	else:
		world = Node3D.new()
		root.add_child(world)
		terrain = Terrain.new()
		terrain.data = TerrainData.new()
		terrain.data.size = Vector2i.ZERO
		terrain.data.resize(Vector2i(-4, -4), Vector2i(8, 8))
		terrain.obstacle_certificates_enabled = true
		terrain.query_diagnostics_enabled = true
		world.add_child(terrain)
		await settle()
		# 冷地图不因一次死亡临时扫描世界。
		compare("未建立共享障碍表")
		terrain.obstacle_field()
		compare("空中短路段", Vector3(0, 1, 0), Vector3(2, 1, 0), [], true)
		var custom := Collision.new()
		var excluded: Array[RID] = []
		custom.call("visual_wall_contact", world.get_world_3d().direct_space_state, Vector3(0, 1, 0), Vector3(2, 1, 0), 0.04, excluded, terrain)
		check(custom.native_calls == 1, "自定义碰撞查询仍调用原覆写，不被空路段证明绕过")
		compare("地面接触", Vector3(0, 0.01, 0), Vector3(2, 0.01, 0))
		var barrier := wall(Vector3(1, 1.5, 0))
		await settle()
		compare("新增两厘米薄墙")
		compare("起点已嵌墙", Vector3(1, 1, 0), Vector3(2, 1, 0))
		compare("真实排除列表", Vector3(0, 1, 0), Vector3(2, 1, 0), [barrier.get_rid()], true)
		barrier.position.x = 5
		barrier.force_update_transform()
		compare("同一步移走动态墙", Vector3(0, 1, 0), Vector3(2, 1, 0), [], true)
		barrier.position.x = 1
		barrier.force_update_transform()
		compare("同一步移回动态墙")
		barrier.collision_layer = ProjectileCollision.MIRROR_SURFACE.COLLISION_LAYER
		compare("保留尸体原有掩码，不新增镜印碰撞", Vector3(0, 1, 0), Vector3(2, 1, 0), [], true)
		barrier.collision_layer = 1
		for offset in [-0.05, -0.0001, 0.0, 0.0001, 0.05]:
			compare("擦过墙体边缘", Vector3(0, 1, 1.54 + offset), Vector3(2, 1, 1.54 + offset))
		terrain.prepare_obstacle_change(barrier)
		var extra := BoxShape3D.new()
		extra.size = Vector3(5, 3, 0.02)
		var owner_id := barrier.get_shape_owners()[0]
		barrier.shape_owner_add_shape(owner_id, extra)
		compare("同一步增加原生形状")
		barrier.shape_owner_remove_shape(owner_id, 1)
		barrier.add_to_group(&"map_boundaries")
		compare("空气墙仍交给原排除流程")
		barrier.position.x = 5
		barrier.force_update_transform()
		terrain.obstacle_field().enabled = false
		compare("关闭障碍证明")
		terrain.obstacle_field().enabled = true
		barrier.free()
		await settle()
		compare("移除墙后恢复资格", Vector3(0, 1, 0), Vector3(2, 1, 0), [], true)
		var area := Area3D.new()
		var area_collision := CollisionShape3D.new()
		var area_shape := BoxShape3D.new()
		area_shape.size = Vector3.ONE * 0.5
		area_collision.shape = area_shape
		area.add_child(area_collision)
		area.position = Vector3(0, 1, 0)
		world.add_child(area)
		await settle()
		collision._query.collide_with_areas = true
		reference._query.collide_with_areas = true
		compare("改变为 Area 查询时不得沿用仅身体的证明")
		collision._query.collide_with_areas = false
		reference._query.collide_with_areas = false
		area.free()
		var original_thread_setting = ProjectSettings.get_setting("physics/3d/run_on_separate_thread", false)
		ProjectSettings.set_setting("physics/3d/run_on_separate_thread", true)
		compare("独立物理线程配置保留原查询")
		ProjectSettings.set_setting("physics/3d/run_on_separate_thread", original_thread_setting)
		terrain.obstacle_certificates_enabled = false
		compare("地图关闭优化保持原流程")
		terrain.obstacle_certificates_enabled = true
		world.remove_child(terrain)
		compare("地形退出后不得复用旧场景资格")
		terrain.free()
		world.free()
	print("Death sweep reuse: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
