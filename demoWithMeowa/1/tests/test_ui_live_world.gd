extends SceneTree

class WorldProbe extends Node3D:
	var idle_frames := 0
	var physics_frames := 0
	var unhandled_keys := 0
	func _process(_delta: float) -> void:
		idle_frames += 1
	func _physics_process(_delta: float) -> void:
		physics_frames += 1
	func _unhandled_key_input(_event: InputEvent) -> void:
		unhandled_keys += 1

var checks := 0
var failures: Array[String] = []
var world: WorldProbe
var player: Player
var camera: FollowCamera
var weather: Node3D
var loadout: LoadoutUI
var training: TrainingUI

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL: ", message)

func key(code: Key, pressed: bool, unicode := 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = unicode
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func verify_open_menu(label: String) -> void:
	check(not paused, label + ": opening the UI leaves the world running")
	var before_idle := world.idle_frames
	var before_physics := world.physics_frames
	var before_clock: float = weather._clock
	var before_audio: float = weather._wind_audio.get_playback_position()
	var before_position := player.position
	var before_yaw := camera._yaw_offset_degrees
	var before_unhandled := world.unhandled_keys
	key(KEY_D, true, 100)
	key(KEY_E, true, 101)
	Input.action_press(&"jump")
	await create_timer(0.35).timeout
	key(KEY_D, false)
	key(KEY_E, false)
	Input.action_release(&"jump")
	check(world.idle_frames > before_idle + 5 and world.physics_frames > before_physics + 5, label + ": world process and physics keep ticking")
	check(weather._clock > before_clock + 0.2 and weather._rain.can_process(), label + ": weather and rain particles continue")
	check(weather._wind_audio.playing and not weather._wind_audio.stream_paused and weather._wind_audio.get_playback_position() > before_audio + 0.1, label + ": wind audio stays continuous")
	check(player.position.distance_to(before_position) < 0.02 and player.is_on_floor(), label + ": movement and jump input are blocked")
	check(is_equal_approx(camera._yaw_offset_degrees, before_yaw), label + ": camera keys cannot turn the background")
	check(world.unhandled_keys == before_unhandled, label + ": panel owns unhandled gameplay keys")

func _run() -> void:
	world = WorldProbe.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(30, 0.2, 30)
	floor_collision.shape = floor_shape
	floor_body.position.y = -0.1
	floor_body.add_child(floor_collision)
	world.add_child(floor_body)
	player = Player.new()
	player.animations = load("res://assets/meowa/player/animations.tres")
	player.position.y = 0.2
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 1.06592
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = capsule.height * 0.5
	player.add_child(collision)
	world.add_child(player)
	camera = FollowCamera.new()
	camera.target = player
	camera.fov = 30
	camera.distance = 11
	camera.pitch_degrees = 10
	camera.dead_zone = 0.1
	camera.dof_mode = 0
	camera.dof_amount = 0.02
	camera.dof_near_transition = 1.5
	camera.dof_far_transition = 4
	camera.ellipse_radius = Vector2(0.25, 0.25)
	camera.ellipse_transition = 0.9
	world.add_child(camera)
	loadout = load("res://scenes/ui/loadout_ui.tscn").instantiate()
	loadout.save_enabled = false
	loadout.motion_enabled = false
	loadout.player = player
	world.add_child(loadout)
	var point := Marker3D.new()
	point.position = Vector3(0, 0.75, 1)
	world.add_child(point)
	training = load("res://scenes/ui/training_ui.tscn").instantiate()
	training.player = player
	training.loadout = loadout
	training.interaction_point = point
	world.add_child(training)
	weather = load("res://scripts/weather.gd").new()
	weather.rain_audio_fade_time = 0.1
	weather.wind_audio_fade_time = 0.1
	world.add_child(weather)
	await create_timer(0.5).timeout
	for page in 2:
		loadout.open_menu(page)
		if page == 0:
			loadout._search.grab_focus()
		await verify_open_menu("equipment" if page == 0 else "skills")
		if page == 0:
			check(loadout._search.text == "de", "Equipment search receives typing without moving the character")
			loadout._search.text = ""
		loadout.close_menu()
		check(not paused and get_first_node_in_group(&"gameplay_input_blockers") == null, "Closing loadout releases only UI input ownership")
	check(training.open_menu(), "Training opens with its real proximity check")
	await verify_open_menu("training")
	key(KEY_TAB, true)
	key(KEY_TAB, false)
	check(training.menu_open and not loadout.menu_open, "Training and loadout cannot overlap through Tab")
	key(KEY_ESCAPE, true)
	key(KEY_ESCAPE, false)
	check(not training.menu_open and loadout.visible and get_first_node_in_group(&"gameplay_input_blockers") == null, "ESC restores HUD and gameplay input")
	var start := player.position.x
	key(KEY_D, true)
	key(KEY_E, true)
	await create_timer(0.25).timeout
	key(KEY_D, false)
	key(KEY_E, false)
	check(player.position.x > start + 0.6 and camera._yaw_offset_degrees > 1.0, "Movement and camera input return after closing the menu")
	# Opening a panel in midair must leave character physics running.
	player.position = Vector3(0, 1, 0)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	loadout.open_menu()
	await create_timer(0.6).timeout
	check(player.position.y < 0.02 and player.is_on_floor(), "Gravity and landing continue while a panel is open")
	loadout.close_menu()
	# The UI must never change a pause requested by another system.
	paused = true
	loadout.open_menu()
	loadout.close_menu()
	check(paused, "A pre-existing external pause remains untouched")
	paused = false
	loadout.open_menu()
	world.remove_child(loadout)
	check(get_first_node_in_group(&"gameplay_input_blockers") == null and not paused, "Removing an open UI leaves no input lock or pause behind")
	loadout.free()
	world.free()
	print("Live UI world: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
