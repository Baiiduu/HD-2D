extends SceneTree

## 原生渲染下的真实怪物压力入口，不修改场景或存档。
## -- --uncapped --counts=0,112,128,200,300 --warmup=16 --duration=15 --output=D:/.../population.json
## --combat 开启满级技能／增益、真实掉落与补怪；--walk 使用原人物输入和碰撞走位。
var counts := PackedInt32Array([128, 256, 512, 768])
var sample_seconds := 3.0
var output := "D:/.codexfile/work/enemy-framework/population.json"
var world: Node3D
var wave: WavePrototype
var player: Player
var results: Array[Dictionary] = []
var uncapped := false
var warmup_seconds := 8.0
var frozen_movement := false
var combat := false
var walk := false
var _walk_key: int = 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--counts="):
			counts.clear()
			for value in argument.trim_prefix("--counts=").split(","): counts.append(value.to_int())
		elif argument.begins_with("--duration="): sample_seconds = argument.trim_prefix("--duration=").to_float()
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument == "--uncapped": uncapped = true
		elif argument.begins_with("--warmup="): warmup_seconds = argument.trim_prefix("--warmup=").to_float()
		elif argument == "--frozen-movement": frozen_movement = true
		elif argument == "--combat": combat = true
		elif argument == "--walk": walk = true
	if counts.is_empty() or sample_seconds <= 0.0:
		push_error("需要数量档位和正数采样时长")
		quit(1)
		return
	run.call_deferred()

func settle(count := 4) -> void:
	for frame in count: await physics_frame

func percentile(values: Array[float], fraction: float) -> float:
	values.sort()
	return values[mini(floori(values.size() * fraction), values.size() - 1)] if not values.is_empty() else 0.0

func _combat_build() -> void:
	var skills: RunSkills = wave.get_node("RunSkills")
	for id in skills._components:
		var definition: CombatSkillDefinition = skills._components[id].get_skill_definition()
		for level in range(skills.get_level(id) + 1, definition.levels.size() + 1):
			skills.candidates()
			skills._choose(0, StringName("skill:%s:%d" % [id, level]))
	var buffs: RunBuffs = wave.get_node("RunBuffs")
	for definition in buffs.definitions:
		for level in definition.max_level:
			buffs.candidates()
			buffs._choose(0, definition.id)

func _maintain_population(target: int) -> void:
	if not combat or target == 0 or wave.phase != WavePrototype.Phase.BATTLE: return
	var missing := target - wave.enemies.size() - wave._pending
	if missing > 0: wave.queue_spawn(wave.default_enemy, missing, 0.0, Vector3.INF, PackedStringArray(), 0.1, 0.001)

func _walk_input() -> void:
	var desired: int = [KEY_D, KEY_S, KEY_A, KEY_W][int(Time.get_ticks_msec() / 800) % 4] if walk else 0
	if _walk_key == desired: return
	if _walk_key:
		var release := InputEventKey.new()
		release.physical_keycode = _walk_key
		release.keycode = _walk_key
		Input.parse_input_event(release)
	_walk_key = desired
	if desired:
		var press := InputEventKey.new()
		press.physical_keycode = desired
		press.keycode = desired
		press.pressed = true
		Input.parse_input_event(press)

func run() -> void:
	if uncapped:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	var growth: RunGrowth = world.get_node("WavePrototype/RunGrowth")
	growth.enabled = combat
	if combat:
		# 测试构筑通过真实升级接口建立；保留掉落／吸取，避免测量被升级选择冻结打断。
		growth.rules = growth.rules.duplicate() as ExperienceRules
		growth.rules.first_level_experience = 1000000000
	root.add_child(world)
	current_scene = world
	await settle(16)
	wave = world.get_node("WavePrototype")
	player = world.get_node("Player")
	player.set_physics_process(false)
	player.max_health = 100000000.0
	for target in counts:
		if target < 0 or target > 4096:
			push_error("压测数量必须在 0～4096")
			quit(1)
			return
		if wave.phase in [WavePrototype.Phase.BATTLE, WavePrototype.Phase.REST]: wave.retreat()
		if wave.phase == WavePrototype.Phase.RESULT: wave.return_home()
		await settle()
		for component: Node in (wave.get_node("RunSkills") as RunSkills)._components.values(): component.process_mode = Node.PROCESS_MODE_INHERIT
		var rules: WavePopulationRules = load("res://data/waves/population/stress_768.tres").duplicate(true)
		rules.first_active_limit = maxi(target, 1)
		rules.max_active = maxi(target, 1)
		rules.max_population_cost = maxi(target * 2, 1)
		rules.role_limits[0] = maxi(target, 1)
		if combat: rules.max_queued_per_wave = 32768
		var group := WaveSpawnEntry.new()
		group.enemy = wave.default_enemy
		group.count = maxi(target, 1)
		group.start_delay = 0.0
		group.interval = 0.001
		group.warning_seconds = 0.1
		var plan := WaveDefinition.new()
		plan.entries.append(group)
		wave.waves.assign([plan])
		wave.population_rules = rules
		wave.endless_mode = combat
		player.global_position = wave.global_position + Vector3.UP * 0.03
		(player.movement_camera as FollowCamera).snap_to_target()
		var choice: GrowthChoiceUI = wave.get_node("RunSkills/InitialSkillChoice")
		choice.open_duration = 0.0
		wave.start_run()
		if choice.is_open:
			if not choice.select_option(&"initial:fan_slash"):
				choice.select_option(choice._options[0].id)
			choice.confirm_selection()
		if combat:
			wave.wave = 63
			_combat_build()
		else:
			for component: Node in (wave.get_node("RunSkills") as RunSkills)._components.values(): component.process_mode = Node.PROCESS_MODE_DISABLED
		wave.set_physics_process(target > 0)
		if target == 0: wave._spawn_queue.clear()
		# 开局仍使用正式交互点；采样在战场内部，让实际镜头覆盖追击怪潮。
		var center := wave.battle_area.get_center()
		var point := wave._path.graph.get_closest_point(Vector3(center.x, 0.0, center.y))
		player.global_position = wave._path.graph.get_point_position(point) + Vector3.UP * 0.03
		(player.movement_camera as FollowCamera).snap_to_target()
		player.set_physics_process(walk)
		var start := Time.get_ticks_msec()
		var peak := 0
		while wave.phase == WavePrototype.Phase.BATTLE and wave.enemies.size() < target and Time.get_ticks_msec() - start < 90000:
			peak = maxi(peak, wave.enemies.size())
			player.heal(player.max_health)
			await physics_frame
		if wave.enemies.size() != target:
			results.append({"target": target, "reached": peak, "pending": wave._pending, "reason": wave.result_reason})
			print("POPULATION_FAILED ", JSON.stringify(results[-1]))
			break
		var spawn_seconds := float(Time.get_ticks_msec() - start) / 1000.0
		var warmup_until := Time.get_ticks_msec() + int(maxf(warmup_seconds, 0.0) * 1000.0)
		while Time.get_ticks_msec() < warmup_until:
			player.heal(player.max_health)
			_maintain_population(target)
			_walk_input()
			await physics_frame
		if frozen_movement:
			for enemy in wave.enemies: enemy.set_physics_process(false)
		var frames: Array[float] = []
		var physics: Array[float] = []
		var process: Array[float] = []
		var stamp := Time.get_ticks_usec()
		var sample_start := stamp
		var visible_min := target
		var visible_max := 0
		var visible_at := stamp
		var alive_min := wave.enemies.size()
		var alive_max := alive_min
		var kills_at := wave.kills
		var pickup_peak := growth._drops.size()
		while Time.get_ticks_usec() - sample_start < int(sample_seconds * 1000000.0):
			player.heal(player.max_health)
			_maintain_population(target)
			_walk_input()
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append(float(now - stamp) / 1000.0)
			physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			process.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			stamp = now
			alive_min = mini(alive_min, wave.enemies.size())
			alive_max = maxi(alive_max, wave.enemies.size())
			pickup_peak = maxi(pickup_peak, growth._drops.size())
			if now >= visible_at:
				var visible := 0
				for enemy in wave.enemies:
					if (player.movement_camera as Camera3D).is_position_in_frustum(enemy.global_position + Vector3.UP * 0.5): visible += 1
				visible_min = mini(visible_min, visible)
				visible_max = maxi(visible_max, visible)
				visible_at = now + 1000000
		var sample := {"target": target, "reached": wave.enemies.size(), "pending": wave._pending,
			"alive_min":alive_min, "alive_max":alive_max, "kills_during_sample":wave.kills - kills_at, "pickups_peak":pickup_peak,
			"battle_active":wave.phase == WavePrototype.Phase.BATTLE,
			"in_frustum_min":visible_min, "in_frustum_max":visible_max,
			"average_fps":frames.size() * 1000000.0 / (Time.get_ticks_usec() - sample_start),
			"spawn_wall_seconds": spawn_seconds,
			"frame_p50_ms": percentile(frames, 0.5), "frame_p95_ms": percentile(frames, 0.95),
			"frame_p99_ms":percentile(frames, 0.99),
			"physics_p50_ms": percentile(physics, 0.5), "physics_p95_ms": percentile(physics, 0.95),
			"process_p50_ms": percentile(process, 0.5), "process_p95_ms": percentile(process, 0.95),
			"shared_field_builds": wave._path.shared_field_builds, "neighbor_candidate_checks": wave._spatial_index.candidate_checks}
		results.append(sample)
		print("POPULATION_SAMPLE ", JSON.stringify(sample))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.get_base_dir().path_join("population_%d.png" % target))
	var report := {"renderer": DisplayServer.get_name(), "headless": DisplayServer.get_name() == "headless",
		"gpu": RenderingServer.get_video_adapter_name(), "viewport": str(root.size), "physics_ticks_per_second": Engine.physics_ticks_per_second,
		"sample_seconds": sample_seconds, "engine_version": Engine.get_version_info().string,
		"uncapped":uncapped,
		"warmup_seconds":warmup_seconds, "frozen_movement_diagnostic":frozen_movement,
		"combat_max_build":combat, "walk":walk, "skills":(wave.get_node("RunSkills") as RunSkills).get_slots(),
		"camera":{"fov":player.movement_camera.fov, "distance":player.movement_camera.get("distance"), "pitch_degrees":player.movement_camera.get("pitch_degrees")},
		"note": "正式场景／相机／动画／天气，持续回血。完整战斗开关启用真实满级技能与增益、掉落及补怪；经验升级门槛仅在测试中提高，避免升级选择冻结。相机视锥计数不扣除建筑遮挡。", "samples": results}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t"))
	else: push_error("无法写入压力结果：" + output)
	walk = false
	_walk_input()
	wave.retreat()
	await settle()
	world.queue_free()
	await settle()
	quit(0 if results.size() == counts.size() and results.all(func(sample: Dictionary): return sample.get("battle_active", false) and (combat or sample.reached == sample.target)) else 1)
