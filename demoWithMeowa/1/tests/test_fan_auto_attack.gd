extends SceneTree

var scene: Node3D
var wave: WavePrototype
var player: Player
var fan: FanAutoAttack
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(40.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func settle(count := 5) -> void:
	for frame in count: await physics_frame

func enemy_at(offset: Vector3) -> WaveEnemy:
	assert(wave._spawn_enemy())
	var enemy := wave.enemies[-1]
	enemy.set_physics_process(false)
	enemy.spawn_delay = 0.0
	enemy.health = 500.0
	enemy.global_position = player.global_position + offset
	return enemy

func remove_enemies() -> void:
	for enemy in wave.enemies.duplicate():
		enemy.spawn_delay = 0.0
		enemy.take_damage(10000.0)
	fan.cancel_current()
	fan._cooldown = 0.0

func strike(step := 1.0 / 60.0) -> void:
	fan.cancel_current()
	fan._cooldown = 0.0
	assert(fan.start_swing())
	for frame in ceili((fan.windup_time + fan.sweep_time + fan.fade_time + 0.01) / step):
		fan._physics_process(step)

func run() -> void:
	scene = load("res://scenes/world/world.tscn").instantiate()
	scene.get_node("WavePrototype/RunGrowth").enabled = false
	# 布局可变；攻击夹具只保留地形，随后用真实碰撞墙验证阻挡。
	var props := scene.get_node("WorldDetails")
	scene.remove_child(props)
	props.free()
	for prop in scene.get_children():
		if prop is PlazaProp:
			scene.remove_child(prop)
			prop.free()
	scene.get_node("LoadoutUI").save_enabled = false
	scene.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(scene)
	current_scene = scene
	await settle(12)
	wave = scene.get_node("WavePrototype")
	player = scene.get_node("Player")
	fan = wave.get_node("FanAutoAttack")
	check(fan.frames and fan.frames.get_frame_count(&"slash") == 8 and not fan.frames.get_animation_loop(&"slash"), "Meowa supplies eight transparent non-looping slash frames")
	player.set_physics_process(false)
	wave.set_physics_process(false)
	fan.set_physics_process(false)
	player.global_position = wave.global_position + Vector3.UP * 0.03
	var skills: RunSkills = wave.get_node("RunSkills")
	# 动作夹具需要固定 A01；抽三张的随机规则由成长测试覆盖。
	skills.initial_cards_per_draw = skills.skill_paths.size()
	check(wave.start_run(), "New battlefield entrance starts the wave")
	skills.initial_choice.open_duration = 0.0
	# 重新呈现已抽到的同一组卡，让动作测试立即可选择。
	skills.initial_choice.present_choices(skills._initial_cards)
	check(skills.initial_choice.select_option(&"initial:fan_slash"), "A01 is selected through the actual initial choice")
	skills.initial_choice.confirm_selection()
	fan.set_physics_process(false)
	wave._spawn_queue.clear()
	player.global_position = scene.get_node("BattleArea").global_position + Vector3.UP * 0.03
	fan.knockback_distance = 0.0
	var primary := enemy_at(Vector3(0, 0, -1.0))
	var left := enemy_at(Vector3(-0.9, 0, -1.5))
	var right := enemy_at(Vector3(0.9, 0, -1.5))
	var side := enemy_at(Vector3(2.0, 0, 0))
	var behind := enemy_at(Vector3(0, 0, 1.6))
	var far := enemy_at(Vector3(0, 0, -3.0))
	var raised := enemy_at(Vector3(0.5, 0.8, -1.6))
	check(fan.nearest_target() == primary, "Nearest visible in-range target selects direction")
	check(fan.start_swing(), "A01 begins independently of player animation")
	check(fan.direction.dot(Vector3.FORWARD) > 0.999, "Direction is in world space")
	fan._physics_process(0.05)
	check(primary.health == 500.0 and not fan._mesh.visible, "Windup does not deal hidden damage")
	fan._physics_process(0.14)
	check(primary.health == 490.0 and left.health == 490.0 and right.health == 500.0, "Sweep damages left then center before reaching right")
	fan._physics_process(0.09)
	check(right.health == 490.0, "One sweep can hit multiple enemies")
	check(fan._mesh.visible and fan._material.get_shader_parameter("frame_rect") == Vector4(0.75, 0.5, 0.25, 0.5), "The shader samples the current atlas frame rather than the full sheet")
	check(side.health == 500.0 and behind.health == 500.0 and far.health == 500.0 and raised.health == 500.0, "Fan angle, range and terrain height limit hits")
	fan._physics_process(0.05)
	check(primary.health == 490.0 and left.health == 490.0 and right.health == 490.0, "Each target is hit once per sweep")
	check(not fan.start_swing(), "Attack interval prevents extra swings")
	# QE 不改变锁定方向；移动不会中断攻击或操作人物动画。
	fan.cancel_current()
	fan._cooldown = 0.0
	check(fan.start_swing(), "Second independent swing begins")
	var aim := fan.direction
	var animation_resource := player.animations
	var camera := scene.get_node("MapEffects/Camera3D") as FollowCamera
	camera.yaw_degrees += 90.0
	camera.snap_to_target()
	player.global_position.x += 0.2
	fan._physics_process(fan.windup_time + 0.05)
	check(fan.direction == aim and fan.global_position.distance_to(wave._ground_target()) < 0.01, "QE leaves aim fixed and the effect follows movement")
	check(player.animations == animation_resource, "A01 preserves the existing player animation resource")
	var elapsed := fan._elapsed
	var remaining := fan._cooldown
	wave.set_combat_frozen(true)
	check(fan.process_mode == Node.PROCESS_MODE_DISABLED, "The attack participates in combat-only freeze")
	await settle()
	check(fan._elapsed == elapsed and fan._cooldown == remaining and fan._swinging, "Growth freeze preserves the swing and cooldown instead of cancelling it")
	wave.set_combat_frozen(false)
	check(fan.process_mode != Node.PROCESS_MODE_DISABLED and fan._swinging, "The same swing resumes after combat freeze")
	var cooldown := fan._cooldown
	var blink_start := player.global_position
	var path_enemy := enemy_at(Vector3(2.5, 0, -0.3))
	var landing_enemy := enemy_at(Vector3(5.0, 0, 0) + aim)
	var path_health := path_enemy.health
	var landing_health := landing_enemy.health
	var hit_ids := fan._hits.duplicate()
	player.global_position += Vector3.RIGHT * 5.0
	player.blink_travelled.emit(blink_start, player.global_position)
	check(fan._swinging and fan._mesh.visible and fan._cooldown == cooldown and fan._elapsed == elapsed and fan.direction == aim and fan._hits == hit_ids, "Blink preserves the same swing, locked direction, hit history and cooldown")
	check(fan.global_position.distance_to(wave._ground_target()) < 0.01 and path_enemy.health == path_health and landing_enemy.health == landing_health, "Blink moves the effect immediately without dealing teleport-path damage")
	fan._physics_process(0.05)
	check(landing_enemy.health == landing_health - 10.0 and path_enemy.health == path_health, "The ongoing sweep can hit at the landing position without sweeping the travel path")
	fan._physics_process(0.05)
	check(landing_enemy.health == landing_health - 10.0, "Blink does not give the same sweep another hit on its target")
	player.global_position = blink_start
	player.global_position.x -= 0.2
	remove_enemies()
	# 墙体不只阻挡目标选择，也裁切特效扇面。
	primary = enemy_at(Vector3(0, 0, -1.5))
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 0.15)
	collision.shape = box
	wall.add_child(collision)
	scene.add_child(wall)
	wall.global_position = player.global_position + Vector3(0, 0.5, -0.7)
	await settle()
	check(fan.nearest_target() == null and not fan.start_swing(), "A01 cannot target through walls")
	check(fan._surface_limit(wave._ground_target(), 0.0) < 0.7, "The visible slash stops at the wall")
	wall.free()
	await settle()
	# 运行时参数影响真实判定，特效仍使用同一世界范围。
	fan.damage = 15.0
	fan.attack_range = 3.8
	fan.fan_angle = 140.0
	fan.attack_interval = 1.2
	far = enemy_at(Vector3(0, 0, -3.1))
	left = enemy_at(Vector3(-2.0, 0, -1.2))
	strike(1.0 / 30.0)
	check(primary.health == 485.0 and far.health == 485.0 and left.health == 485.0, "Damage, range and angle parameters change actual hits")
	var before := primary.health
	strike(1.0 / 120.0)
	check(primary.health == before - 15.0, "Higher frame rate cannot multiply damage")
	# 无有效目标不空挥；标准史莱姆两击击杀，击退受到真实碰撞限制。
	remove_enemies()
	check(not fan.start_swing(), "Empty battlefield holds the attack ready")
	fan.damage = 10.0
	fan.attack_range = 2.4
	fan.fan_angle = 100.0
	fan.attack_interval = 0.8
	fan.knockback_distance = 0.25
	primary = enemy_at(Vector3(0, 0, -1.2))
	primary.health = 20.0
	var original := primary.global_position
	strike()
	check(primary.health == 10.0 and primary.global_position.distance_to(original) > 0.2, "A hit gives one damage event and light physical knockback")
	var kills := wave.kills
	strike()
	check(primary.dead and wave.kills == kills + 1, "Standard slime dies after two hits and counts once")
	# 清波、失败和重试不得留下玩家攻击或额外伤害。
	wave._physics_process(0.01)
	check(wave.phase == WavePrototype.Phase.REST and not fan._mesh.visible and not fan._swinging, "Clear removes the slash before safe rest")
	fan._physics_process(10.0)
	check(not fan._mesh.visible and wave.enemies.is_empty(), "Rest does not keep attacking")
	check(wave.start_next_wave(), "Next wave can start after rest")
	wave._spawn_queue.clear()
	primary = enemy_at(Vector3(0, 0, -1.2))
	check(fan.start_swing(), "A01 is ready in the new wave")
	player.take_damage(player.max_health)
	wave._physics_process(0.01)
	check(wave.phase == WavePrototype.Phase.RESULT and not fan._swinging and not fan._mesh.visible, "Failure cancels a pending swing")
	wave.retry()
	check(fan._cooldown == 0.0 and not fan._swinging, "Retry does not resume old damage or effects")
	print("A01 fan attack: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await settle()
	await create_timer(0.3).timeout
	quit(1 if failures else 0)
