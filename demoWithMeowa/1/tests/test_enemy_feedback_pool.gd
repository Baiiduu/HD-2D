extends SceneTree
const MATERIALS := preload("res://scripts/enemies/enemy_remains_materials.gd")

var checks := 0
var failures := 0
var world: Node3D
var source: Sprite3D
var camera: Camera3D
var visuals: PlayerActionVisuals

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func parameter(mesh: GeometryInstance3D, name: StringName) -> Variant:
	var value: Variant = mesh.get_instance_shader_parameter(name)
	return value if value != null else (mesh.material_override as ShaderMaterial).get_shader_parameter(name)

func sharing_checks() -> void:
	var pool := EnemyFeedbackPool.new()
	world.add_child(pool)
	source.modulate = Color(0.4, 0.7, 0.9, 0.8)
	source.flip_h = true
	var first := pool.death(source, false, visuals)
	first.set_process(false)
	source.modulate = Color(0.9, 0.6, 0.3, 0.5)
	source.flip_h = false
	var second := pool.death(source, false, visuals)
	second.set_process(false)
	check(first._pieces[0].material_override == second._pieces[0].material_override, "同图集尸体共享含建筑遮挡补画的材质")
	check(first._ghosts[0].material_override == first._ghosts[1].material_override and first._ghosts[0].material_override == second._ghosts[0].material_override, "死亡残影跨怪物共用材质，保留独立透明度")
	check(first._pieces[1].material_override == second._pieces[2].material_override, "原生爆点共用图集材质")
	var second_tint: Variant = parameter(second._pieces[0], &"tint")
	var second_uv: Variant = parameter(second._pieces[0], &"frame_rect")
	check(parameter(first._pieces[0], &"tint") != second_tint and Vector4(parameter(first._pieces[0], &"frame_rect")).z < 0.0 and Vector4(second_uv).z > 0.0, "共享材质仍保留各自乘色、透明度与翻转")
	first._process(0.4)
	check(parameter(second._pieces[0], &"tint") == second_tint and parameter(second._pieces[0], &"frame_rect") == second_uv and is_equal_approx(float(parameter(second._pieces[0], &"hit_flash")), 0.35), "推进一只尸体不改写另一只的快照或短闪")
	check(parameter(first._ghosts[0], &"opacity") != parameter(first._ghosts[1], &"opacity"), "共用残影材质的两层余迹仍有各自浓淡")
	check(first._ghosts[0].material_override.render_priority == -1 and first._ghosts[0].material_override.next_pass.render_priority == 7, "共享材质保留残影原有绘制顺序")
	first._pieces[0].set_instance_shader_parameter(&"wave_finish_silhouette", 1.0)
	check(second._pieces[0].get_instance_shader_parameter(&"wave_finish_silhouette") != 1.0, "最后一击剪影只作用于选中尸体")
	first.stop()
	check(first._pieces[0].get_instance_shader_parameter(&"wave_finish_silhouette") == 0.0, "停止清理实例剪影状态")
	var contact := pool.melee_contact(Vector3.ZERO, 0.016, Vector3.RIGHT, visuals)
	contact.set_process(false)
	check(contact.material_override == second._pieces[1].material_override, "命中与死亡爆点使用同一贴图材质并保留各自亮度")
	check(parameter(contact, &"death_energy") != parameter(second._pieces[1], &"death_energy"), "共享爆点材质不会串改命中与击杀亮度")
	pool.free()

func prewarm_checks() -> void:
	var pool := EnemyFeedbackPool.new()
	world.add_child(pool)
	if not pool.has_method("start_prewarm"):
		check(false, "反馈池须支持不播放效果的分帧预热")
		pool.free()
		return
	var original_tint := source.modulate
	pool.call("start_prewarm", visuals, 20, 8)
	pool.set_process(false)
	pool._process(1.0 / 60.0)
	pool.set_process(false)
	check(pool._idle_deaths.size() == 2 and not bool(pool.call("prewarm_ready")), "每帧只预热两个对象，不集中阻塞一帧")
	for frame in 20:
		if bool(pool.call("prewarm_ready")): break
		pool._process(1.0 / 60.0)
		pool.set_process(false)
	check(bool(pool.call("prewarm_ready")) and pool._idle_deaths.size() == 20 and pool._idle_contacts.size() == 8, "准备阶段完成指定死亡与命中储备")
	check(source.modulate == original_tint and pool._burst_count == 0 and pool._burst_cooldown == 0.0, "预热不改写人物／怪物或触发群杀节奏")
	for child in pool.find_children("*", "Node", true, false):
		check(not child.is_processing(), "预热对象闲置时没有表现回调")
		if child is GeometryInstance3D: check(not child.is_visible_in_tree(), "预热不显示死亡、金星、烟尘或命中")
	var node_count := pool.find_children("*", "Node", true, false).size()
	var events: Array[StringName] = []
	pool._audio = null
	for index in 16:
		var effect := pool.death(source, false, visuals)
		effect.presentation_event.connect(func(stage, _point): events.append(stage), CONNECT_ONE_SHOT)
		effect.set_process(false)
		check(effect._active and effect._age == 0.0 and effect._pieces[0].visible, "预热后真实击杀仍从原始首帧即时开始")
	for index in 8:
		var contact := pool.melee_contact(Vector3.ZERO, 0.016, Vector3.RIGHT, visuals)
		contact.set_process(false)
	check(pool.find_children("*", "Node", true, false).size() == node_count, "首批真实群杀与命中不再临时创建附属节点")
	check(events.is_empty(), "预热和真实击杀首帧不伪造气流、落地或碰墙声音")
	pool.free()
	check(MATERIALS._users == 0 and MATERIALS._cache.is_empty(), "最后一个反馈对象退出后释放材质和贴图缓存")

func cluster_checks() -> void:
	var pool := EnemyFeedbackPool.new()
	world.add_child(pool)
	visuals.melee_death_cluster_enabled = true
	seed(8181)
	var expected := randi()
	seed(8181)
	pool.start_prewarm(visuals, 4, 0)
	pool.set_process(false)
	while not pool.prewarm_ready(): pool._process(1.0 / 60.0)
	check(randi() == expected, "完整预热不消耗出怪／掉落／成长的全局随机流")
	var nodes := pool.find_children("*", "Node", true, false).size()
	for index in 3:
		var effect := pool.death(source, false, visuals)
		effect.set_process(false)
	var bursts := 0
	for effect in pool.get_children():
		if effect is EnemyDeathEffect and effect._burst_only: bursts += 1
	check(bursts == 1 and pool._idle_deaths.is_empty(), "预热保留三次密集死亡触发一次集中爆点")
	check(pool.find_children("*", "Node", true, false).size() == nodes, "集中爆点同样使用完整储备，不在群杀帧创建碎屑节点")
	pool.death(source, false, visuals).set_process(false)
	check(pool.get_child_count() == 5, "超出储备按原规则扩容，不省略死亡表现")
	pool.free()

func partial_and_disabled_checks() -> void:
	var pool := EnemyFeedbackPool.new()
	world.add_child(pool)
	pool.start_prewarm(visuals, 0, 0)
	check(pool.prewarm_ready() and not pool.is_processing() and pool.get_child_count() == 0, "关闭预热时不创建储备或空转")
	pool.start_prewarm(visuals, 20, 8)
	pool._process(1.0 / 60.0)
	pool.finish_prewarm()
	check(pool.prewarm_ready() and not pool.is_processing() and pool._idle_deaths.size() == 2, "提前开战只保留已完成的两个对象，停止后台预热")
	for index in 3: pool.death(source, false, visuals).set_process(false)
	check(pool.get_child_count() == 4, "部分预热后照常播放三只尸体和集中爆点，缺少的对象即时补足")
	pool.free()
	check(MATERIALS._users == 0 and MATERIALS._cache.is_empty(), "中断预热后退出仍释放共享材质")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	camera = Camera3D.new()
	world.add_child(camera)
	source = Sprite3D.new()
	var frames := load("res://assets/meowa/slime/animations.tres") as SpriteFrames
	source.texture = frames.get_frame_texture(&"idle_front", 0)
	source.pixel_size = 0.015625
	world.add_child(source)
	visuals = load("res://data/combat/scenes/world/player/action_visuals.tres").duplicate() as PlayerActionVisuals
	visuals.melee_death_cluster_enabled = false
	sharing_checks()
	prewarm_checks()
	cluster_checks()
	partial_and_disabled_checks()
	world.queue_free()
	await process_frame
	print("Enemy feedback pool: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
