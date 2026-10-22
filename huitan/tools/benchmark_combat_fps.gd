extends "res://tools/benchmark_native_queries.gd"
## Explicit rendered benchmark, requested by the user. No screenshot capture.
## Real wall clock, 128 monsters, formal camera/materials; requires a display.
var gpu_timing := false

func _initialize() -> void:
	super._initialize()
	rendered_fps = true
	gpu_timing = "--gpu-timing" in OS.get_cmdline_user_args()
	DisplayServer.window_set_title("HD-2D | 128 enemies | " + ("native CPU candidate" if native_swarm else "script CPU"))
	if gpu_timing: RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)

func end_process(delta: float) -> void:
	if gpu_timing and process_stamp > 0:
		for metric in ["viewport_render_cpu_ms", "viewport_render_gpu_ms"]:
			if not measurements[process_stage].has(metric): measurements[process_stage][metric] = []
		# Viewport timestamps arrive asynchronously from earlier rendered frames.
		# They are renderer timings, not additive with whole-frame wall time.
		push_sample(process_stage, "viewport_render_cpu_ms", RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		push_sample(process_stage, "viewport_render_gpu_ms", RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	super.end_process(delta)

func inspect_behaviour(tick: int) -> void:
	super.inspect_behaviour(tick)
	var visible := 0
	for enemy in wave.enemies:
		if player.movement_camera.is_position_in_frustum(enemy.global_position + Vector3.UP * 0.5): visible += 1
	behaviours[-1]["in_frustum_at_phase_end"] = visible
	behaviours[-1]["engine_reported_fps"] = Engine.get_frames_per_second()
