extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var scene: Node3D = load("res://scenes/world/world.tscn").instantiate()
	scene.get_node("LoadoutUI").save_enabled = false
	scene.get_node("WavePrototype/RunGrowth").enabled = false
	scene.get_node("WavePrototype/FanAutoAttack").enabled = false
	root.add_child(scene)
	current_scene = scene
	for frame in 12: await physics_frame
	var wave: WavePrototype = scene.get_node("WavePrototype")
	var skills: RunSkills = wave.get_node("RunSkills")
	# 接触预算测试固定获得所选技能，避免新增技能后随机首选卡漏掉 A01。
	skills.initial_cards_per_draw = 100
	var player: Player = scene.get_node("Player")
	player.set_physics_process(false)
	wave.set_physics_process(false)
	player.global_position = wave.global_position + Vector3.UP * 0.03
	assert(wave.start_run())
	var initial_choice := scene.get_node_or_null("WavePrototype/RunSkills/InitialSkillChoice") as GrowthChoiceUI
	if initial_choice and initial_choice.is_open:
		initial_choice.reveal_now()
		initial_choice.select_option(&"initial:fan_slash")
		initial_choice.confirm_selection()
	for component: Node in skills._components.values():
		component.process_mode = Node.PROCESS_MODE_DISABLED
	scene.get_node("WavePrototype/FanAutoAttack").enabled = false
	var pierce := scene.get_node_or_null("WavePrototype/LightPierceAutoAttack")
	if pierce: pierce.set("enabled", false)
	wave._spawn_queue.clear()
	var definition: WaveEnemyDefinition = load("res://data/enemies/wave_slime.tres").duplicate()
	definition.scene = load("res://tests/fixtures/contact_query_slime.tscn")
	definition.move_speed = 0.0
	assert(wave._spawn_enemy(definition))
	var slime: SlimeEnemy = wave.enemies[-1]
	slime.set_physics_process(false)
	slime.spawn_delay = 0.0
	slime.gravity = 0.0
	# 战区中心现已摆放建筑；接触测试使用开波入口的空地。
	player.global_position = wave.global_position + Vector3.UP * 0.03
	slime.global_position = player.global_position + Vector3.RIGHT * 0.5
	for frame in 3: await physics_frame
	var before := player.current_health
	slime._combat_tick(1.0 / 60)
	check(player.current_health == before and slime.get("sight_queries") == 0,
		"开波初始保护保留，并跳过无效遮挡查询")
	wave._hurt_clock = 0.0
	slime._combat_tick(1.0 / 60)
	check(player.current_health == before - slime.attack_damage and slime.get("sight_queries") == 1,
		"合法接触仍做实时遮挡检查并结算一次伤害")
	for tick in 120: slime._combat_tick(1.0 / 60)
	check(slime.get("sight_queries") == 1 and player.current_health == before - slime.attack_damage,
		"受击保护期间的 120 次接触不重复做射线或扣血")
	wave._hurt_clock = 0.0
	slime._combat_tick(1.0 / 60)
	check(slime.get("sight_queries") == 2 and player.current_health == before - slime.attack_damage * 2,
		"保护结束后恢复实时查询与原伤害")
	wave._hurt_clock = 0.0
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.1, 2.0, 2.0)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	wall.global_position = player.global_position + Vector3.RIGHT * 0.25 + Vector3.UP * 0.8
	for frame in 3: await physics_frame
	slime._combat_tick(1.0 / 60)
	check(slime.get("sight_queries") == 3 and player.current_health == before - slime.attack_damage * 2,
		"可受击时仍精确检查新挡墙，不穿墙攻击")
	wall.free()
	wave.set_combat_frozen(true)
	check(not slime.can_damage_player.call(slime.attack_damage), "成长冻结时共同攻击资格失效")
	wave.set_combat_frozen(false)
	for frame in 3: await physics_frame
	slime.attack_damage = 0.0
	slime._combat_tick(1.0 / 60)
	check(slime.get("sight_queries") == 3, "零伤害攻击不做无效查询")
	slime.attack_damage = definition.attack_damage
	var eligible := slime.can_damage_player
	check(eligible.call(slime.attack_damage), "未来敌方弹丸或区域可使用同一资格接口")
	wave._finish("budget test", WavePrototype.Outcome.RETREAT)
	check(not eligible.call(slime.attack_damage), "旧战斗回调结束后失效")
	scene.free()
	for frame in 3: await process_frame
	print("Enemy attack budget: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
