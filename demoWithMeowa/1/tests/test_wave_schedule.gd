extends SceneTree
const PLANNER := preload("res://scripts/combat/wave_schedule_planner.gd")
## 重构前固定现有波次规划行为；不装配地图、人物、AI 或界面。
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func run() -> void:
	var controller := WavePrototype.new()
	controller.max_active_enemies = 24
	controller._run_endless = true
	controller._endless_growth = 8
	controller._endless_cap = 160
	controller._endless_interval_reduction = 0.03
	controller._endless_min_interval = 0.18
	var enemy := WaveEnemyDefinition.new()
	var template := WaveDefinition.new()
	for count in [8, 18, 4, 4, 4, 2]:
		var entry := WaveSpawnEntry.new()
		entry.enemy = enemy
		entry.enemy_id = &"example"
		entry.count = count
		entry.interval = 0.5
		entry.spawn_zone_ids = PackedStringArray(["West"])
		entry.warning_seconds = 0.2
		if not template.entries.is_empty():
			var previous := template.entries[-1]
			entry.start_delay = previous.start_delay + previous.spawn_duration() + 2.0
		template.entries.append(entry)
	template.entries[1].batch_size = 18
	controller._run_waves.assign([template, template, template])
	check(controller._definition_for_wave(0) == null, "Invalid wave numbers produce no plan")
	check(controller._definition_for_wave(1) == template, "Opening waves retain their existing templates")
	var fourth := controller._definition_for_wave(4)
	check(controller._wave_total(fourth) == 48, "First endless wave uses configured count growth")
	check(fourth.entries.map(func(entry): return entry.count) == [10, 21, 5, 5, 5, 2], "Cumulative allocation preserves proportions without dropping members")
	check(fourth.entries[1].batch_size == 18, "Batch capacity still leaves room for the existing group")
	for index in fourth.entries.size():
		var source := template.entries[index]
		var planned := fourth.entries[index]
		check(planned != source and planned.enemy == source.enemy and planned.enemy_id == source.enemy_id and planned.spawn_zone_ids == source.spawn_zone_ids and planned.warning_seconds == source.warning_seconds, "Generated groups preserve source metadata without reusing mutable entries")
		check(is_equal_approx(planned.interval, 0.485), "Configured interval reduction applies once")
		if index > 0:
			var previous := template.entries[index - 1]
			var gap := source.start_delay - previous.start_delay - previous.spawn_duration()
			var previous_plan := fourth.entries[index - 1]
			check(is_equal_approx(planned.start_delay - previous_plan.start_delay - previous_plan.spawn_duration(), gap), "Group lulls survive larger batches and reduced intervals")
	var late := controller._definition_for_wave(1000000000)
	check(controller._wave_total(late) == 160 and controller._run_waves.size() == 3, "Huge wave numbers remain capped without accumulating templates")
	check(template.entries.map(func(entry): return entry.count) == [8, 18, 4, 4, 4, 2], "Planning leaves original counts unchanged")
	template.entries[0].interval = 0.01
	check(is_equal_approx(controller._definition_for_wave(4).entries[0].interval, 0.01), "The interval floor never slows an already faster source")
	template.entries[1].start_delay = 0.0
	check(controller._definition_for_wave(4).entries[1].start_delay == 0.0, "Deliberately overlapping groups retain their start time")
	controller._run_endless = false
	check(controller._definition_for_wave(4) == null, "Finite schedules do not synthesize extra waves")
	controller.free()
	check(PLANNER.endless_total(40, 3, 4, 8, 160) == 48 and PLANNER.endless_total(40, 3, 1000000000, 8, 160) == 160, "Pure planner computes bounded growth without a controller")
	var independent := PLANNER.extend_wave(template, 48, 0.97, 0.18, func(_entry: WaveSpawnEntry): return 20)
	check(PLANNER.total(independent) == 48 and independent.entries[1].batch_size == 20, "Pure planner uses its explicitly supplied batch capacity")
	check(independent.entries[0].interval == 0.01 and independent.entries[1].start_delay == 0.0, "Pure planner preserves fast and overlapping source groups")
	independent.entries[0].spawn_zone_ids[0] = "East"
	check(template.entries[0].spawn_zone_ids[0] == "West", "Editing planned spawn zones leaves the source template unchanged")
	await process_frame
	print(JSON.stringify({"suite":"wave_schedule", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
