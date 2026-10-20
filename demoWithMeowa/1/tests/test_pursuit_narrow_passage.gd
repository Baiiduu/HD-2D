extends SceneTree

const SESSION := preload("res://tests/fixtures/ricochet_session.gd")
var checks := 0
var failures := 0
var world: Node3D
var terrain: Terrain

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func box(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	body.position = center

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	terrain = Terrain.new()
	terrain.data = TerrainData.new()
	terrain.data.size = Vector2i.ZERO
	terrain.data.resize(Vector2i(-11, 18), Vector2i(10, 10))
	world.add_child(terrain)
	# Captured World shop/planter layout. The western gap is 1.195m wide,
	# enough for a 0.4m radius, but the old 0.8m grid misses its clear centre.
	box(Vector3(-16.15, 0.5, 36), Vector3(0.4, 1, 30))
	box(Vector3(0, 0.5, 30.35288), Vector3(40, 1, 0.5))
	box(Vector3(-13.27284, 1.71, 36.60868), Vector3(2.964, 3.42, 1.995))
	box(Vector3(-13.1789, 0.66, 32.23062), Vector3(2.496, 1.32, 1.656))
	box(Vector3(-11.24135, 0.147, 34.40188), Vector3(1.956, 0.294, 1.476))
	for i in 4: await physics_frame
	var path := TerrainPath.new()
	path.build(terrain, 0.4, [])
	var from := Vector3(-5.2, 0.03, 42)
	var goal := Vector3(-13.27284, 0.03, 35.23117)
	check(path._segment_clear(Vector3(-15.4, 0, 34.8), Vector3(-15.4, 0, 38.8)), "Real full-radius sweep fits through the captured western passage")
	check(path.shared_reachable(from, goal), "A legal shop-front target is reachable through the off-centre passage")
	var route := path.shared_pursuit_route(from, goal)
	check(not route.is_empty(), "Shared pursuit supplies the actual approach route")
	if not route.is_empty():
		check(TerrainPath.horizontal_distance(route[-1], goal) < 0.85, "The approach reaches the correct shop side instead of a partial route outside the pocket")
		for i in range(1, route.size()):
			check(path._segment_clear(route[i - 1], route[i]), "Every route segment retains the original full body sweep")
	path.native_chase_enabled = true
	check(not path.chase_route(from, goal).is_empty(), "Native chase consumes the same connected geometry")
	# Exercise the real residual timeout rather than suppressing its result.
	var wave := SESSION.new()
	wave.terrain = terrain
	wave._path = path
	world.add_child(wave)
	wave.phase = WavePrototype.Phase.BATTLE
	var enemy := WaveEnemy.new()
	enemy.definition = load("res://data/enemies/leaf_charger.tres")
	enemy.navigation = path
	world.add_child(enemy)
	enemy.position = from
	wave._check_enemy_reachability(enemy, goal, wave.unreachable_timeout + 0.1)
	check(wave.phase == WavePrototype.Phase.BATTLE, "Standing at the shop does not falsely interrupt the challenge")
	var narrow_target := Vector3(-13.1789, 0.03, 30.91062)
	check(path.shared_reachable(from, narrow_target), "A shallow front-wall contact chooses an approach on the inside of the arena wall")
	var approach := path.shared_pursuit_route(from, narrow_target)
	check(not approach.is_empty() and approach[-1].z > 30.6, "The narrow front gap never targets ground beyond the arena wall")
	check(not path.pursuit_route(from, narrow_target).is_empty(), "Strict and shared pursuit resolve the same visible shop-side approach")
	# A truly narrower-than-body corridor and a real fallen enemy stay invalid.
	box(Vector3(-15.15, 0.5, 36.6), Vector3(0.3, 1, 2.2))
	for i in 3: await physics_frame
	path.build(terrain, 0.4, [])
	check(not path.shared_reachable(from, goal), "A genuinely closed passage is not invented by displaced samples")
	wave.phase = WavePrototype.Phase.BATTLE
	enemy.position.y -= 5.0
	wave._check_enemy_reachability(enemy, goal, wave.unreachable_timeout + 0.1)
	check(wave.phase == WavePrototype.Phase.RESULT, "A truly fallen residual still invokes the existing protection")
	world.queue_free()
	for i in 5: await physics_frame
	print("Narrow passage: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
