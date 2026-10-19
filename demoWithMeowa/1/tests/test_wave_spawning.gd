extends SceneTree

const PROBE := preload("res://tests/fixtures/wave_probe_enemy.gd")
var world: Node3D
var wave: WavePrototype
var player: Player
var checks := 0
var failures: Array[String] = []
var original_exclusions: Array[Rect2] = []
var immediate_spawns := true

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL: ", label)

func frames(count := 6) -> void:
	for frame in count: await physics_frame

func definition(health := 30.0) -> WaveEnemyDefinition:
	var node := PROBE.new()
	var packed := PackedScene.new()
	assert(packed.pack(node) == OK)
	node.free()
	var resource := WaveEnemyDefinition.new()
	resource.scene = packed
	resource.health = health
	resource.move_speed = 0.0
	resource.attack_damage = 0.0
	resource.experience_reward = 0
	return resource

func entry(enemy: WaveEnemyDefinition, count := 1, delay := 0.0, ids := PackedStringArray()) -> WaveSpawnEntry:
	var resource := WaveSpawnEntry.new()
	resource.enemy = enemy
	resource.count = count
	resource.start_delay = delay
	resource.interval = .01
	resource.spawn_zone_ids = ids
	return resource

func plan(entries: Array[WaveSpawnEntry]) -> WaveDefinition:
	var resource := WaveDefinition.new()
	resource.entries.assign(entries)
	return resource

func hold() -> void:
	for enemy in wave.enemies: enemy.set_physics_process(false)

func start() -> bool:
	if not wave.start_run(): return false
	choose_initial()
	return wave.phase == WavePrototype.Phase.BATTLE

func choose_initial() -> void:
	var skills := wave.get_node("RunSkillManager") as RunSkillManager
	if wave.skill_draft.initial_choice.is_open:
		wave.skill_draft.initial_choice.reveal_now()
		wave.skill_draft.initial_choice.select_option(wave.skill_draft.initial_choice._options[0].id)
		wave.skill_draft.initial_choice.confirm_selection()
	for component: Node in skills._components.values(): component.process_mode = Node.PROCESS_MODE_DISABLED

func reset() -> void:
	wave._finish("fixture reset")
	wave.return_home()
	wave.waves.clear()
	wave.total_waves = 2
	wave.first_wave_enemies = 1
	wave.enemies_per_wave = 0
	wave.max_active_enemies = 30
	wave.max_spawns_per_tick = 2
	wave.max_spawn_checks_per_tick = 4
	wave.max_spawns_per_wave = 512
	wave.spawn_safe_distance = 5
	wave.spawn_spacing = 1.2
	wave.spawn_block_timeout = 10
	wave.spawn_retry_interval = .3
	wave.spawn_excluded_areas.assign(original_exclusions)
	player.global_position = wave.global_position + Vector3.UP * .03
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()

func run() -> void:
	var protected := FileAccess.get_sha256("res://data/world/world_terrain.tres")
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("WavePresentation").enabled = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	current_scene = world
	await frames(12)
	wave = world.get_node("WavePrototype")
	# 旧排期／容量回归沿用即时生成，预告机制由 test_spawn_shadows 覆盖。
	wave.spawn_shadow_settings = null
	# 旧预警配置不应让普通怪、怪潮或分裂幼体在生成后额外等待。
	wave.spawn_warning = 0.8
	wave.enemy_spawned.connect(func(enemy: WaveEnemy): immediate_spawns = immediate_spawns and enemy.spawn_delay == 0.0)
	wave.endless_mode = false # 有限模式仍覆盖原三波胜利与刷新边界。
	wave.population_rules = null
	wave.health_growth_rules = null
	wave.max_active_enemies = 24
	player = world.get_node("Player")
	wave.set_physics_process(false)
	player.set_physics_process(false)
	wave.get_node("FanAutoAttack").enabled = false
	original_exclusions.assign(wave.spawn_excluded_areas)
	var navigation_points := wave._path.graph.get_point_count()
	var nav_bounds := wave.battle_area.grow(wave.terrain.data.cell_size * 2.0)
	var nav_inside := wave._path.graph.get_point_count() > 0
	for id in wave._path.graph.get_point_ids():
		var point := wave._path.graph.get_point_position(id)
		nav_inside = nav_inside and nav_bounds.has_point(Vector2(point.x, point.z))
	check(nav_inside, "Wave navigation stays within arena and apron on the current sparse map")
	check(wave._spawn_zones.size() == 6, "All six perimeter zones connected")
	check(wave.waves.size() == 3, "Production uses three editable wave resources")
	check(wave.max_active_enemies == 24, "Production admits at most 24 simultaneous enemies")
	player.global_position = wave.global_position + Vector3.UP * .03
	check(start(), "Production wave starts")
	var expected_totals := [18, 28, 40]
	var peak_population := 0
	for index in expected_totals.size():
		check(wave._pending == expected_totals[index], "Production registers entire rhythmic wave %d" % (index + 1))
		var groups := wave.waves[index].entries
		var horde: WaveSpawnEntry = groups.filter(func(item): return item.mixed_horde)[0]
		check(horde.start_delay - (groups[0].start_delay + groups[0].spawn_duration()) >= 3.0, "Scouts leave a short spawning lull before the first mixed horde")
		var expected: int = expected_totals[index]
		for job in wave._spawn_queue:
			if job.enemy.enemy_id == &"pot_brood": expected += 2
		var largest_batch := 1
		for item in groups: largest_batch = maxi(largest_batch, item.batch_size)
		var horde_radius := sqrt(float(largest_batch)) * maxf(wave.spawn_spacing, wave._largest_spawn_clearance * 2.0) * 1.25
		wave._physics_process(.59)
		check(wave.enemies.is_empty(), "Wave begins with a short lead-in")
		var steps := 0
		var safety_ok := true
		while wave.phase == WavePrototype.Phase.BATTLE and steps < 240:
			wave._physics_process(.3)
			hold()
			peak_population = maxi(peak_population, wave.enemies.size())
			for enemy in wave.enemies:
				safety_ok = safety_ok and not original_exclusions[0].has_point(Vector2(enemy.global_position.x, enemy.global_position.z))
				if enemy.definition.enemy_id != &"mini_slime":
					safety_ok = safety_ok and wave._spawn_zones.any(func(zone: WaveSpawnZone): return TerrainPath.horizontal_distance(zone.global_position, enemy.global_position) <= maxf(zone.radius, horde_radius) + 0.01)
			if wave.enemies.size() == wave.max_active_enemies or wave._capacity_waiting > 0 or steps % 8 == 0:
				for enemy in wave.enemies.duplicate().slice(0, 8):
					enemy.spawn_delay = 0
					enemy.take_damage(1000)
			steps += 1
		check(wave._pending == 0 and wave._spawned_this_wave == expected and wave.enemies.is_empty(), "Every queued primary and split child spawns and is defeated for production wave %d" % (index + 1))
		check(safety_ok, "Larger groups stay in valid perimeter zones and outside entrance")
		if index < expected_totals.size() - 1:
			check(wave.phase == WavePrototype.Phase.REST, "Production clear enters a safe break")
			check(wave.start_next_wave(), "Production next wave requires an explicit start")
	check(peak_population > 0 and peak_population <= 24, "Mixed production hordes respect the requested simultaneous cap")
	check(immediate_spawns, "All primary and split-child spawns are active immediately")
	check(wave.outcome == WavePrototype.Outcome.VICTORY and wave.kills == wave._spawned_run and wave._spawned_run > 86, "Full production run completes all 86 primary monsters and their split children without losing queued jobs")
	# 开始通知中的清波请求不能把新波次当成空波。
	reset()
	var clear_on_start := func(value: int):
		if value == WavePrototype.Phase.BATTLE: wave._clear_wave()
	wave.phase_changed.connect(clear_on_start)
	check(start() and wave.phase == WavePrototype.Phase.BATTLE and wave.completed_waves == 0 and wave._pending == 1, "Reentrant start notification sees fully registered queue")
	wave.phase_changed.disconnect(clear_on_start)
	# 临时无安全点保留任务；腾出空间后继续。
	wave.spawn_safe_distance = 500
	wave._physics_process(.31)
	check(wave.phase == WavePrototype.Phase.BATTLE and wave._pending == 1 and wave.enemies.is_empty(), "Temporary obstruction retries without ending run")
	wave.spawn_safe_distance = 5
	wave._physics_process(.31)
	hold()
	check(wave.enemies.size() == 1 and wave._pending == 0, "Blocked job resumes once safe")
	# 同时到期受帧预算限制；满员等待不能被当成位置超时。
	reset()
	var probe := definition()
	wave.waves.assign([plan([entry(probe, 3)])])
	wave.max_active_enemies = 2
	wave.spawn_block_timeout = 2
	check(start(), "Batch fixture starts")
	wave._physics_process(.01)
	hold()
	check(wave.enemies.size() == 2 and wave._pending == 1, "Per-frame budget admits bounded batch")
	check(TerrainPath.horizontal_distance(wave.enemies[0].global_position, wave.enemies[1].global_position) >= wave.spawn_spacing, "Warning enemies reserve spacing")
	wave._physics_process(100)
	check(wave.phase == WavePrototype.Phase.BATTLE and wave.enemies.size() == 2 and wave._pending == 1, "Full capacity postpones queue without dropping jobs or timeout")
	wave.enemies[0].spawn_delay = 0
	wave.enemies[0].take_damage(1000)
	wave._physics_process(.01)
	hold()
	check(wave.enemies.size() == 2 and wave._pending == 0, "Killing releases a slot to waiting spawn")
	# 时间排序、旧预告配置兼容和本局配置快照。
	reset()
	var early := definition(40)
	var first := entry(early, 3)
	first.warning_seconds = .25
	var late := entry(probe, 1, 1.0)
	wave.waves.assign([plan([late, first])])
	wave.max_spawns_per_tick = 1
	check(start(), "Timing fixture starts")
	first.count = 200
	early.health = 1
	wave.waves.clear()
	wave.total_waves = 99
	wave._physics_process(2)
	hold()
	check(wave.enemies.size() == 1 and wave.enemies[0].health == 40 and wave._pending == 3, "Earliest deadline wins; source edits do not change run queue")
	check(wave.enemies[0].spawn_delay == 0.0, "Old group warning configuration cannot delay activation")
	check(wave.wave_count() == 1, "Run wave count stays fixed")
	var before := wave.get_run_state()
	wave.set_combat_frozen(true)
	wave._physics_process(100)
	check(wave.get_run_state().wave_elapsed == before.wave_elapsed and wave._pending == before.pending, "Combat freeze preserves spawn clock and queue")
	wave.set_combat_frozen(false)
	for index in 3:
		wave._physics_process(.01)
		hold()
	check(wave.enemies.size() == 4 and wave.enemies[1].health == 40 and wave.enemies[2].health == 40 and wave.enemies[3].health == 30, "Catch-up retains stable deadline order and snapshots")
	# 被堵住的区域不阻塞同帧其他到期区域。
	reset()
	var blocked_zone := wave._spawn_zones.filter(func(zone: WaveSpawnZone): return zone.name == &"SouthWest")[0] as WaveSpawnZone
	var blocked_xz := Vector2(blocked_zone.global_position.x, blocked_zone.global_position.z)
	wave.spawn_excluded_areas.append(Rect2(blocked_xz - Vector2.ONE * 6, Vector2.ONE * 12))
	wave.waves.assign([plan([entry(probe, 1, 0, PackedStringArray(["SouthWest"])), entry(probe, 1, 0, PackedStringArray(["EastNorth"]))])])
	check(start(), "Independent zones fixture starts")
	wave._physics_process(.01)
	hold()
	check(wave.enemies.size() == 1 and wave._pending == 1 and wave.phase == WavePrototype.Phase.BATTLE, "Blocked zone does not starve another due group")
	# 持续阻塞明确结束，不伪造清波。
	wave.spawn_block_timeout = 2
	wave._physics_process(2.1)
	check(wave.phase == WavePrototype.Phase.RESULT and wave.outcome == WavePrototype.Outcome.ERROR and wave.completed_waves == 0 and wave._pending == 0 and wave.enemies.is_empty(), "Persistent blocked zone aborts and cleans up")
	# 分裂登记在母体死亡前；幼体留在原位置附近并各自占位。
	reset()
	wave.waves.assign([plan([entry(probe)])])
	check(start(), "Local summon fixture starts")
	wave._physics_process(.01)
	hold()
	var parent: WaveEnemy = wave.enemies[0]
	var parent_point := parent.global_position
	parent.child_definition = probe
	parent.spawn_delay = 0
	parent.take_damage(1000)
	wave._clear_wave()
	check(wave.phase == WavePrototype.Phase.BATTLE and wave._pending == 2 and wave.enemies.is_empty(), "Registered children prevent premature clear")
	wave._physics_process(.51)
	hold()
	check(wave.enemies.size() == 2 and wave._pending == 0, "Both local children appear")
	for enemy in wave.enemies:
		check(TerrainPath.horizontal_distance(enemy.global_position, parent_point) <= 3.3, "Child stays near requested position")
	var stale_damage := wave.enemies[0].damage_player
	var stale_spawn := wave.enemies[0].request_spawn
	for enemy in wave.enemies.duplicate():
		enemy.spawn_delay = 0
		enemy.take_damage(1000)
	wave._physics_process(.01)
	check(wave.phase == WavePrototype.Phase.RESULT and wave.outcome == WavePrototype.Outcome.VICTORY and wave.completed_waves == 1 and wave.kills == 3, "Final clear records victory exactly once")
	check(not stale_damage.call(10) and not stale_spawn.call(probe, 1, .1, Vector3.INF), "Ended callbacks cannot mutate result")
	# 清波扩展可暂停，恢复后只通知一次完成。
	reset()
	check(start(), "Clear extension fixture starts")
	wave._physics_process(.31)
	hold()
	var completions: Array[int] = []
	var freeze_on_clear := func(): wave.set_combat_frozen(true)
	var completed := func(number: int): completions.append(number)
	wave.wave_clearing.connect(freeze_on_clear)
	wave.wave_cleared.connect(completed)
	wave.enemies[0].spawn_delay = 0
	wave.enemies[0].take_damage(1000)
	wave._physics_process(.01)
	check(wave.phase == WavePrototype.Phase.BATTLE and wave.combat_frozen and completions.is_empty(), "Clear hook can defer rest safely")
	wave.set_combat_frozen(false)
	wave._physics_process(.01)
	check(wave.phase == WavePrototype.Phase.REST and completions == [1], "Unfreeze completes clear once")
	wave._physics_process(100)
	check(completions == [1] and wave.enemies.is_empty(), "Rest is indefinitely safe")
	wave.wave_clearing.disconnect(freeze_on_clear)
	wave.wave_cleared.disconnect(completed)
	wave.retreat()
	check(wave.outcome == WavePrototype.Outcome.RETREAT, "Retreat outcome differs from victory")
	# R 留给画面风格；隐藏 UI 下通过 T 重试。
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = wave.retry_key
	wave._unhandled_key_input(event)
	choose_initial()
	check(wave.retry_key == KEY_T and wave.phase == WavePrototype.Phase.BATTLE and wave.wave == 1 and wave.kills == 0, "T retries from result without visible UI")
	# 延迟召唤预算包含已生成者，防止持续追加绕过上限。
	wave.max_spawns_per_wave = 2
	check(not wave.queue_spawn(probe, 2) and wave.outcome == WavePrototype.Outcome.ERROR, "Cumulative spawn budget prevents unlimited reinforcements")
	# 开始回调不能递归开启同一轮；开始回调撤销后不能继续偷偷开波。
	reset()
	var repeated: Array[bool] = []
	var repeat_start := func(): repeated.append(start())
	wave.run_started.connect(repeat_start)
	check(start() and repeated == [false] and wave._pending == 1, "Repeated start from run notification is rejected")
	wave.run_started.disconnect(repeat_start)
	reset()
	var abort_start := func():
		wave._finish("abort start")
		wave.return_home()
	wave.run_started.connect(abort_start)
	check(not start() and wave.phase == WavePrototype.Phase.READY and wave.enemies.is_empty() and wave.wave == 0, "Aborted start cannot resume after returning home")
	wave.run_started.disconnect(abort_start)
	# 结果通知中立即重试时，旧结果不得发出新一轮的结束通知。
	reset()
	check(start(), "Automatic retry fixture starts")
	var serial: int = wave.get_run_state().run_id
	var did_retry: Array[bool] = [false]
	var ended: Array[String] = []
	var auto_retry := func():
		if wave.phase == WavePrototype.Phase.RESULT and not did_retry[0]:
			did_retry[0] = true
			wave.retry()
			choose_initial()
	var record_end := func(reason: String): ended.append(reason)
	wave.changed.connect(auto_retry)
	wave.run_ended.connect(record_end)
	wave.retreat()
	check(wave.phase == WavePrototype.Phase.BATTLE and wave.get_run_state().run_id == serial + 1 and ended.is_empty(), "Reentrant retry cannot be ended by stale result notification")
	wave.changed.disconnect(auto_retry)
	wave.run_ended.disconnect(record_end)
	reset()
	var invalid := entry(probe)
	invalid.start_delay = -1
	wave.waves.assign([plan([invalid])])
	check(not start() and wave.phase == WavePrototype.Phase.RESULT and wave.wave == 0, "Invalid schedule rejected before combat")
	check(FileAccess.get_sha256("res://data/world/world_terrain.tres") == protected, "No terrain source writes")
	print(JSON.stringify({"checks":checks,"failures":failures,"navigation_points":navigation_points}))
	for audio in world.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	world.queue_free()
	await frames(8)
	# 让音频混音线程释放已停的播放实例，避免无界面的测试进程提前退出。
	await create_timer(.15).timeout
	quit(0 if failures.is_empty() else 1)
