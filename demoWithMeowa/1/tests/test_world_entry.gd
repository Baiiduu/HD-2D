extends SceneTree

const ENTRY = preload("res://scripts/world/world_entry.gd")
const REQUEST = preload("res://scripts/world/world_entry_request.gd")
const SETTINGS = preload("res://scripts/world/world_entry_settings.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func frames(count := 3) -> void:
	for index in count: await process_frame

func fixture() -> Node3D:
	var world := Node3D.new()
	var player := Node3D.new()
	player.name = "Player"
	player.position = Vector3(1, 0, 2)
	world.add_child(player)
	var camera := FollowCamera.new()
	camera.name = "Camera"
	camera.target = player
	camera.fov = 28.0
	camera.distance = 25.0
	camera.pitch_degrees = 30.627
	camera.yaw_degrees = 135.0
	camera.dof_enabled = false
	world.add_child(camera)
	for label in ["HUD", "HiddenHUD"]:
		var hud := CanvasLayer.new()
		hud.name = label
		hud.visible = label == "HUD"
		world.add_child(hud)
	var entry := ENTRY.new()
	entry.name = "WorldEntry"
	entry.camera = camera
	entry.player = player
	entry.settings = SETTINGS.new()
	entry.hud_layers.assign([world.get_node("HUD"), world.get_node("HiddenHUD")])
	world.add_child(entry)
	return world

func request_checks() -> void:
	REQUEST.clear()
	check(not REQUEST.consume(), "Direct map startup has no intro request")
	REQUEST.request()
	check(REQUEST.consume() and not REQUEST.consume(), "Menu request is consumed exactly once")
	REQUEST.request()
	REQUEST.clear()
	check(not REQUEST.consume(), "Failed menu scene changes can clear the request")

func timeline_checks() -> void:
	var world := fixture()
	root.add_child(world)
	await frames()
	var entry = world.get_node("WorldEntry")
	var camera := world.get_node("Camera") as FollowCamera
	var normal_pose := camera.global_transform
	check(not entry.active and not entry.is_processing(), "Direct F5/F6 map does not play or update entry effects")
	check(entry.play(), "Entry can be previewed independently of the menu")
	entry.set_process(false)
	check(entry.active and not camera.is_processing() and entry.is_in_group(&"gameplay_input_blockers"), "Entry owns camera and gameplay input without pausing world")
	check(not paused and Engine.time_scale == 1.0, "Weather, music and world time keep running")
	check(not world.get_node("HUD").visible and not world.get_node("HiddenHUD").visible, "Entry hides gameplay HUD layers")
	check(not entry.has_node("EntryFogOverlay") and entry._spotlight.shadow_enabled and entry._fog.visible, "Entry uses spatial fog and a real spotlight without a full-screen gray filter")
	check(entry.fog_amount > 0.7 and entry.fog_amount < 1.0, "Opening fog is dense and remains translucent")
	check(camera.global_position.y > normal_pose.origin.y + 5.0, "Camera starts well above normal gameplay")
	check(not entry.play(), "Repeated play requests do not restart or steal saved state")
	var initial_fog: float = entry.fog_amount
	var initial_pose := camera.global_transform
	entry.advance(0.0)
	check(camera.global_transform.is_equal_approx(initial_pose), "Zero elapsed time preserves entry pose")
	entry.advance(entry.settings.duration_seconds * 0.5)
	check(is_equal_approx(entry.fog_amount, initial_fog), "Clouds remain dense while the camera is still flying")
	check(entry._spotlight.light_energy > 0.0 and entry._spotlight.global_position.y > entry.player.global_position.y, "Warm spotlight stays above the real player during reveal")
	check(camera.global_position.y < initial_pose.origin.y and camera.global_position.y > normal_pose.origin.y, "Camera descends toward character throughout entry")
	check(camera.fov == 28.0 and camera.distance == 25.0 and camera.pitch_degrees == 30.627 and camera.yaw_degrees == 135.0 and not camera.dof_enabled, "Entry never rewrites authored camera settings")
	entry.advance(entry.settings.duration_seconds)
	check(not entry.active and not entry.is_processing() and camera.is_processing(), "Completion returns camera processing and stops entry work")
	check(not entry.is_in_group(&"gameplay_input_blockers") and world.get_node("HUD").visible and not world.get_node("HiddenHUD").visible, "Completion restores input and original HUD visibility")
	check(camera.global_transform.is_equal_approx(normal_pose), "Camera hands off at the exact original gameplay composition")
	check(entry.fog_amount == 0.0 and not is_instance_valid(entry._spotlight) and not is_instance_valid(entry._fog), "Completion clears spotlight and fog references")
	await frames()
	check(entry.get_child_count() == 0, "Completed entry retains no render nodes")
	world.free()

func sky_approach_checks() -> void:
	var world := fixture()
	var camera := world.get_node("Camera") as FollowCamera
	var original_environment := Environment.new()
	original_environment.volumetric_fog_enabled = false
	original_environment.volumetric_fog_density = 0.006
	camera.environment = original_environment
	root.add_child(world)
	await frames()
	var entry = world.get_node("WorldEntry")
	var gameplay_pose := camera.global_transform
	check(not entry.preview_on_direct_run, "Direct-map preview is opt-in on a new entry component")
	entry.play()
	entry.set_process(false)
	var start_pose := camera.global_transform
	var approach := start_pose.origin - gameplay_pose.origin
	var horizontal := Vector2(approach.x, approach.z).length()
	check(horizontal >= 70.0 and horizontal > absf(approach.y) * 2.5, "Entry approaches from distant sky instead of descending above the map")
	check(absf(camera.global_basis.z.y) < 0.15, "Opening camera faces the foggy sky near the horizon")
	check(entry.settings.duration_seconds >= 4.5 and entry.settings.duration_seconds <= 7.0, "Entry reserves time for cloud flight followed by a separate reveal")
	check(camera.environment != original_environment and camera.environment.volumetric_fog_enabled, "Entry has its own volumetric environment even when gameplay fog is disabled")
	check(camera.environment.volumetric_fog_sky_affect > 0.95 and camera.environment.volumetric_fog_density == 0.0, "Fog covers the sky through cloud volumes instead of a uniform background haze")
	check(ENTRY.CLOUD_NOISE.get_width() == 272 and ENTRY.CLOUD_NOISE.get_height() == 136, "Prebaked 3D cloud density matches the shader's padded slice layout")
	check(not original_environment.volumetric_fog_enabled and is_equal_approx(original_environment.volumetric_fog_density, 0.006), "Temporary cloud rendering does not modify gameplay environment settings")
	var banks: Array = []
	if "_fog_banks" in entry: banks.assign(entry._fog_banks)
	check(banks.size() >= 4, "Multiple real cloud banks occupy different depths on the approach")
	var bank_positions: Array[Vector3] = []
	for bank in banks:
		bank_positions.append(bank.global_position)
	entry.advance(entry.settings.duration_seconds * entry.settings.arrival_ratio * 0.85)
	var remaining := camera.global_position.distance_to(gameplay_pose.origin)
	check(remaining < approach.length() * 0.2, "Main approach finishes before the final settling section")
	var toward_player := (camera.target.global_position + Vector3.UP * camera.focus_height - camera.global_position).normalized()
	check((-camera.global_basis.z).dot(toward_player) > 0.995, "Rapid approach brings the player into the center of attention")
	var passed := 0
	var fixed_in_world := true
	for index in banks.size():
		fixed_in_world = fixed_in_world and banks[index].global_position.is_equal_approx(bank_positions[index])
		if (banks[index].global_position - camera.global_position).dot(-camera.global_basis.z) < 0.0: passed += 1
	check(not banks.is_empty() and fixed_in_world and passed >= 2, "Camera physically passes world-fixed clouds, creating depth and parallax")
	entry.skip()
	check(camera.environment == original_environment, "Skip restores the exact original camera environment")
	world.free()
	await frames()

func continuity_checks() -> void:
	var mask := Image.new()
	mask.load_png_from_buffer(FileAccess.get_file_as_bytes(ENTRY.WISP_TEXTURE.resource_path))
	check(not mask.is_empty() and mask.get_width() >= 512 and mask.get_height() >= 256, "Meowa wisps retain their original high-resolution density source")
	var soft_samples := 0
	var border_dark := true
	for x in range(0, mask.get_width(), 16):
		border_dark = border_dark and mask.get_pixel(x, 0).r < 0.06 and mask.get_pixel(x, mask.get_height() - 1).r < 0.06
	for y in range(0, mask.get_height(), 16):
		border_dark = border_dark and mask.get_pixel(0, y).r < 0.06 and mask.get_pixel(mask.get_width() - 1, y).r < 0.06
		for x in range(0, mask.get_width(), 16):
			var value := mask.get_pixel(x, y).r
			if value > 0.02 and value < 0.98: soft_samples += 1
	check(border_dark and soft_samples > 100, "Wisps have clear image boundaries and continuous density instead of hard alpha cutouts")
	var world := fixture()
	root.add_child(world)
	await frames()
	var entry = world.get_node("WorldEntry")
	var camera := world.get_node("Camera") as FollowCamera
	entry.play()
	entry.set_process(false)
	var position_steps: Array[float] = []
	var angle_steps: Array[float] = []
	var previous_pose := camera.global_transform
	var peak_index := 0
	var angle_peak_index := 0
	var arrival: float = entry.settings.get("arrival_ratio") if "arrival_ratio" in entry.settings else 1.0
	for frame in range(1, 121):
		entry._apply(float(frame) / 120.0 * arrival)
		var pose := camera.global_transform
		position_steps.append(pose.origin.distance_to(previous_pose.origin))
		angle_steps.append(pose.basis.get_rotation_quaternion().angle_to(previous_pose.basis.get_rotation_quaternion()))
		if position_steps[-1] > position_steps[peak_index]: peak_index = frame - 1
		if angle_steps[-1] > angle_steps[angle_peak_index]: angle_peak_index = frame - 1
		previous_pose = pose
	var peak: float = position_steps.max()
	check(position_steps[0] < peak * 0.1 and position_steps[-1] < peak * 0.1, "Camera accelerates from rest and settles continuously at the player")
	check(peak_index > 30 and peak_index < 90, "Approach reaches peak speed in the middle rather than jumping at startup")
	check(position_steps[110] > 0.005, "Camera continues settling throughout the flight section")
	check(abs(peak_index - angle_peak_index) < 20, "Camera rotation and translation share the same rhythm")
	var wisps: Array = []
	if "_wisps" in entry: wisps.assign(entry._wisps)
	check(wisps.size() >= 6, "Visible world-space wisps provide identifiable near-cloud edges")
	check(wisps.all(func(wisp): return wisp is MeshInstance3D and wisp.is_inside_tree()), "Cloud wisps participate in actual spatial occlusion and parallax")
	entry.skip()
	entry.play()
	entry.set_process(false)
	if "_render_wait_frames" in entry:
		entry._render_wait_frames = 2
		entry._process(0.5)
		check(entry._elapsed == 0.0, "Loading frames cannot consume the intro before clouds are presented")
		entry._on_render_frame()
		entry._process(0.5)
		check(entry._elapsed == 0.0, "Intro waits for the second presented frame")
		entry._on_render_frame()
		entry._process(0.5)
		check(entry._elapsed == 0.0, "First post-loading delta is discarded rather than skipping the approach")
		entry._process(0.5)
		check(entry._elapsed > 0.0 and entry._elapsed <= 0.04, "Presentation-only clock limits large frame jumps without altering world time")
	else:
		check(false, "Entry needs a presented-frame gate for cold scene and shader loading")
	entry.skip()
	world.free()
	await frames()

func cloud_flight_checks() -> void:
	var world := fixture()
	root.add_child(world)
	await frames()
	var entry = world.get_node("WorldEntry")
	var camera := world.get_node("Camera") as FollowCamera
	check("arrival_ratio" in entry.settings, "Flight arrival and cloud reveal have independent timing")
	if not "arrival_ratio" in entry.settings:
		world.free()
		return
	var arrival: float = entry.settings.arrival_ratio
	var normal_pose := camera.global_transform
	entry.play()
	entry.set_process(false)
	var initial_fog: float = entry.fog_amount
	var start := camera.global_position
	var max_curve := 0.0
	var min_bank := 0.0
	var max_bank := 0.0
	var fog_covers_flight := true
	var fog_covers_view := true
	var never_inverted := true
	for index in range(41):
		entry._apply(arrival * index / 40.0)
		var position := camera.global_position
		var chord := Geometry3D.get_closest_point_to_segment(position, start, normal_pose.origin)
		max_curve = maxf(max_curve, position.distance_to(chord))
		var level := Basis.looking_at(-camera.global_basis.z, Vector3.UP)
		var bank := atan2(camera.global_basis.x.dot(level.y), camera.global_basis.x.dot(level.x))
		min_bank = minf(min_bank, bank)
		max_bank = maxf(max_bank, bank)
		never_inverted = never_inverted and camera.global_basis.y.dot(Vector3.UP) > 0.0
		var cover := AABB(entry._fog.global_position - entry._fog.size * 0.5, entry._fog.size)
		fog_covers_flight = fog_covers_flight and cover.has_point(position - camera.global_basis.z * 3.0)
		# Containing the camera alone missed holes in front of a banked/turning view.
		var aspect := root.get_visible_rect().size.aspect()
		for depth in [24.0, 48.0, 96.0]:
			var half_height: float = depth * tan(deg_to_rad(camera.fov) * 0.5)
			for x in [-1.0, 1.0]:
				for y in [-1.0, 1.0]:
					var corner := position + camera.global_basis * Vector3(x * half_height * aspect, y * half_height, -depth)
					fog_covers_view = fog_covers_view and cover.has_point(corner)
		check(is_equal_approx(entry.fog_amount, initial_fog), "Flight sample %d keeps full cloud density until arrival" % index)
	check(max_curve > 15.0 and min_bank < -0.2 and max_bank > 0.2, "Camera sweeps through a wide arc and banks in both directions")
	check(never_inverted, "Camera banking never turns the picture upside down")
	check(fog_covers_flight, "World-space cloud cover encloses the camera's entire flight")
	check(fog_covers_view, "Cloud cover encloses the full forward fog frustum through every bank and turn")
	var base_density: float = entry._volume_material.get_shader_parameter("density")
	var minimum_fill: float = entry._volume_material.get_shader_parameter("coverage_floor")
	check(base_density * minimum_fill * 96.0 >= 3.0, "The covering cloud has enough minimum optical depth to obscure the fixed distant city even between billows")
	check(camera.global_transform.is_equal_approx(normal_pose), "Camera reaches the authored gameplay pose before cloud clearing begins")
	var landed := camera.global_transform
	var bank_pose: Transform3D = entry._fog_banks[-1].global_transform
	var wisp_position: Vector3 = entry._wisps[-1].global_position
	var cloud_density: float = entry._bank_materials[-1].get_shader_parameter("density")
	entry._apply(arrival + 0.025)
	check(camera.global_transform.is_equal_approx(landed) and is_equal_approx(entry.fog_amount, initial_fog), "Clouds briefly hold after the camera stops")
	entry._apply(0.85)
	check(camera.global_transform.is_equal_approx(landed) and is_equal_approx(entry.fog_amount, initial_fog), "Cloud clearing keeps the cloud body opaque while the final composition stays still")
	check(is_equal_approx(entry._bank_materials[-1].get_shader_parameter("density"), cloud_density), "Clouds retreat without reducing their bulk density")
	check(entry._fog_banks[-1].global_position.distance_to(bank_pose.origin) > 5.0 and not entry._fog_banks[-1].global_basis.is_equal_approx(bank_pose.basis), "Real cloud banks move outward and roll during clearing")
	var cloud_width: float = entry._wisps[-1].mesh.size.x * entry._wisps[-1].global_basis.get_scale().x
	check(entry._wisps[-1].global_position.distance_to(wisp_position) > cloud_width * 0.25, "Near cloud silhouettes move by a visible fraction of their own size instead of only fading")
	check(entry._spotlight.light_energy > 0.0 and entry.is_in_group(&"gameplay_input_blockers"), "Player spotlight and input ownership remain throughout the reveal")
	entry._apply(1.0)
	check(is_zero_approx(entry.fog_amount), "Clouds reach zero density before temporary effects are removed")
	entry.skip()
	world.free()
	await frames()

func lifecycle_checks() -> void:
	REQUEST.request()
	var world := fixture()
	root.add_child(world)
	await frames()
	var entry = world.get_node("WorldEntry")
	entry.set_process(false)
	var camera := world.get_node("Camera") as FollowCamera
	check(entry.active and not REQUEST.consume(), "World consumes menu intent and auto-plays after scene setup")
	entry.skip()
	check(not entry.active and camera.is_processing() and not paused, "Skip hands off immediately without affecting world pause")
	entry.settings.allow_skip = false
	entry.play()
	entry.set_process(false)
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	entry._input(escape)
	check(entry.active, "Disabled skip still blocks input without ending entry")
	entry.settings.allow_skip = true
	escape.echo = true
	entry._input(escape)
	check(entry.active, "Auto-repeat cannot accidentally skip entry")
	escape.echo = false
	entry._input(escape)
	check(not entry.active and camera.is_processing(), "Fresh Escape skips and releases camera ownership")
	camera.set_process(false)
	check(entry.play(), "Entry can play while original follow processing is disabled")
	entry.set_process(false)
	entry.skip()
	check(not camera.is_processing(), "Cleanup preserves an originally disabled camera")
	camera.set_process(true)
	check(entry.play(), "Entry can be replayed for manual tuning")
	entry.free()
	check(camera.is_processing() and world.get_node("HUD").visible and not world.get_node("HiddenHUD").visible and get_first_node_in_group(&"gameplay_input_blockers") == null, "Removing entry mid-play restores camera, HUD and input")
	world.free()
	await frames()
	var missing := ENTRY.new()
	root.add_child(missing)
	check(not missing.play() and get_first_node_in_group(&"gameplay_input_blockers") == null, "Missing bindings cannot leave input locked")
	missing.free()
	REQUEST.request()
	world = fixture()
	world.get_node("WorldEntry").settings.enabled = false
	root.add_child(world)
	await frames()
	check(not world.get_node("WorldEntry").active and not REQUEST.consume(), "Disabled entry consumes stale request without leaving it for another map")
	world.free()
	await frames()
	world = fixture()
	root.add_child(world)
	await frames()
	entry = world.get_node("WorldEntry")
	entry.settings.duration_seconds = 0.0
	check(entry.play() and not entry.active and not entry.is_in_group(&"gameplay_input_blockers"), "Zero-duration tuning hands off immediately without locking input")
	world.free()
	await frames()
	world = fixture()
	root.add_child(world)
	await frames()
	entry = world.get_node("WorldEntry")
	entry.play()
	world.free()
	await frames()
	check(get_first_node_in_group(&"gameplay_input_blockers") == null, "Scene unload during entry leaves no stale input owner")
	world = fixture()
	root.add_child(world)
	await frames()
	entry = world.get_node("WorldEntry")
	entry.play()
	entry.set_process(false)
	var detached_player: Node3D = world.get_node("Player")
	world.remove_child(detached_player)
	entry.advance(0.1)
	check(not entry.active and world.get_node("Camera").is_processing() and get_first_node_in_group(&"gameplay_input_blockers") == null, "Losing the player cancels cleanly instead of leaving a cinematic camera")
	detached_player.free()
	world.free()
	await frames()

func formal_checks() -> void:
	var world: Node = load("res://scenes/world/world.tscn").instantiate()
	var player_outline: bool = world.get_node("Player/Sprite").occlusion_outline_enabled
	var entry = world.get_node_or_null("WorldEntry")
	check(entry != null, "Formal map has the menu-entry component")
	if entry:
		check(entry.camera == world.get_node("MapEffects/Camera3D") and entry.player == world.get_node("Player"), "Formal entry targets the actual player and existing camera")
		check("terrain" in entry and entry.get("terrain") == world.get_node("Homestead"), "Whole-map cloud cover reads the real terrain boundary")
		check(entry.settings.enabled, "Formal entry remains enabled while preserving the user's preview switch")
		check(entry.settings.resource_path == "res://data/visual/world_entry.tres", "Entry settings are independent of combat camera and Style")
		var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(world)
		check(entries.any(func(item): return item.property == "fog_opacity" and item.category == "视觉" and item.common), "Entry fog is adjustable in the shared visual parameter hub")
	quiet_map(world)
	REQUEST.request()
	root.add_child(world)
	await frames(12)
	if entry:
		entry.set_process(false)
		var wave := world.get_node("WavePrototype") as WavePrototype
		var camera := world.get_node("MapEffects/Camera3D") as FollowCamera
		var environment: Environment = world.get_node("MapEffects/WorldEnvironment").environment
		var original_fog := environment.volumetric_fog_density
		await building_route_checks(world)
		check(entry.active and not wave.start_run() and wave.phase == WavePrototype.Phase.READY and not wave.combat_frozen, "Real World plays the requested entry after spawn and blocks premature combat without freezing time")
		check(not wave.skill_draft.initial_choice.is_open and wave.enemies.is_empty(), "Entry neither opens the initial draft nor spawns monsters")
		var cloud_bounds := AABB(entry._fog.global_position - entry._fog.size * 0.5, entry._fog.size)
		var map_bounds: Rect2 = world.get_node("Homestead").get_world_rect()
		check(cloud_bounds.has_point(Vector3(map_bounds.position.x, 2.0, map_bounds.position.y)) and cloud_bounds.has_point(Vector3(map_bounds.end.x, 2.0, map_bounds.end.y)), "Cloud cover includes both far corners of the actual map")
		entry.advance(entry.settings.duration_seconds * 0.5)
		var light: SpotLight3D = entry._spotlight
		var target_direction: Vector3 = (entry.player.global_position + Vector3.UP * 0.15 - light.global_position).normalized()
		check(light.global_basis.z.dot(target_direction) < -0.999, "The real spotlight points at the player rather than a nearby scene prop")
		entry.advance(entry.settings.duration_seconds)
		var end_pose := camera.global_transform
		camera._process(0.0)
		check(camera.global_transform.is_equal_approx(end_pose), "Real World handoff has no composition jump on the next camera update")
		check(wave.phase == WavePrototype.Phase.READY and not wave.skill_draft.initial_choice.is_open and environment.volumetric_fog_density == original_fog, "Entry ends in existing preparation flow and preserves authored environment fog")
		check(not entry.active and not entry.is_processing() and camera.is_processing(), "Real World entry leaves no active timeline")
		check(world.get_node("Player/Sprite").occlusion_outline_enabled == player_outline, "Completion restores the player's authored gameplay occlusion outline")
	world.free()
	await frames()
	var city: Node = load("res://scenes/city/city.tscn").instantiate()
	check(city.get_node_or_null("WorldEntry") == null, "City does not inherit World's optional entry")
	quiet_map(city)
	root.add_child(city)
	await frames(6)
	city.free()
	await frames()

func building_route_checks(world: Node) -> void:
	var entry = world.get_node("WorldEntry")
	if not "flight_path" in entry:
		check(false, "World entry needs an authored route through the existing buildings")
		return
	var path: Path3D = entry.flight_path
	check(path != null and path.curve != null and path.curve.point_count >= 4, "World binds an editable building passage route")
	if not path or not path.curve: return
	var camera: FollowCamera = entry.camera
	check(not world.get_node("Player/Sprite").occlusion_outline_enabled, "Entry does not reveal the hidden player through buildings with a gameplay outline")
	var map_bounds: Rect2 = world.get_node("Homestead").get_world_rect()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.margin = 0.02
	# 飞行机位可越过少量地图上空；游戏空气墙没有画面，不作为镜头实体障碍。
	query.exclude = [entry.player.get_rid(), world.get_node("MapEffects/MapBoundary").get_rid()]
	await physics_frame
	var space := camera.get_world_3d().direct_space_state
	var inside_map := true
	var boundary_excess := 0.0
	var boundary_position := Vector3.ZERO
	var low_samples := 0
	var gap_samples := 0
	var clear := true
	var upright := true
	var continuous := true
	var forward_travel := true
	var closing_approach := true
	var covered := true
	var cloud_bounds := AABB(entry._fog.global_position - entry._fog.size * 0.5, entry._fog.size)
	var half_height := 96.0 * tan(deg_to_rad(camera.fov) * 0.5)
	var half_width := half_height * root.get_visible_rect().size.aspect()
	entry._apply(0.0)
	var previous := camera.global_transform
	var flight_steps := ceili(entry.settings.duration_seconds * entry.settings.arrival_ratio * 60.0)
	for index in range(flight_steps + 1):
		entry._apply(entry.settings.arrival_ratio * index / flight_steps)
		var pose := camera.global_transform
		var flight_bounds := map_bounds if pose.origin.y < 5.0 else map_bounds.grow(4.5)
		inside_map = inside_map and flight_bounds.has_point(Vector2(pose.origin.x, pose.origin.z))
		var excess := maxf(maxf(flight_bounds.position.x - pose.origin.x, pose.origin.x - flight_bounds.end.x), maxf(flight_bounds.position.y - pose.origin.z, pose.origin.z - flight_bounds.end.y))
		if excess > boundary_excess:
			boundary_excess = excess
			boundary_position = pose.origin
		if pose.origin.y < 3.3: low_samples += 1
		if pose.origin.x > -9.0 and pose.origin.x < -7.3 and pose.origin.z > 39.5 and pose.origin.z < 44.5 and pose.origin.y < 3.0:
			gap_samples += 1
		upright = upright and pose.basis.y.dot(Vector3.UP) > 0.0
		for x in [-1.0, 1.0]:
			for y in [-1.0, 1.0]:
				covered = covered and cloud_bounds.has_point(pose * Vector3(x * half_width, y * half_height, -96.0))
		continuous = continuous and pose.basis.get_rotation_quaternion().angle_to(previous.basis.get_rotation_quaternion()) < 0.15
		var movement := pose.origin - previous.origin
		if movement.length() > 0.0001:
			forward_travel = forward_travel and movement.normalized().dot(-pose.basis.z) > 0.15
		if index > flight_steps * 0.8:
			closing_approach = closing_approach and pose.origin.distance_to(camera.focus) <= previous.origin.distance_to(camera.focus) + 0.001
		query.transform = Transform3D(Basis.IDENTITY, previous.origin)
		query.motion = pose.origin - previous.origin
		clear = clear and space.intersect_shape(query, 1).is_empty() and space.cast_motion(query)[0] > 0.999
		previous = pose
	check(inside_map, "Street flight stays inside the real map and the high approach uses only its immediate rooftop margin (outside %.3f m at %s, camera distance %.1f m)" % [boundary_excess, boundary_position, camera.distance])
	check(low_samples >= 35 and gap_samples >= 8, "Camera spends time at facade height in the real shop/hospital passage")
	check(clear, "Camera and its swept near-space stay outside actual building and obstacle collisions")
	check(upright and continuous, "Building turns remain smooth and never invert the image")
	check(forward_travel, "Street flight always advances into the view instead of travelling backward after facing the player")
	check(closing_approach, "The final approach closes toward the player instead of pulling out to the gameplay camera")
	check(covered, "The building route and banked forward view remain inside dense cloud coverage")
	var landed := camera.global_transform
	entry._apply(0.9)
	check(camera.global_transform.is_equal_approx(landed), "Street flight settles before the existing outward cloud reveal")
	entry.skip()
	check(entry._route_curve == null and is_zero_approx(entry._route_length), "Route snapshots are released with the temporary entry state")
	var saved_yaw := camera._yaw_offset_degrees
	camera._yaw_offset_degrees += 35.0
	camera.snap_to_target()
	var rotated_pose := camera.global_transform
	entry.play()
	entry.set_process(false)
	entry._apply(entry.settings.arrival_ratio * 0.8)
	var rotated_previous := camera.global_transform
	var rotated_forward := true
	for index in range(1, 61):
		entry._apply(entry.settings.arrival_ratio * lerpf(0.8, 1.0, index / 60.0))
		var movement := camera.global_position - rotated_previous.origin
		if movement.length() > 0.0001: rotated_forward = rotated_forward and movement.normalized().dot(-camera.global_basis.z) > 0.15
		rotated_previous = camera.global_transform
	check(rotated_forward, "Rotated Q/E replay also approaches forward during the final handoff")
	entry._apply(entry.settings.arrival_ratio)
	check(camera.global_transform.is_equal_approx(rotated_pose), "A replay adapts the authored route endpoint to the actual Q/E gameplay view")
	check(entry._route_curve != path.curve, "Adapting a replay never rewrites the authored route resource")
	entry.skip()
	camera._yaw_offset_degrees = saved_yaw
	camera.snap_to_target()
	entry.play()
	entry.set_process(false)

func quiet_map(map: Node) -> void:
	map.get_node("LoadoutUI").save_enabled = false
	map.get_node("MapEffects/BGM").music_enabled = false
	map.get_node("MapEffects/Weather").rain_audio_enabled = false
	map.get_node("MapEffects/Weather").wind_audio_enabled = false
	map.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	if map.has_node("GameSettingsUI"): map.get_node("GameSettingsUI").save_graphics_settings = false
	for audio in map.find_children("UIAudio", "", true, false): audio.enabled = false

func traversal_audio_checks() -> void:
	var world := fixture()
	root.add_child(world)
	await frames()
	var entry = world.get_node("WorldEntry")
	entry.settings.traversal_sound = load("res://assets/meowa/audio/world_entry/mist_glide.mp3")
	check(entry.settings.traversal_sound.get_length() >= 6.9, "Meowa traversal sound has its complete cinematic body and tail")
	entry.play(false)
	entry.set_process(false)
	entry.advance(1.0)
	check(entry._traversal == null, "Hidden menu prewarm never starts traversal audio")
	entry.skip()
	entry.play()
	entry.set_process(false)
	entry.advance(0.1)
	var voice: AudioStreamPlayer = entry._traversal
	check(is_instance_valid(voice) and voice.playing, "Visible entry starts its dedicated traversal voice")
	var opening_db: float = voice.volume_db
	entry.advance(2.0)
	check(voice.volume_db > opening_db + 5.0, "Air rush builds with camera travel rather than staying at a constant level")
	check(Engine.time_scale == 1.0 and not paused, "Cinematic sound does not change world time or pause state")
	entry.settings.traversal_audio_enabled = false
	entry.advance(0.1)
	check(not voice.playing, "Turning off traversal audio stops the current sound")
	entry.settings.traversal_audio_enabled = true
	entry.advance(0.1)
	check(voice.playing and entry._traversal == voice, "Reenabling resumes the same voice at the current sequence position")
	entry.advance(entry.settings.duration_seconds * entry.settings.arrival_ratio - entry._elapsed + 0.7)
	check(voice.volume_db < opening_db, "Arrival fades the air rush while clouds continue clearing")
	entry.skip()
	check(not voice.playing and entry._traversal == null, "Skip stops sound immediately and releases the cinematic voice")
	await frames()
	check(not is_instance_valid(voice), "Stopped entry leaves no idle traversal audio node")
	world.free()
	await frames()
	await create_timer(0.35).timeout

func prewarm_checks() -> void:
	var world := fixture()
	root.add_child(world)
	await frames()
	var entry = world.get_node("WorldEntry")
	var camera := world.get_node("Camera") as FollowCamera
	var original_environment := camera.environment
	var normal_pose := camera.global_transform
	entry.settings.duration_seconds = 600.0
	check(entry.has_method("prewarm"), "Entry provides draw-driven prewarming independent of cinematic duration")
	if not entry.has_method("prewarm"):
		world.free()
		return
	check(entry.prewarm(), "Hidden preparation starts the real entry materials")
	entry.set_process(false)
	check(entry.active and not entry.is_processing_input() and entry._traversal == null, "Prewarm owns only the scene camera, without consuming menu input or playing audio")
	entry.advance(300.0)
	check(is_zero_approx(entry._elapsed), "Long elapsed frames cannot skip a prewarm render state")
	var poses: Array[Transform3D] = []
	for state in 4:
		poses.append(camera.global_transform)
		entry._on_render_frame()
		check(entry.active and camera.global_transform.is_equal_approx(poses[-1]), "Each representative state survives its first drawn frame")
		entry._on_render_frame()
	check(not entry.active and not entry.is_processing(), "Four states finish after eight drawn frames, even for a ten-minute cinematic")
	check(not poses[0].is_equal_approx(poses[1]) and not poses[1].is_equal_approx(poses[2]), "Prewarm visits flight, arrival and clearing poses rather than repeatedly warming one view")
	check(camera.environment == original_environment and camera.global_transform.is_equal_approx(normal_pose) and camera.is_processing(), "Prewarm restores the original environment and camera")
	check(world.get_node("HUD").visible and not world.get_node("HiddenHUD").visible and not entry.is_in_group(&"gameplay_input_blockers"), "Prewarm restores visibility and its own input blocker")
	check(entry.settings.duration_seconds == 600.0 and entry.play(), "The visible entry retains its authored duration and can play after prewarm")
	entry.set_process(false)
	entry.advance(0.5)
	check(entry.active and is_equal_approx(entry._elapsed, 0.5) and entry.is_processing_input(), "Actual entry still advances continuously and owns skip input")
	entry.skip()
	check(entry.prewarm(), "Prewarm can restart after cancellation")
	entry.skip()
	check(not entry.active and camera.environment == original_environment, "Cancellation releases partial prewarm state")
	entry.settings.duration_seconds = 0.0
	check(not entry.prewarm() and not entry.active and not entry._prewarming, "An instant or disabled entry leaves no pending prewarm")
	entry.settings.duration_seconds = 600.0
	entry.prewarm()
	entry.set_process(false)
	world.get_node("Player").free()
	entry._on_render_frame()
	check(not entry.active and entry._render_wait_frames == 0 and camera.environment == original_environment, "Removing the entry target releases pending render work immediately")
	world.free()
	await frames()

func run() -> void:
	request_checks()
	await prewarm_checks()
	await timeline_checks()
	await sky_approach_checks()
	await continuity_checks()
	await cloud_flight_checks()
	await lifecycle_checks()
	await traversal_audio_checks()
	await formal_checks()
	REQUEST.clear()
	await frames()
	print(JSON.stringify({"suite":"world_entry", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
