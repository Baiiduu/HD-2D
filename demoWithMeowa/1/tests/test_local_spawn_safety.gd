extends SceneTree

const SESSION := preload("res://tests/fixtures/ricochet_session.gd")
var checks := 0
var failures := 0
var world: Node3D
var wave: WavePrototype
var terrain: Terrain
var player: Player

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle(count := 3) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	terrain = Terrain.new()
	var data := TerrainData.new()
	data.size = Vector2i.ZERO
	data.resize(Vector2i(-11, -11), Vector2i(22, 22))
	terrain.data = data
	world.add_child(terrain)
	wave = SESSION.new()
	wave.name = "WavePrototype"
	wave.terrain = terrain
	wave.battle_area = Rect2(-16, -16, 32, 32)
	wave.spawn_excluded_areas = [Rect2(-6.4, -3.2, 12.8, 6.4)]
	wave.spawn_block_timeout = 2.0
	wave.max_active_enemies = 4
	wave._run_population = null
	world.add_child(wave)
	wave.phase = WavePrototype.Phase.BATTLE
	wave.wave = 1
	wave._attack_root = Node3D.new()
	wave.add_child(wave._attack_root)
	player = Player.new()
	player.name = "Player"
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 1.1
	collider.shape = capsule
	collider.position.y = 0.55
	player.add_child(collider)
	wave.player = player
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.position = Vector3(0, 0.03, -8)
	await settle()
	wave._path.build(terrain, 0.32, [player.get_rid()])
	wave._path_ready = true
	var child := load("res://data/enemies/mini_slime.tres") as WaveEnemyDefinition
	var requested := wave._path.ground_position(Vector3(0.4, 0, 0))
	var goal := wave._ground_target()
	check(not wave._valid_spawn(requested, child, goal), "普通刷怪仍不能进入入口禁刷区")
	check(wave._valid_spawn(requested, child, goal, true), "原地分裂允许留在进入禁刷区的母体附近")
	for seed in 16:
		wave._random.seed = seed
		var point := wave._find_spawn(child, requested, PackedStringArray())
		check(point.is_finite() and TerrainPath.horizontal_distance(point, requested) <= 3.2001,
			"禁刷区中央的局部刷新不依赖随机逃出矩形：%d" % seed)
	check(not wave._valid_spawn(Vector3(16, 0, 0), child, goal, true), "局部刷新仍遵守真实战区边界")
	check(not wave._valid_spawn(player.position, child, goal, true), "局部刷新仍为人物身体保留距离")
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 3, 1.5)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.position = requested + Vector3.UP * 1.5
	await settle()
	check(not wave._valid_spawn(requested, child, goal, true), "局部刷新不会忽略真实墙体")
	wall.queue_free()
	await settle()
	# 使用真实壶兽死亡接口登记幼体，在母体进入禁刷区后击杀。
	var parent_rules := load("res://data/enemies/pot_brood.tres") as WaveEnemyDefinition
	wave._catalog_snapshots[&"mini_slime"] = child
	check(wave._spawn_enemy(parent_rules, Vector3(8, 0, 0)), "真实壶兽可先在禁刷区外生成")
	if not wave.enemies.is_empty():
		var parent := wave.enemies[0] as PotBroodEnemy
		parent.set_physics_process(false)
		parent.position = wave._path.ground_position(Vector3.ZERO) + Vector3.UP * 0.03
		parent._look = Vector3.FORWARD
		parent.commit_spatial_state()
		var origin := parent.global_position
		parent.take_damage(parent.health + 1.0)
		check(wave.enemies.is_empty() and wave._pending == 2, "母体死亡先完整登记两个幼体，不能提前清波")
		wave._wave_clock = 0.5
		wave._process_spawns()
		check(wave._pending == 0 and wave.enemies.size() == 2, "禁刷区内击杀壶兽后两个幼体实际出场")
		for enemy in wave.enemies:
			enemy.set_physics_process(false)
			check(TerrainPath.horizontal_distance(enemy.global_position, origin) <= 3.6001,
				"幼体保留母体附近的位置，不跳去外围刷怪点")
		wave._wave_clock = 3.0
		wave._process_spawns()
		check(wave.phase == WavePrototype.Phase.BATTLE, "经过堵点超时时间后不发生误中断")
	for enemy in wave.enemies.duplicate(): enemy.cancel()
	wave.enemies.clear()
	world.queue_free()
	await settle()
	print("Local spawn safety: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
