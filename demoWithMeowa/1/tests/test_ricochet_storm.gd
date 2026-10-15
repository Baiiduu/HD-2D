extends SceneTree

var checks := 0
var failures := 0
var world: Node3D
var terrain: Terrain
var player: Player
var wave: WavePrototype
var storm: RicochetStorm
var skills: RunSkills
var patches: Array[Vector2i] = []

func _initialize() -> void:
	create_timer(70.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle(frames := 3) -> void:
	for index in frames: await physics_frame

func mob(point: Vector3, health := 1000.0) -> WaveEnemy:
	assert(wave._spawn_enemy(null, point))
	var enemy := wave.enemies[-1]
	enemy.set_physics_process(false)
	enemy.spawn_delay = 0.0
	enemy.health = health
	enemy.global_position = point + Vector3.UP * 0.03
	wave._spatial_index.update(enemy)
	return enemy

func reset() -> void:
	wave.set_combat_frozen(false)
	player.body_ricochet.cancel(true)
	storm.cancel_current()
	var enemies := wave.enemies.duplicate()
	wave.enemies.clear()
	for enemy in enemies: enemy.free()
	patches.clear()
	wave.combat_modifiers.reset()
	storm.apply_skill_level(1)
	player.position = Vector3(0, 0.03, 0)
	storm.set_physics_process(false)

func fire(point := Vector3(0, 0.03, 0)) -> bool:
	var result := storm.discharge(point)
	storm.set_physics_process(false)
	return result

func tick(seconds: float) -> void:
	storm._physics_process(seconds)
	storm.set_physics_process(false)

func wall_at(point: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.1, 2, 10)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = point
	return wall

func group_at(x: float) -> Array[WaveEnemy]:
	var group: Array[WaveEnemy] = []
	for z in [-0.6, 0.0, 0.6]: group.append(mob(Vector3(x, 0, z)))
	return group

func single_target_visual_checks() -> void:
	reset()
	var first := mob(Vector3(1, 0, 0))
	check(fire() and first.health == 993.0, "单怪仍正常受到首次雷击")
	var effect := storm._effect
	check(effect._bolts.size() == 1 and effect._bolts[0].kind == RicochetStormEffect.Kind.SKY, "单怪仅有一处降雷，不画人物到怪物的传播线")
	check(effect._impacts._impacts.size() == 1 and storm._bursts.is_empty(), "单怪保留一次命中电花且没有后续传播层")
	check(effect._patches.is_empty(), "单怪不显示成片电涌，不伪造大面积受击")
	tick(0.2)
	check(first.health == 993.0, "单怪不会凭空产生第二次传播伤害")
	reset()
	first = mob(Vector3(1, 0, 0))
	var second := mob(Vector3(2.35, 0, 0))
	fire()
	check(not effect._bolts.any(func(bolt): return bolt.kind == RicochetStormEffect.Kind.CHAIN), "首片就地引雷，不从人物拉出横向连接")
	tick(0.1)
	var links: Array = effect._bolts.filter(func(bolt): return bolt.kind == RicochetStormEffect.Kind.CHAIN)
	check(second.health == 993.0 and links.size() == 1, "存在真实下一目标时才绘制传播线")
	check(links[0].from.is_equal_approx(first.global_position + Vector3.UP * storm.contact_height) and links[0].to.is_equal_approx(second.global_position + Vector3.UP * storm.contact_height), "传播线两端对应实际受击的两只怪物")
	effect.stop()
	effect.show_link(Vector3.ZERO, Vector3.RIGHT, 0.45, RicochetStormEffect.Kind.TRAIL)
	check(effect._bolts[0].parts[0].get_instance_shader_parameter("show_spine") == false, "飞行电痕只保留断续素材，不绘制传播主干")
	effect.stop()
	effect.show_link(Vector3.ZERO, Vector3.RIGHT)
	check(effect._bolts[0].kind == RicochetStormEffect.Kind.CHAIN and effect._bolts[0].parts[0].get_instance_shader_parameter("show_spine") == true, "节点复用后正确恢复真实传播线的样式")

func patch_checks() -> void:
	reset()
	var first := group_at(1.0)
	var second := group_at(2.35)
	var third := group_at(3.7)
	check(fire(), "附近有怪时可发出独立雷潮")
	check(first.all(func(enemy): return enemy.health == 993.0), "第一片三只怪在同一次调用中同时受伤")
	check(second.all(func(enemy): return enemy.health == 1000.0), "第二片保留片间节奏")
	check(patches == [Vector2i(0, 3)], "每片只发送一个批次反馈")
	check(storm._effect._patches.size() == 3 and storm._effect._bolts.filter(func(bolt): return bolt.kind == RicochetStormEffect.Kind.SKY).size() == 1, "同片三只叠成雷光面，保留一处落雷重心")
	tick(0.09)
	check(second.all(func(enemy): return enemy.health == 993.0), "第二片三只怪一起受伤，非逐只接力")
	check(storm._effect._patches.size() == 6, "下一片亮起时保留前片电涌，形成层叠推进")
	var effect := storm._effect
	var node_count := effect.get_child_count()
	effect._process(effect.patch_duration + effect.arc_duration)
	check(effect._patches.is_empty() and effect._bolts.is_empty() and not effect.is_processing(), "电涌及时结束并停止空转")
	effect.show_patch(PackedVector3Array([first[0].global_position, first[1].global_position, first[2].global_position]))
	check(effect.get_child_count() == node_count and effect._patches.size() == 3, "后续电涌复用同一组网格、材质与节点")
	check(first.all(func(enemy): return enemy.health == 993.0), "同次放电同体只命中一次")
	check(third.all(func(enemy): return enemy.health == 1000.0) and storm._bursts.is_empty(), "基础两层限制实际传播与收尾")
	tick(1.0)
	check(first[0].health == 993.0, "收尾不会递归产生新雷潮")
	check(fire(), "下一次独立放电可以重新命中同一片")
	check(first.all(func(enemy): return enemy.health == 986.0), "不同放电不共享永久免伤记录")
	reset()
	storm.apply_skill_level(4)
	for x in [1.0, 2.35, 3.7, 5.05]: group_at(x)
	check(fire(), "最高级可以对大怪群放电")
	tick(1.0)
	check(patches.size() >= 2 and storm._bursts.is_empty(), "大步长完整处理所有到期层，不丢失批次")
	check(storm.get_attack_stats().layers == 3 and storm.get_attack_stats().targets == 5, "成长实际增加层数和每片数量")

func obstruction_checks() -> void:
	reset()
	var first := mob(Vector3(1, 0, 0))
	var second := mob(Vector3(2.35, 0, 0))
	var wall := wall_at(Vector3(1.7, 0.6, 0))
	await settle()
	check(fire() and first.health == 993.0, "墙前第一片正常受击")
	tick(0.2)
	check(second.health == 1000.0, "雷潮不穿过真实墙体寻找下一片")
	wall.free()
	await settle()
	reset()
	first = mob(Vector3(1, 0, 0))
	second = mob(Vector3(2.35, 0, 0))
	check(fire(), "动态挡墙用例先锁定无墙的两片")
	wall = wall_at(Vector3(1.7, 0.6, 0))
	await settle()
	tick(0.2)
	check(second.health == 1000.0, "锁定后新出现的墙也实时阻断传播")
	wall.free()
	await settle()
	reset()
	first = mob(Vector3(1, 0, 0), 1.0)
	second = mob(Vector3(2.35, 0, 0))
	check(fire() and first.dead, "第一片可以直接击杀传导怪物")
	await settle()
	tick(0.2)
	check(second.health == 993.0, "传导怪死亡释放后仍从已锁定落点传向下一片")
	reset()
	var warning := mob(Vector3(1, 0, 0))
	warning.spawn_delay = 2.0
	var raised := mob(Vector3(1, 2, 0))
	check(not fire() and warning.health == 1000.0 and raised.health == 1000.0, "出生保护与高差资格在查墙之前过滤")

func freeze_checks() -> void:
	reset()
	var first := group_at(1.0)
	var second := group_at(2.35)
	fire()
	var remaining: float = storm._bursts[0].wait
	wave.set_combat_frozen(true)
	var effect_age: float = storm._effect._bolts[0].age
	var patch_age: float = storm._effect._patches[0].age
	tick(1.0)
	await settle(5)
	check(storm._bursts[0].wait == remaining and second[0].health == 1000.0, "升级冻结传播与伤害计时")
	check(storm._effect._bolts[0].age == effect_age, "冻结同时覆盖雷电和命中子树")
	check(storm._effect._patches[0].age == patch_age, "成片电涌的全部动画也服从战斗冻结")
	wave.set_combat_frozen(false)
	tick(0.1)
	check(second.all(func(enemy): return enemy.health == 993.0), "解冻后继续原有传播")
	reset()
	first = group_at(1.0)
	second = group_at(2.35)
	var freeze_on_hit := func(_enemy: WaveEnemy, _damage: float): wave.set_combat_frozen(true)
	storm.hit_landed.connect(freeze_on_hit, CONNECT_ONE_SHOT)
	fire()
	check(first.filter(func(enemy): return enemy.health == 993.0).size() == 1, "同片首个命中回调可立即触发升级冻结")
	wave.set_combat_frozen(false)
	tick(0.1)
	tick(0.1)
	check(first.all(func(enemy): return enemy.health == 993.0) and second.all(func(enemy): return enemy.health == 993.0), "中途冻结保留批次游标，不重伤第一只或漏掉其它怪")
	reset()
	var target := mob(Vector3(1, 0, 0))
	storm._flight_stats = storm.get_attack_stats()
	storm._launched(Vector3.RIGHT, 20.0, 1.0)
	storm.hit_landed.connect(freeze_on_hit, CONNECT_ONE_SHOT)
	storm._travelled(Vector3(0, 0.03, 0), Vector3(10, 0.03, 0), Vector3.RIGHT, 0.7)
	tick(0.7)
	check(wave.combat_frozen and storm._segments.size() == 1, "飞行路段中途升级保留尚未消费的真实位移")
	wave.set_combat_frozen(false)
	tick(0.01)
	check(storm._segments.is_empty() and target.health == 993.0, "解冻从原路段进度继续，不重复切入施放")

func flight_checks() -> void:
	reset()
	var target := mob(Vector3(1, 0, 0))
	tick(1.0)
	check(target.health == 1000.0, "人物站立时不会自动施放弹射雷潮")
	player.set_physics_process(true)
	await settle(12)
	player.set_physics_process(false)
	check(player.body_ricochet.begin_charge(Vector3.RIGHT), "真实人物可蓄力并固定技能快照")
	var before: Dictionary = storm._flight_stats.duplicate()
	storm.apply_skill_level(4)
	check(player.body_ricochet.release_charge(), "真实弹射触发已学习雷潮")
	player.body_ricochet.advance(0.15, Vector3.ZERO, false)
	tick(0.15)
	check(target.health == 993.0, "关闭基础剑术时仍由真实飞行路段独立结算雷伤")
	check(storm._flight_stats == before, "途中升级保留本次蓄力固定的技能数值")
	player.body_ricochet.cancel(true)
	reset()
	storm._flight_stats = storm.get_attack_stats()
	storm._launched(Vector3.RIGHT, 100.0, 1.0)
	target = mob(Vector3(5, 0, 0))
	storm._travelled(Vector3(0, 0.03, 0), Vector3(10, 0.03, 0), Vector3.RIGHT, 0.1)
	tick(0.1)
	check(target.health == 993.0, "低帧率高速跨过怪群也用连续轨迹找到切入点")
	check(storm._effect._bolts.size() > 0, "弹射路径产生独立电痕与成片雷击")
	var health_by_step: Array[float] = []
	for steps in [1, 10]:
		reset()
		target = mob(Vector3(1, 0, 0))
		storm._flight_stats = storm.get_attack_stats()
		storm._launched(Vector3.RIGHT, 1.0, 1.0)
		for index in steps:
			var start := Vector3(float(index) / steps, 0.03, 0)
			var end := Vector3(float(index + 1) / steps, 0.03, 0)
			storm._travelled(start, end, Vector3.RIGHT, 1.0 / steps)
			tick(1.0 / steps)
		health_by_step.append(target.health)
	check(health_by_step == [993.0, 993.0], "粗细物理步长均只雷击同体一次，伤害不随帧率变化")

func growth_and_cleanup() -> void:
	reset()
	var stats := storm.get_attack_stats()
	for attribute in [GrowthBuffDefinition.Attribute.DAMAGE, GrowthBuffDefinition.Attribute.RANGE, GrowthBuffDefinition.Attribute.COOLDOWN]:
		var buff := GrowthBuffDefinition.new()
		buff.id = StringName("storm_test_%d" % attribute)
		buff.attribute = attribute
		buff.bonus_per_level = 0.2
		wave.combat_modifiers.apply_buff(buff)
	var after := storm.get_attack_stats()
	check(is_equal_approx(after.damage, stats.damage * 1.2), "共享伤害只应用一次")
	check(is_equal_approx(after.range, stats.range * 1.2) and is_equal_approx(after.spread, stats.spread * 1.2), "范围同时改变切入和后续传导距离")
	check(is_equal_approx(after.interval, stats.interval * 0.8) and after.layer_interval == stats.layer_interval, "冷却提高放电频率，不加速完整片间表现")
	wave.owner = world
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(world)
	for property in ["damage", "trigger_radius", "spread_radius", "max_propagation_radius", "spread_layers", "targets_per_layer", "layer_interval"]:
		check(entries.any(func(item): return item.node == storm and item.property == property and item.category == "战斗与成长" and item.common), "统一战斗参数入口可调整：" + property)
	wave.owner = null
	mob(Vector3(1, 0, 0))
	fire()
	var effect := storm._effect
	var children := effect.get_child_count()
	effect.stop()
	fire()
	check(effect == storm._effect and effect.get_child_count() == children, "连续放电复用网格、材质、节点与完整命中帧")
	wave._set_phase(WavePrototype.Phase.REST)
	check(storm.skill_level == 1 and storm._bursts.is_empty() and not effect.is_processing() and effect._impacts._impacts.is_empty() and effect._patches.is_empty(), "清波保留已学技能并清理雷电、电涌与声音")
	wave._set_phase(WavePrototype.Phase.BATTLE)
	check(storm.skill_level == 1, "下一波继承技能等级")
	wave._set_phase(WavePrototype.Phase.READY)
	check(storm.skill_level == 0 and not storm.is_physics_processing(), "重试重新清空学习状态且闲置无物理更新")

func balance_and_outward_checks() -> void:
	reset()
	var expected := [Vector4(7.0, 0.42, 2, 3), Vector4(8.4, 0.42, 2, 4), Vector4(9.8, 0.378, 3, 4), Vector4(11.2, 0.336, 3, 5)]
	for index in expected.size():
		var stats := storm.get_attack_stats(index + 1)
		check(is_equal_approx(stats.damage, expected[index].x) and is_equal_approx(stats.interval, expected[index].y), "各级雷伤和放电间隔采用补伤基线：%d" % (index + 1))
		check(stats.layers == int(expected[index].z) and stats.targets == int(expected[index].w), "各级覆盖预算实际收紧：%d" % (index + 1))
		check(stats.range == 1.25 and stats.spread == 1.5 and stats.max_radius == 3.6, "技能升级不继续扩大传播距离：%d" % (index + 1))
	var range_buff := load("res://data/growth/range.tres") as GrowthBuffDefinition
	for index in 30: wave.combat_modifiers.apply_buff(range_buff)
	var grown := storm.get_attack_stats(4)
	check(grown.range == 3.6 and grown.spread == 3.6 and grown.max_radius == 3.6, "高层共享范围成长仍受真实传播总边界约束")
	reset()
	var first := mob(Vector3(1, 0, 0))
	var outward := mob(Vector3(2.4, 0, 0))
	var inward := mob(Vector3(1.75, 0, 1.25))
	var stats := storm.get_attack_stats()
	stats.targets = 1
	stats.layers = 4
	check(storm.discharge(Vector3(0, 0.03, 0), stats), "只向外传导用例正常起手")
	tick(1.0)
	check(first.health == 993.0 and outward.health == 993.0, "向外相邻目标仍能正常接力")
	check(inward.health == 1000.0, "预算未耗尽也不折回更靠近触发点的目标")
	reset()
	var line: Array[WaveEnemy] = []
	for x in [1.0, 2.3, 3.5, 4.7]: line.append(mob(Vector3(x, 0, 0)))
	check(storm.discharge(Vector3(0, 0.03, 0), stats), "传播边界用例正常起手")
	tick(1.0)
	check(line.slice(0, 3).all(func(enemy): return enemy.health == 993.0), "总半径以内的有效向外连接正常命中")
	check(line[3].health == 1000.0, "层数和单跳距离尚有预算也不能超过总传播半径")
	reset()
	first = mob(Vector3(1, 0, 0))
	var moving := mob(Vector3(2.35, 0, 0))
	fire()
	moving.global_position = Vector3(0.4, 0.03, 0.5)
	wave._spatial_index.update(moving)
	tick(0.2)
	check(moving.health == 1000.0, "目标锁定后移向内侧，到期也不允许回传")
	reset()
	first = mob(Vector3(1, 0, 0))
	moving = mob(Vector3(2.35, 0, 0))
	fire()
	moving.global_position = Vector3(3.5, 0.03, 0)
	wave._spatial_index.update(moving)
	tick(0.2)
	check(moving.health == 1000.0, "目标锁定后移出单跳距离，到期不会隔空追击")
	reset()
	first = mob(Vector3(1, 0, 0))
	moving = mob(Vector3(2.35, 0, 0))
	stats.spread = 3.6
	storm.discharge(Vector3(0, 0.03, 0), stats)
	moving.global_position = Vector3(4, 0.03, 0)
	wave._spatial_index.update(moving)
	tick(0.2)
	check(moving.health == 1000.0, "共享范围足够覆盖单跳时，移动目标仍不能越过总边界")
	check(storm.describe_skill_upgrade(0, 1).contains("同次弹射每怪一次"), "初始学习卡明确说明整次弹射的去重规则")

func flight_budget_checks() -> void:
	reset()
	var first := mob(Vector3(1, 0, 0))
	var second := mob(Vector3(2.35, 0, 0))
	var stats := storm.get_attack_stats()
	var contacts := {}
	check(storm.discharge(Vector3(0, 0.03, 0), stats, contacts), "首次放电预留未落雷的后续目标")
	check(not storm.discharge(Vector3(0, 0.03, 0), stats, contacts), "重叠放电不会再次选择已命中或尚未落雷的同体")
	var fresh := mob(Vector3(0.8, 0, 0.8))
	check(storm.discharge(Vector3(0, 0.03, 0), stats, contacts), "去重后仍可继续放电命中新目标")
	tick(0.2)
	check([first, second, fresh].all(func(enemy): return enemy.health == 993.0), "同次弹射不同批次和不同传播层对同体合计只伤一次")
	check(contacts.values().all(func(value): return value == 1), "所有已落雷目标保留本次弹射命中记录")
	check(not storm.discharge(Vector3(2.35, 0.03, 0), stats, contacts), "人物折返到怪群中也不能重复雷击")
	reset()
	first = mob(Vector3(1, 0, 0))
	storm._flight_stats = storm.get_attack_stats()
	storm._launched(Vector3.RIGHT, 1.0, 1.0)
	for heading in [Vector3.RIGHT, Vector3.LEFT]:
		var start := Vector3(0, 0.03, 0) if heading == Vector3.RIGHT else Vector3(1, 0.03, 0)
		storm._travelled(start, start + heading, heading, 0.5)
		tick(0.5)
	check(first.health == 993.0, "真实往返路段共享整次弹射命中预算")
	storm._launched(Vector3.RIGHT, 1.0, 1.0)
	storm._travelled(Vector3(0, 0.03, 0), Vector3(1, 0.03, 0), Vector3.RIGHT, 0.5)
	tick(0.5)
	check(first.health == 986.0, "下一次弹射重新获得对同体的一次雷伤")
	reset()
	first = mob(Vector3(1, 0, 0))
	second = mob(Vector3(2.35, 0, 0))
	storm._flight_stats = storm.get_attack_stats()
	storm._launched(Vector3.RIGHT, 1.0, 1.0)
	var previous: Dictionary = storm._flight_contacts
	storm.discharge(Vector3(0, 0.03, 0), stats, previous)
	storm._launched(Vector3.RIGHT, 1.0, 1.0)
	tick(0.2)
	check(second.health == 993.0 and storm._flight_contacts.is_empty(), "上次弹射的延迟落雷不会污染新一次弹射的命中记录")
	check(storm.discharge(Vector3(2.35, 0.03, 0), stats, storm._flight_contacts) and second.health == 986.0, "快速再次弹射仍有独立的伤害预算")
	reset()
	first = mob(Vector3(1, 0, 0))
	second = mob(Vector3(2.35, 0, 0))
	contacts = {}
	storm.discharge(Vector3(0, 0.03, 0), stats, contacts)
	var wall := wall_at(Vector3(1.7, 0.6, 0))
	await settle()
	tick(0.2)
	check(second.health == 1000.0 and not contacts.has(second.get_instance_id()), "动态墙导致的未命中释放预留，不错误消耗整次弹射机会")
	wall.free()
	await settle()
	check(storm.discharge(Vector3(1.2, 0.03, 0), stats, contacts) and second.health == 993.0, "墙移除后切入仍可命中先前未实际受伤的怪物")

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	world = Node3D.new()
	terrain = Terrain.new()
	terrain.data = TerrainData.new()
	terrain.data.size = Vector2i.ZERO
	terrain.data.resize(Vector2i(-12, -12), Vector2i(25, 25))
	world.add_child(terrain)
	player = Player.new()
	player.name = "Player"
	player.ricochet_rules = PlayerRicochetRules.new()
	player.sword_rules = PlayerSwordRules.new()
	player.sword_rules.enabled = false
	player.action_visuals = PlayerActionVisuals.new()
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 1.06592
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	player.add_child(shape)
	world.add_child(player)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 9, 14)
	camera.rotation_degrees.x = -32
	world.add_child(camera)
	player.movement_camera = camera
	wave = load("res://scenes/combat/wave_prototype.tscn").instantiate()
	wave.player = player
	wave.terrain = terrain
	wave.battle_area = Rect2(-10, -10, 20, 20)
	wave.show_ui = false
	world.add_child(wave)
	root.add_child(world)
	current_scene = world
	player.set_physics_process(false)
	wave.set_physics_process(false)
	await settle(12)
	storm = wave.get_node("RicochetStorm")
	storm.audio_enabled = false
	storm.patch_landed.connect(func(layer: int, count: int): patches.append(Vector2i(layer, count)))
	skills = wave.get_node("RunSkills")
	var growth := wave.get_node("RunGrowth") as RunGrowth
	growth.set_physics_process(false)
	growth.cards_per_draw = 100
	growth.choice_ui.open_duration = 0.0
	skills.initial_choice.open_duration = 0.0
	skills.initial_cards_per_draw = 100
	check(storm.skill_level == 0 and not storm.is_physics_processing() and not storm._effect, "正式技能组件未学时不创建特效或执行攻击")
	check(wave.start_run() and skills._initial_offered.has(&"initial:ricochet_storm"), "独立雷潮进入正式初始技能池")
	skills.initial_choice.select_option(&"initial:ricochet_storm")
	skills.initial_choice.confirm_selection()
	check(storm.skill_level == 1 and skills.get_slots().size() == 1 and skills.get_slots()[0].id == "ricochet_storm", "实际选择只学习雷潮并显示技能栏")
	wave._spawn_queue.clear()
	check(skills.candidates().any(func(card): return card.id == &"skill:ricochet_storm:2"), "升级池提供雷潮强化")
	growth._grant_experience(10)
	check(growth.choice_ui.is_open and wave.combat_frozen, "经验升级复用现有冻结选择")
	growth.choice_ui.select_option(&"skill:ricochet_storm:2")
	growth.choice_ui.confirm_selection()
	check(storm.skill_level == 2 and not wave.combat_frozen, "实际升级选择改变雷潮等级")
	single_target_visual_checks()
	patch_checks()
	await obstruction_checks()
	await freeze_checks()
	await flight_checks()
	balance_and_outward_checks()
	await flight_budget_checks()
	growth_and_cleanup()
	for voice in root.find_children("*", "AudioStreamPlayer", true, false): voice.stop()
	await create_timer(0.1).timeout
	world.queue_free()
	await settle()
	print("Ricochet storm: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
