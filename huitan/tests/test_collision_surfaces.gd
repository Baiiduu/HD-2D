extends SceneTree

class FeedbackSpy extends CoreFeedbackAudio:
	var played: StringName
	func _play_world(cue: StringName, _point: Vector3, _kind := GameAudio.Kind.ATTACK, _gain := 0.0, _priority := -1, _pitch := 1.0, _merge_group: StringName = &"") -> bool:
		played = cue
		return true

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var surfaces: Script = load("res://scripts/core/collision_surface.gd")
	if not surfaces:
		check(false, "需要共用的碰撞部位材质解析入口")
		quit(1)
		return
	var world := Node3D.new()
	root.add_child(world)
	var parent := Node3D.new()
	parent.set_meta(&"collision_surface", &"wood")
	world.add_child(parent)
	var wall := StaticBody3D.new()
	wall.set_meta(&"movement_surface", 5)
	parent.add_child(wall)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.set_meta(&"collision_surface", &"stone")
	wall.add_child(shape)
	for frame in 3: await physics_frame
	check(surfaces.resolve(wall, 0) == &"stone", "命中形状优先于身体及上层物体的默认材质")
	shape.remove_meta(&"collision_surface")
	shape.set_meta(&"movement_surface", 4)
	check(surfaces.resolve(wall, 0) == &"wood", "兼容旧形状 movement_surface")
	shape.remove_meta(&"movement_surface")
	check(surfaces.resolve(wall, 0) == &"metal", "兼容旧碰撞身体 movement_surface")
	wall.set_meta(&"collision_surface", &"stone")
	check(surfaces.resolve(wall, 0) == &"stone", "同节点新标记优先于旧标记")
	wall.remove_meta(&"collision_surface")
	wall.remove_meta(&"movement_surface")
	check(surfaces.resolve(wall, 0) == &"wood", "未标记形状继承最近物体的默认材质")
	shape.set_meta(&"collision_surface", 99)
	check(surfaces.resolve(wall, 0) == &"wood", "无效元数据不覆盖有效默认值")
	parent.remove_meta(&"collision_surface")
	check(surfaces.resolve(wall, 0) == &"", "未标记物体保持未知，交由消费方回退")
	check(surfaces.resolve(null, -1) == &"", "已释放或无形状的碰撞安全回退")
	shape.set_meta(&"collision_surface", &"glass")
	check(surfaces.resolve(wall, 0) == &"glass", "新建筑可直接声明新材质，无需登记建筑类型")
	check(surfaces.movement_index(&"wood") == 4 and surfaces.movement_index(&"mirror") == -1, "脚步保持原六类地表，特殊反弹面不混入地表索引")
	# 使用真实扫掠返回的形状索引，不通过节点名或对象类型推测材质。
	var actor := CharacterBody3D.new()
	var actor_shape := CollisionShape3D.new()
	actor_shape.shape = SphereShape3D.new()
	actor.add_child(actor_shape)
	world.add_child(actor)
	var feedback := FeedbackSpy.new()
	feedback._body = PlayerRicochet.new()
	for material in [&"stone", &"wood", &"metal", &"mirror", &"water", &"boundary", &"glass"]:
		shape.set_meta(&"collision_surface", material)
		actor.position = Vector3(0, 0, 3)
		actor.force_update_transform()
		await physics_frame
		var contact := actor.move_and_collide(Vector3(0, 0, -4))
		check(contact != null, "真实碰撞存在：" + material)
		if not contact: continue
		check(surfaces.resolve(contact.get_collider(), contact.get_collider_shape_index()) == material, "真实碰撞索引解析：" + material)
		feedback._bounced(contact)
		var expected := &"bounce_wood" if material == &"wood" else (&"bounce_metal" if material == &"metal" else &"bounce_stone")
		check(feedback.played == expected, "反弹事件按实际部位选择音源：" + material)
		if material == &"glass":
			feedback.bounce_surface_cues[&"glass"] = &"bounce_metal"
			feedback._bounced(contact)
			check(feedback.played == &"bounce_metal", "新增材质通过映射配置选声，无需修改声音代码")
	feedback._body.free()
	feedback.free()
	world.queue_free()
	await process_frame
	print("Collision surfaces: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
