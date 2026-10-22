extends SceneTree
## Read-only idle-world diagnosis. Rendered execution requires --allow-rendered.
## No spawning, input injection, screenshots, source/settings saves, or visual acceptance.

class EndProbe extends Node:
	var audit: SceneTree
	func _physics_process(_delta: float) -> void: audit.end_physics()
	func _process(_delta: float) -> void: audit.end_process()

var world: Node3D
var wave: WavePrototype
var player: Player
var camera: Camera3D
var views: Array[Viewport] = []
var lights: Array[Light3D] = []
var shadows: Array[bool] = []
var stages := {}
var stage := ""
var output := ""
var count := 240
var warmup := 90
var cpu_only := false
var timing := true
var only_baseline := false
var focus_shadows := false
var physics_stamp := 0
var process_stamp := 0
var draw_stamp := 0
var physics_count := 0
var last_physics_count := 0
var original_player := Vector3.ZERO
var original_camera := Transform3D.IDENTITY
var failures: Array[String] = []
var inventory := {}
var pre_draw_stamp := 0
var preserve_vsync := false
var completed := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg.begins_with("--frames="): count = maxi(30, arg.trim_prefix("--frames=").to_int())
		elif arg.begins_with("--warmup="): warmup = maxi(5, arg.trim_prefix("--warmup=").to_int())
		elif arg == "--cpu-only": cpu_only = true
		elif arg == "--baseline-only": only_baseline = true
		elif arg == "--focus-shadows": focus_shadows = true
		elif arg == "--keep-vsync": preserve_vsync = true
	if output.is_empty() or (not cpu_only and (DisplayServer.get_name() == "headless" or not "--allow-rendered" in OS.get_cmdline_user_args())):
		push_error("Specify --output and either --cpu-only --headless or explicit --allow-rendered with a real display")
		quit(2)
		return
	if cpu_only and DisplayServer.get_name() != "headless": quit(2); return
	RenderingServer.frame_pre_draw.connect(begin_pre_draw)
	create_timer(600.0).timeout.connect(func(): push_error("Empty-world audit timeout"); quit(2))
	run.call_deferred()

func ensure(value: bool, reason: String) -> void:
	if not value: failures.append(reason); push_error(reason)

func push(metric: String, value: float) -> void:
	if stage.is_empty(): return
	if not stages[stage].has(metric): stages[stage][metric] = []
	stages[stage][metric].append(value)

func begin_physics() -> void:
	physics_stamp = Time.get_ticks_usec()
	physics_count += 1

func begin_process() -> void:
	process_stamp = Time.get_ticks_usec()

func begin_pre_draw() -> void:
	pre_draw_stamp = Time.get_ticks_usec()

func end_pre_draw() -> void:
	push("pre_draw_signal_callbacks_ms", (Time.get_ticks_usec() - pre_draw_stamp) / 1000.0)

func end_physics() -> void:
	push("physics_callbacks_ms_per_step", (Time.get_ticks_usec() - physics_stamp) / 1000.0)

func end_process() -> void:
	push("process_callbacks_ms_per_frame", (Time.get_ticks_usec() - process_stamp) / 1000.0)
	push("engine_physics_peak_last_second_ms", Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	if cpu_only: return
	var now := Time.get_ticks_usec()
	if draw_stamp > 0:
		push("wall_frame_ms", (now - draw_stamp) / 1000.0)
		push("physics_steps_per_frame", physics_count - last_physics_count)
	draw_stamp = now
	last_physics_count = physics_count
	if stage.is_empty() or not timing: return
	var meter_start := Time.get_ticks_usec()
	var setup := RenderingServer.get_frame_setup_time_cpu()
	var render_cpu := 0.0
	var gpu := 0.0
	var active := 0
	for view in views:
		if view is SubViewport and view.render_target_update_mode == SubViewport.UPDATE_DISABLED: continue
		if view is Window and not view.visible: continue
		active += 1
		var rid := view.get_viewport_rid()
		var cpu_ms := RenderingServer.viewport_get_measured_render_time_cpu(rid)
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		render_cpu += cpu_ms
		gpu += gpu_ms
		push("viewport_cpu:" + String(view.name), cpu_ms)
		push("viewport_gpu:" + String(view.name), gpu_ms)
	push("render_setup_cpu_ms", setup)
	push("render_viewports_cpu_ms", render_cpu)
	push("render_total_cpu_ms", setup + render_cpu)
	push("render_viewports_gpu_ms", gpu)
	push("active_viewports", active)
	push("draw_calls_all", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	for entry in [["visible", RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE], ["shadow", RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW]]:
		push("root_" + entry[0] + "_draw_calls", RenderingServer.viewport_get_render_info(root.get_viewport_rid(), entry[1], RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
	push("meter_read_cpu_ms", (Time.get_ticks_usec() - meter_start) / 1000.0)

func scan(node: Node) -> void:
	if node is Viewport: views.append(node)
	if node is Light3D:
		lights.append(node)
		shadows.append(node.shadow_enabled)
	for child in node.get_children(): scan(child)

func set_timers(enabled: bool) -> void:
	timing = enabled
	if not cpu_only:
		for view in views: RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), enabled)

func frames(amount: int) -> void:
	for index in amount: await process_frame

func sample(label: String) -> void:
	stage = ""
	await frames(warmup)
	ensure(wave.phase == WavePrototype.Phase.READY and wave.enemies.is_empty(), "Idle READY with zero enemies: " + label)
	ensure(player.global_position.distance_to(original_player) < 0.001, "Player remains stationary: " + label)
	ensure(camera.global_transform.is_equal_approx(original_camera), "Camera unchanged: " + label)
	stages[label] = {}
	stage = label
	draw_stamp = 0
	await frames(count)
	stage = ""
	var stats := summarize(stages[label].get("wall_frame_ms", []))
	print("EMPTY_WORLD_PHASE ", label, " wall_ms=", stats.get("mean", 0.0))
	write_report()

func summarize(values: Array) -> Dictionary:
	if values.is_empty(): return {"samples": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var sum := 0.0
	for value in values: sum += value
	return {"samples": values.size(), "mean": sum / values.size(), "p50": sorted[sorted.size() / 2], "p95": sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))], "min": sorted[0], "max": sorted[-1]}

func write_report() -> void:
	var summary := {}
	for label in stages:
		summary[label] = {}
		for metric in stages[label]: summary[label][metric] = summarize(stages[label][metric])
	var report := {"schema": 1, "completed": completed, "diagnostic_only": true, "cpu_only": cpu_only, "engine": Engine.get_version_info(),
		"gpu": RenderingServer.get_video_adapter_name(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "display": DisplayServer.get_name(),
		"window_pixels": str(DisplayServer.window_get_size()) if not cpu_only else "headless",
		"logical_viewport": str(root.get_visible_rect().size), "physics_hz": Engine.physics_ticks_per_second,
		"render_thread_model": ProjectSettings.get_setting("rendering/driver/threads/thread_model", 1),
		"vsync_mode": DisplayServer.window_get_vsync_mode() if not cpu_only else -1,
		"inventory": inventory, "failures": failures, "summary": summary, "raw": stages,
		"notes": ["Live zero-monster READY state, no input/attack/start_run; no source/user settings saved.",
		"CPU callback windows exclude native physics stepping, engine work and renderer; physics is per step, process/render per display frame.",
		"Viewport timings are asynchronous. CPU render totals sum global setup plus active viewports; CPU/GPU overlap and are not additive.",
		"engine_physics_peak_last_second_ms is the engine's rolling one-second maximum, including native physics; not an individual frame/step sample.",
		"root_visible_draw_calls means all visible-pass draws, not exclusively opaque. Shadow draw count is separate.",
		"Frozen/disabled effects are diagnostic ablations, not accepted optimization or visual QA."]}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if not file: push_error("Cannot write report: " + output); quit(2); return
	file.store_string(JSON.stringify(report, "\t"))

func run() -> void:
	seed(617)
	if not cpu_only:
		DisplayServer.window_set_title("HD-2D | empty world performance diagnosis")
		if not preserve_vsync: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	AudioServer.set_bus_mute(0, true)
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("GameSettingsUI").save_graphics_settings = false
	root.add_child(world)
	current_scene = world
	wave = world.get_node("WavePrototype")
	player = world.get_node("Player")
	camera = player.movement_camera
	await frames(180)
	# Startup, camera follow, gravity, navigation and deferred material setup settle first.
	await create_timer(3.0).timeout
	original_player = player.global_position
	original_camera = camera.global_transform
	scan(root)
	inventory = {"nodes": get_node_count(), "lights": lights.size(), "shadow_lights": shadows.count(true),
		"viewports": views.size(), "camera_fov": camera.fov, "camera_transform": str(original_camera), "player": str(original_player),
		"environment": {}, "active_process_nodes": [], "light_details": [], "viewport_details": [], "screen_pixels": str(DisplayServer.screen_get_size()) if not cpu_only else "headless"}
	for light in lights:
		inventory.light_details.append({"path": String(world.get_path_to(light)), "type": light.get_class(), "shadow": light.shadow_enabled, "visible": light.is_visible_in_tree(), "mask": light.light_cull_mask, "range": light.omni_range if light is OmniLight3D else 0.0, "position": str(light.global_position)})
	for view in views:
		inventory.viewport_details.append({"path": String(root.get_path_to(view)), "size": str(view.get_visible_rect().size), "mode": view.render_target_update_mode if view is SubViewport else -1})
	var env: Environment = world.get_node("MapEffects/WorldEnvironment").environment
	for property in ["ssao_enabled", "ssil_enabled", "ssr_enabled", "glow_enabled", "volumetric_fog_enabled"]: inventory.environment[property] = env.get(property)
	for node in world.find_children("*", "Node", true, false):
		if node.is_processing() or node.is_physics_processing(): inventory.active_process_nodes.append(String(world.get_path_to(node)))
	var probe := EndProbe.new()
	probe.audit = self
	probe.process_priority = 1000000
	probe.process_physics_priority = 1000000
	root.add_child(probe)
	physics_frame.connect(begin_physics)
	process_frame.connect(begin_process)
	RenderingServer.frame_pre_draw.connect(end_pre_draw)
	set_timers(not cpu_only)
	await sample("live_full_A1")
	if not cpu_only:
		set_timers(false)
		await sample("live_no_meters_B1")
		await sample("live_no_meters_B2")
		set_timers(true)
		await sample("live_full_A2")
	if not only_baseline:
		world.process_mode = Node.PROCESS_MODE_DISABLED
		await sample("frozen_full")
		if not cpu_only:
			var gate := root.get_node_or_null("EmptyWaterShadowGate")
			var gate_desired: Dictionary = gate._desired.duplicate() if gate else {}
			if gate:
				for key in gate._desired: gate._desired[key] = false
			for light in lights: light.shadow_enabled = false
			await sample("frozen_no_shadows")
			if gate:
				for key in gate_desired: gate._desired[key] = gate_desired[key]
			for index in lights.size(): lights[index].shadow_enabled = shadows[index]
			await sample("frozen_shadows_restored")
			if focus_shadows:
				for kind in ["directional", "positional", "fill_omni", "cone_spot", "water_only"]:
					if gate and kind == "water_only":
						for key in gate._desired: gate._desired[key] = false
					for index in lights.size():
						var light := lights[index]
						var match_kind: bool = (light is DirectionalLight3D and kind == "directional") or (not light is DirectionalLight3D and kind == "positional") or (String(light.name) == "WaterLight" and kind == "water_only") or (light is OmniLight3D and String(light.name) != "WaterLight" and kind == "fill_omni") or (light is SpotLight3D and kind == "cone_spot")
						if match_kind: light.shadow_enabled = false
					await sample("frozen_no_" + kind + "_shadows")
					if gate:
						for key in gate_desired: gate._desired[key] = gate_desired[key]
					for index in lights.size(): lights[index].shadow_enabled = shadows[index]
					await sample("frozen_restored_after_" + kind)
			var reflection = world.get_node("MapEffects/WaterReflection")
			if not reflection.views.is_empty():
				var mirror_modes: Array[int] = []
				for view in reflection.views:
					mirror_modes.append(view.viewport.render_target_update_mode)
					view.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
				await sample("frozen_no_water_mirror")
				for index in reflection.views.size(): reflection.views[index].viewport.render_target_update_mode = mirror_modes[index]
			for property in ([] if focus_shadows else ["ssao_enabled", "ssil_enabled", "ssr_enabled", "volumetric_fog_enabled", "glow_enabled"]):
				var old: bool = env.get(property)
				env.set(property, false)
				await sample("frozen_no_" + property)
				env.set(property, old)
			var old_scale := root.scaling_3d_scale
			root.scaling_3d_scale = old_scale * 0.5
			await sample("frozen_half_3d_resolution")
			root.scaling_3d_scale = old_scale
			await sample("frozen_full_restored")
			var disable_3d: Array[bool] = []
			for view in views:
				disable_3d.append(view.disable_3d)
				view.disable_3d = true
			await sample("frozen_no_3d")
			for index in views.size(): views[index].disable_3d = disable_3d[index]
	world.process_mode = Node.PROCESS_MODE_INHERIT
	completed = true
	write_report()
	world.queue_free()
	await create_timer(1.0).timeout
	await frames(2)
	print("EMPTY_WORLD_DONE failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
