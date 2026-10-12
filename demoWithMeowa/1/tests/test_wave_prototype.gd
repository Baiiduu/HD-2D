extends SceneTree

var scene: Node3D
var wave: WavePrototype
var player: Player
var ui: LoadoutUI

func _initialize() -> void:
	create_timer(25.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func settle(frames := 5) -> void:
	for frame in frames: await physics_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func enemy_at(offset: Vector3) -> WaveEnemy:
	assert(wave._spawn_enemy())
	var enemy := wave.enemies[-1]
	enemy.set_physics_process(false)
	enemy.spawn_delay = 0.0
	enemy.health = 500.0
	enemy.global_position = player.global_position + offset
	return enemy

func clear_wave() -> void:
	wave._pending = 0
	if wave.enemies.is_empty(): enemy_at(Vector3(2, 0, 0))
	for enemy in wave.enemies.duplicate(): enemy.take_damage(10000.0)
	wave._physics_process(0.01)

func run() -> void:
	scene = load("res://scenes/world/world.tscn").instantiate()
	ui = scene.get_node("LoadoutUI")
	ui.save_enabled = false
	root.add_child(scene)
	current_scene = scene
	await settle(12)
	wave = scene.get_node("WavePrototype")
	assert(wave._path_ready and wave._spawn_points.size() > 10)
	player = scene.get_node("Player")
	player.set_physics_process(false)
	wave.set_physics_process(false)
	var legacy_state := ui.state.export_state().duplicate(true)
	assert(not wave.start_run(), "Starting requires approaching the marker")
	player.global_position = wave.global_position + Vector3.UP * 0.03
	key(KEY_F)
	await settle()
	assert(wave.phase == WavePrototype.Phase.BATTLE and wave.wave == 1 and not paused)
	assert(not wave.start_run())
	ui.open_menu(1)
	assert(not ui.menu_open and get_first_node_in_group(&"gameplay_input_blockers") == null)
	var enemy := enemy_at(Vector3(2, 0, 0))
	var other := enemy_at(Vector3(3, 0, 0))
	var health_before := enemy.health
	assert(wave._attack() and enemy.health < health_before and other.health == 500.0)
	var camera := scene.get_node("MapEffects/Camera3D") as FollowCamera
	camera.yaw_degrees = 90.0
	camera.snap_to_target()
	assert(wave._nearest_target() == enemy)
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 2.0, 3.0)
	collision.shape = box
	wall.add_child(collision)
	scene.add_child(wall)
	wall.global_position = player.global_position + Vector3(1.0, 0.5, 0.0)
	await settle()
	health_before = enemy.health
	assert(not wave._attack() and enemy.health == health_before)
	wall.queue_free()
	await settle()
	enemy.global_position = player.global_position + Vector3(0.5, 0, 0)
	wave._spawn_clock = 1000.0
	wave._attack_clock = 1000.0
	wave._hurt_clock = 0.0
	health_before = player.current_health
	wave._physics_process(0.01)
	assert(player.current_health < health_before)
	health_before = player.current_health
	wave._physics_process(0.01)
	assert(player.current_health == health_before)
	player.take_damage(player.max_health)
	wave._physics_process(0.01)
	assert(wave.phase == WavePrototype.Phase.RESULT and wave.enemies.is_empty())
	wave.retry()
	assert(wave.phase == WavePrototype.Phase.BATTLE and player.current_health == player.max_health)
	await settle()
	player.current_health = player.max_health * 0.5
	health_before = player.current_health
	clear_wave()
	assert(wave.phase == WavePrototype.Phase.REST and wave.completed_waves == 1)
	assert(player.current_health == health_before, "No implicit growth, healing or reward")
	wave._physics_process(100.0)
	assert(wave.phase == WavePrototype.Phase.REST and wave.enemies.is_empty() and player.current_health == health_before)
	ui.open_menu(1)
	await settle()
	assert(ui.menu_open and ui._actions.get_child_count() == 0 and ui._filter.item_count == 1)
	assert(not wave.start_next_wave())
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = true
	ui._skill_double_click(event, "lightning")
	assert(ui.state.export_state() == legacy_state)
	for id in ui._hud._slot_ids: assert(id.is_empty())
	ui.close_menu()
	await create_timer(0.5).timeout
	assert(wave.start_next_wave() and wave.wave == 2)
	clear_wave()
	assert(wave.phase == WavePrototype.Phase.REST and wave.completed_waves == 2)
	assert(wave.start_next_wave())
	clear_wave()
	assert(wave.phase == WavePrototype.Phase.RESULT and wave.completed_waves == 3 and wave.kills == 3)
	assert(ui.state.export_state() == legacy_state)
	wave.return_home()
	assert(wave.phase == WavePrototype.Phase.READY and get_first_node_in_group(&"gameplay_input_blockers") == null)
	player.global_position = wave.global_position
	assert(wave.start_run())
	player.global_position = Vector3(18, 0, 0)
	wave._physics_process(0.01)
	assert(wave.phase == WavePrototype.Phase.RESULT and wave.enemies.is_empty())
	wave.retry()
	clear_wave()
	wave.retreat()
	assert(wave.phase == WavePrototype.Phase.RESULT and wave.completed_waves == 1)
	print("PASS: F start, generic nearest-target attack, wall occlusion, QE, real health/contact protection, defeat/retry, three-wave direct rest/victory, unlimited safe rest, Tab placeholder/empty HUD, legacy state unchanged, no skill/growth rewards and retreat")
	scene.queue_free()
	await settle()
	quit()
