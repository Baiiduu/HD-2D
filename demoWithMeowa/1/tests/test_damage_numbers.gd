extends SceneTree

var checks := 0
var failures := 0
var world: Node3D
var session: WavePrototype
var numbers: DamageNumbers
var camera: Camera3D
var events: Array[CombatDamageEvent] = []

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle(count := 3) -> void:
	for frame in count: await process_frame

func enemy(health := 20.0) -> WaveEnemy:
	var mob := WaveEnemy.new()
	mob.wave_mode = true
	mob.health = health
	mob.definition = WaveEnemyDefinition.new()
	mob.combat_active = func(): return session.phase == WavePrototype.Phase.BATTLE and not session.combat_frozen
	world.add_child(mob)
	session.enemy_spawned.emit(mob)
	mob.damaged.connect(func(event): events.append(event))
	return mob

func hit(target_id := 1, style: StringName = &"normal") -> CombatDamageEvent:
	var event := CombatDamageEvent.new()
	event.amount = 24.0
	event.target_id = target_id
	event.world_position = Vector3(0.5, 0.8, 0)
	event.style = style
	event.direction = Vector3.RIGHT
	return event

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 5, 10)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	session = preload("res://tests/fixtures/ricochet_session.gd").new()
	world.add_child(session)
	session.phase = WavePrototype.Phase.BATTLE
	numbers = preload("res://scenes/combat/damage_numbers.tscn").instantiate()
	numbers.session = session
	session.add_child(numbers)
	numbers.owner = session
	check(numbers.get_pool_stats().idle == numbers.number_prewarm, "进入时预热节点")
	check(not numbers.is_processing(), "没有数字时不逐帧工作")
	check(numbers in session._combat_nodes, "显示层使用共享战斗冻结")
	var mob := enemy()
	numbers._watch_enemy(mob)
	mob.take_damage(0)
	mob.take_damage(-1)
	mob.take_damage(NAN)
	mob.take_damage(INF)
	check(events.is_empty() and numbers._active.is_empty() and mob.health == 20, "无效伤害不产生数字或扣血")
	mob.spawn_delay = 0.5
	mob.take_damage(10)
	check(events.is_empty() and mob.health == 20, "出场预告不产生假命中")
	mob.spawn_delay = 0
	session.set_combat_frozen(true)
	mob.take_damage(10)
	check(events.is_empty(), "战斗冻结拒绝命中")
	session.set_combat_frozen(false)
	mob.take_damage(7.25, {"source": &"A02", "style": &"lightning", "direction": Vector3.RIGHT})
	check(events.size() == 1 and numbers._active.size() == 1, "一笔有效扣血只生成一次数字")
	var event := events[0]
	check(event.amount == 7.25 and event.requested_amount == 7.25 and event.source == &"A02" and event.style == &"lightning", "命中保存真实数值与来源标签")
	check(not event.lethal and event.target_id == mob.get_instance_id(), "非致死命中目标正确")
	check(event.world_position == mob.get_damage_feedback_position(), "锚点使用怪物身体高度")
	check(numbers._active[0].style.style_id == &"lightning", "雷电来源使用独立样式")
	var position_before := event.world_position
	mob.position = Vector3(4, 0, 0)
	check(event.world_position == position_before, "飘字不被怪物后续移动拖走")
	numbers.clear()
	events.clear()
	var dead_id := mob.get_instance_id()
	mob.take_damage(999)
	check(events.size() == 1 and events[0].lethal and events[0].amount == 12.75 and events[0].requested_amount == 999, "致死溢出只显示实际扣血，保留请求值")
	mob.take_damage(10)
	check(events.size() == 1, "死亡对象不重复受伤或飘字")
	await settle()
	check(not is_instance_id_valid(dead_id) and numbers._active.size() == 1, "怪物释放后致死数字继续播放")
	session.phase = WavePrototype.Phase.REST
	check(numbers._active.size() == 1, "正常清波不会截断最后一次反馈")
	numbers.clear()
	numbers.present(hit())
	var number := numbers._active[0]
	var begin_y := number.motion_offset.y
	numbers._process(0.21)
	check(number.motion_offset.y < begin_y - 20.0, "起跳后明显升至顶点")
	var apex_y := number.motion_offset.y
	numbers._process(0.25)
	check(number.motion_offset.y > apex_y, "顶点后沿弧线回落")
	numbers._process(0.20)
	check(number.opacity < 1.0 and number.opacity > 0.0, "末段逐渐淡出")
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		camera.position = Vector3(0, 5, 10).rotated(Vector3.UP, angle)
		camera.look_at(Vector3.ZERO)
		number.advance(0.0, camera)
		check(number.visible and number.anchor_screen.is_equal_approx(camera.unproject_position(number.event.world_position)), "旋转相机后仍锚定同一世界命中点")
	camera.look_at(camera.position * 2.0)
	number.advance(0.0, camera)
	check(not number.visible, "相机背后的数字不镜像投射到屏幕")
	camera.look_at(Vector3.ZERO)
	number.advance(0.0, camera)
	check(number.visible, "镜头转回可恢复仍在生命周期中的数字")
	number.advance(0.0, null)
	check(not number.visible, "相机暂时缺失时安全隐藏")
	number.advance(0.0, camera)
	var age_before := number.age
	session.set_combat_frozen(true)
	await settle(6)
	check(number.age == age_before, "升级冻结同时冻结数字动画")
	session.set_combat_frozen(false)
	await settle(2)
	check(number.age > age_before, "解除冻结后继续动画")
	numbers.clear()
	for index in 5: numbers.present(hit())
	var offsets := {}
	for active in numbers._active: offsets[active.motion_offset] = true
	check(offsets.size() == 5 and numbers.get_pool_stats().active == 5, "同帧五次命中分槽错开，不合并伤害")
	var profile := numbers.style_for(&"normal")
	var font := profile.number_font if profile.number_font else ThemeDB.fallback_font
	var text_width := font.get_string_size("24", HORIZONTAL_ALIGNMENT_LEFT, -1, profile.number_font_size).x
	check(absf(numbers._active[1].motion_offset.x - numbers._active[0].motion_offset.x) > text_width, "分槽间距覆盖真实字宽，避免相邻数字重叠")
	check(numbers._active[0].mouse_filter == Control.MOUSE_FILTER_IGNORE, "数字不拦截鼠标攻击输入")
	numbers.enabled = false
	numbers.present(hit())
	check(numbers._active.is_empty() and not numbers.is_processing() and numbers._lanes.is_empty(), "关闭时清理全部数字与分槽状态")
	numbers.enabled = true
	var normal := numbers.style_for(&"normal")
	check(numbers.style_for(&"future_unknown") == normal, "未知标签回退普通样式")
	var custom := DamageNumberStyle.new()
	custom.style_id = &"future_poison"
	custom.number_color = Color.GREEN
	numbers.number_styles.append(custom)
	numbers.present(hit(9, &"future_poison"))
	check(numbers._active[0].style == custom, "追加资源即可接入新表现")
	for value in [0.00001, 0.005, 0.4, 1.0, 24.5, 1000000.0]:
		check(normal.format_amount(value).to_float() > 0 or normal.format_amount(value).begins_with("<"), "小伤害不会显示为零")
	check(numbers.style_for(&"critical").format_amount(168) == "168!", "特殊样式支持独立后缀")
	numbers.clear()
	var invalid := hit()
	invalid.amount = NAN
	numbers.present(invalid)
	invalid = hit()
	invalid.world_position = Vector3.INF
	numbers.present(invalid)
	check(numbers._active.is_empty(), "直接接入也拒绝坏数值")
	var large := hit(88, &"critical")
	large.amount = 123456
	large.world_position = camera.project_position(Vector2(-140, root.size.y * 0.5), 10)
	numbers.present(large)
	check(numbers._active[0].visible, "大数字部分字面仍在画面内时不会按锚点提前裁掉")
	large = hit(89, &"critical")
	large.amount = 123456
	large.world_position = camera.project_position(Vector2(-800, root.size.y * 0.5), 10)
	numbers.present(large)
	check(not numbers._active[1].visible, "大数字整体离屏后仍正常隐藏")
	numbers.clear()
	# 超过闲置上限的真实命中仍全部显示，回收后只保留允许的节点。
	for index in 200: numbers.present(hit(index))
	check(numbers.get_pool_stats().active == 200 and numbers._lanes.size() == 200, "密集命中不因对象池上限漏数字")
	numbers._process(2.0)
	check(numbers.get_pool_stats().active == 0 and numbers._lanes.is_empty() and numbers.get_pool_stats().idle == numbers.number_idle_limit, "到期回收并释放多余节点与目标状态")
	check(not numbers.is_processing(), "回收完毕停止逐帧工作")
	var created_before: int = numbers.get_pool_stats().created
	for index in 64: numbers.present(hit(index))
	check(numbers.get_pool_stats().created == created_before, "后续命中复用已有节点")
	numbers.number_idle_limit = 8
	check(numbers.get_pool_stats().idle == 8 and numbers.get_pool_stats().active == 64, "运行时缩小闲置池立即生效，不截断活跃数字")
	session.run_started.emit()
	check(numbers._active.is_empty(), "新局清空旧飘字")
	numbers.present(hit())
	session.run_ended.emit("结束")
	check(numbers._active.is_empty(), "结束和撤退清空飘字")
	var catalog := preload("res://addons/parameter_hub/catalog.gd").new()
	var properties := {}
	for entry in catalog.collect(session):
		if entry.object == numbers or entry.object == normal: properties[entry.property] = entry
	for property in ["number_styles", "number_stack_spacing", "number_font", "number_font_size", "number_lifetime", "rise_pixels", "pop_scale"]:
		check(properties.has(property) and properties[property].category == "战斗与成长" and properties[property].common, "关键参数可在统一入口编辑：" + property)
	catalog.entries.clear()
	world.queue_free()
	await settle(4)
	print("Damage numbers: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
