extends SceneTree

const PROBE := preload("res://tests/fixtures/wave_probe_enemy.gd")
var scene: Node3D
var wave: WavePrototype
var player: Player

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func settle(frames := 5) -> void:
	for frame in frames: await physics_frame

func probe_definition() -> WaveEnemyDefinition:
	var node := PROBE.new()
	var packed := PackedScene.new()
	assert(packed.pack(node) == OK)
	node.free()
	var definition := WaveEnemyDefinition.new()
	definition.scene = packed
	definition.health = 30.0
	definition.move_speed = 0.0
	definition.attack_damage = 3.0
	return definition

func freeze_enemies() -> void:
	for enemy in wave.enemies: enemy.set_physics_process(false)

func run() -> void:
	scene = load("res://scenes/world/world.tscn").instantiate()
	scene.get_node("WavePrototype/RunGrowth").enabled = false
	scene.get_node("LoadoutUI").save_enabled = false
	root.add_child(scene)
	current_scene = scene
	await settle(12)
	wave = scene.get_node("WavePrototype")
	wave.endless_mode = false
	wave.waves.clear()
	wave.max_spawns_per_tick = 1 # 旧接口测试逐只检查生命周期。
	wave.get_node("FanAutoAttack").enabled = false
	player = scene.get_node("Player")
	player.set_physics_process(false)
	wave.set_physics_process(false)
	player.global_position = wave.global_position + Vector3.UP * 0.03
	assert(wave.start_run())
	# 定时生成有真实预告；出生安全距离与可达路线均满足。
	wave._physics_process(0.31)
	assert(wave.enemies.size() == 1 and wave._pending == 4)
	var slime := wave.enemies[0] as SlimeEnemy
	slime.set_physics_process(false)
	assert(slime and slime.health == 20.0 and slime.spawn_delay > 0.0)
	assert(TerrainPath.horizontal_distance(slime.global_position, player.global_position) >= wave.spawn_safe_distance)
	assert(not wave._path.route(slime.global_position, wave._ground_target()).is_empty())
	var before := player.current_health
	slime.take_damage(10.0)
	slime._physics_process(0.1)
	assert(slime.health == 20.0 and player.current_health == before)
	slime.spawn_delay = 0.0
	slime.take_damage(10.0)
	assert(slime.health == 10.0)
	slime.take_damage(10.0)
	slime.take_damage(10.0)
	assert(wave.kills == 1 and wave.enemies.is_empty())
	wave._physics_process(0.01)
	assert(wave.phase == WavePrototype.Phase.BATTLE, "Pending spawns prevent early clear")
	wave._clear_wave()
	assert(wave.phase == WavePrototype.Phase.BATTLE, "Clear cannot bypass the pending queue")
	# 同屏上限只延后队列；击杀后继续补怪。
	wave.max_active_enemies = 1
	wave._physics_process(1.3)
	freeze_enemies()
	assert(wave.enemies.size() == 1 and wave._pending == 3)
	wave._physics_process(10.0)
	assert(wave.enemies.size() == 1 and wave._pending == 3)
	wave.enemies[0].spawn_delay = 0.0
	wave.enemies[0].take_damage(100.0)
	wave._physics_process(0.01)
	freeze_enemies()
	assert(wave.enemies.size() == 1 and wave._pending == 2)
	# 失败取消所有预告、攻击与残怪，旧回调不能污染重试。
	var stale_damage := wave.enemies[0].damage_player
	var stale_spawn := wave.enemies[0].request_spawn
	var hazard := Node3D.new()
	wave._attack_root.add_child(hazard)
	player.take_damage(player.max_health)
	wave._physics_process(0.01)
	assert(wave.phase == WavePrototype.Phase.RESULT and wave._pending == 0 and wave.enemies.is_empty())
	assert(hazard.is_queued_for_deletion() or not hazard.is_inside_tree())
	wave.retry()
	wave._hurt_clock = 0.0
	assert(not stale_damage.call(8.0) and not stale_spawn.call(wave.default_enemy, 1, 0.1, Vector3.INF))
	assert(wave._pending == 5 and player.current_health == player.max_health)
	# 不同攻击策略无需改控制器；两种来源共用短暂受击保护。
	wave._spawn_queue.clear()
	var definition := probe_definition()
	assert(wave._spawn_enemy(definition))
	var probe: WaveEnemy = wave.enemies[-1]
	probe.set_physics_process(false)
	probe.spawn_delay = 0.0
	before = player.current_health
	probe._physics_process(0.01)
	assert(player.current_health == before - 3.0)
	assert(not wave._damage_player(8.0, wave._generation))
	wave._physics_process(wave.hurt_interval)
	assert(wave._damage_player(8.0, wave._generation))
	assert(player.current_health == before - 11.0)
	# 母体先登记幼体再发出死亡，场上归零也不提前休整。
	probe.child_definition = wave.default_enemy
	probe.take_damage(100.0)
	assert(wave.enemies.is_empty() and wave._pending == 2)
	wave._physics_process(0.01)
	assert(wave.phase == WavePrototype.Phase.BATTLE)
	wave._physics_process(0.5)
	freeze_enemies()
	assert(wave.enemies.size() == 1 and wave._pending == 1)
	wave.enemies[0].spawn_delay = 0.0
	wave.enemies[0].take_damage(100.0)
	wave._physics_process(0.01)
	freeze_enemies()
	assert(wave.enemies.size() == 1 and wave._pending == 0)
	var rest_damage := wave.enemies[0].damage_player
	var projectile := Node3D.new()
	wave._attack_root.add_child(projectile)
	wave.enemies[0].spawn_delay = 0.0
	wave.enemies[0].take_damage(100.0)
	wave._physics_process(0.01)
	assert(wave.phase == WavePrototype.Phase.REST and not projectile.is_inside_tree())
	before = player.current_health
	assert(not rest_damage.call(50.0) and player.current_health == before)
	wave.retreat()
	wave.return_home()
	# 显式波次配置混合不同场景，数量与节奏来自数据。
	var group_a := WaveSpawnEntry.new()
	group_a.enemy = wave.default_enemy
	group_a.count = 1
	group_a.start_delay = 0.0
	var group_b := WaveSpawnEntry.new()
	group_b.enemy = definition
	group_b.count = 1
	group_b.start_delay = 0.0
	var custom_wave := WaveDefinition.new()
	custom_wave.entries.assign([group_a, group_b])
	wave.waves.assign([custom_wave])
	wave.max_active_enemies = 30
	player.global_position = wave.global_position
	assert(wave.start_run() and wave.wave_count() == 1 and wave._pending == 2)
	wave._physics_process(0.01)
	wave._physics_process(0.01)
	freeze_enemies()
	assert(wave.enemies.size() == 2 and wave._pending == 0)
	assert(wave.enemies[0] is SlimeEnemy and not wave.enemies[1] is SlimeEnemy)
	for enemy in wave.enemies.duplicate():
		enemy.spawn_delay = 0.0
		enemy.take_damage(100.0)
	wave._physics_process(0.01)
	assert(wave.phase == WavePrototype.Phase.RESULT and wave.completed_waves == 1 and wave.kills == 2)
	# 残怪跌落不会永久卡住；异常结束不计为清波成功。
	wave.retry()
	wave._spawn_queue.clear()
	assert(wave._spawn_enemy())
	var fallen := wave.enemies[0]
	fallen.spawn_delay = 0.0
	var distance_before := TerrainPath.horizontal_distance(fallen.global_position, player.global_position)
	await settle(120)
	assert(TerrainPath.horizontal_distance(fallen.global_position, player.global_position) < distance_before - 0.5)
	assert(fallen.state == SlimeEnemy.State.CHASE, "Wave slime keeps pursuing beyond patrol rules")
	wave.terrain.data.emit_changed()
	await settle(8)
	assert(wave._path_ready and not wave._path.route(fallen.global_position, wave._ground_target()).is_empty())
	fallen.set_physics_process(false)
	fallen.spawn_delay = 0.0
	# 接触命中必须通过墙体与高差检查。
	fallen.global_position = player.global_position + Vector3(0.55, 0.0, 0.0)
	wave._hurt_clock = 0.0
	before = player.current_health
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.1, 2.0, 2.0)
	collision.shape = box
	wall.add_child(collision)
	scene.add_child(wall)
	wall.global_position = player.global_position + Vector3(0.25, 0.5, 0.0)
	await settle()
	fallen._physics_process(0.01)
	assert(player.current_health == before, "Slime contact cannot pass through a wall")
	wall.free()
	await settle()
	fallen.global_position = player.global_position + Vector3(0.55, 1.2, 0.0)
	fallen._physics_process(0.01)
	assert(player.current_health == before, "Slime contact respects terrain height")
	fallen.global_position = player.global_position + Vector3(0.55, 0.0, 0.0)
	fallen._physics_process(0.01)
	assert(player.current_health < before)
	fallen.global_position.y -= 5.0
	wave._physics_process(wave.unreachable_timeout)
	assert(wave.phase == WavePrototype.Phase.RESULT and wave.completed_waves == 0)
	assert(wave.result_reason.contains("无法到达"))
	# 非 WaveEnemy 场景产生明确配置失败，不留下待生成队列。
	wave.return_home()
	var bad_scene := PackedScene.new()
	var wrong_node := Node3D.new()
	assert(bad_scene.pack(wrong_node) == OK)
	wrong_node.free()
	var bad := WaveEnemyDefinition.new()
	bad.scene = bad_scene
	wave.waves.clear()
	wave.default_enemy = bad
	player.global_position = wave.global_position
	assert(not wave.start_run(), "Invalid enemy scene fails before entering combat")
	assert(wave.phase == WavePrototype.Phase.RESULT and wave._pending == 0 and wave.enemies.is_empty())
	assert(wave.result_reason.contains("WaveEnemy"))
	print("PASS: real slime, two-hit kills, safe telegraph, pending spawns, active cap, mixed wave data, independent attack strategy, shared hurt protection, split lifecycle, safe rest cleanup, stale callbacks, unreachable recovery and invalid scene handling")
	scene.queue_free()
	await settle()
	quit()
