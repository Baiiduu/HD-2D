extends "res://tests/test_enemy_quartet.gd"

## Reuses the actual quartet split case and growth integration's real UI flow.
## Observes real damaged/remove/spawn callbacks; no copy of pair/move formulas.
const BatchIndex = preload("res://scripts/combat/crowd_batch_enemy_spatial_index.gd")
var batch_index := BatchIndex.new()
var growth: RunGrowth
var lethal_probes: Array[Dictionary] = []
var validated_lethal_plans := 0

func check(value: bool, message: String) -> void:
	super.check(value, message)
	for probe in lethal_probes:
		super.check(not batch_index._entries.has(probe.enemy), "Real lethal damage removes the actor before the next public checkpoint")
		var released := batch_index._entries.is_empty() and batch_index._forces.is_empty() and batch_index._plan_frame == -1
		super.check(released or batch_index._fallback_frame == int(probe.frame), "Real death invalidates an active same-step plan or releases the final plan")
		validated_lethal_plans += 1
	lethal_probes.clear()

func observe_spawn(enemy: WaveEnemy) -> void:
	# damaged is emitted before WaveEnemy's actual lethal remove. Arming a
	# read-only query here ensures that the real death exercises a live plan.
	enemy.damaged.connect(func(_event):
		if enemy.health > 0.0 or enemy.dead: return
		batch_index.update(enemy) # commit fixture's direct spawn_delay assignment
		batch_index.separation(enemy, enemy.get_crowd_spacing())
		var frame := Engine.get_physics_frames()
		if batch_index._plan_frame == frame and batch_index._fallback_frame != frame:
			lethal_probes.append({"enemy": enemy, "frame": frame})
	)

func confirm_initial() -> void:
	var skills := wave.get_node("RunSkillManager") as RunSkillManager
	if wave.skill_draft.initial_choice.is_open:
		wave.skill_draft.initial_choice.reveal_now()
		check(wave.skill_draft.initial_choice.select_option(wave.skill_draft.initial_choice._options[0].id), "Actual initial UI accepts a valid skill")
		wave.skill_draft.initial_choice.confirm_selection()
	for component: Node in skills._components.values(): component.process_mode = Node.PROCESS_MODE_DISABLED

func finish_growth_choices() -> void:
	var attempts := 0
	while growth.choice_ui.is_open and attempts < 12:
		growth.choice_ui.reveal_now()
		check(growth.choice_ui.select_option(growth.choice_options[0].id), "Pending growth requires an actual valid UI selection")
		growth.choice_ui.confirm_selection()
		attempts += 1

func growth_and_summon_checks() -> void:
	growth.enabled = true
	wave.retry()
	confirm_initial()
	check(wave.phase == WavePrototype.Phase.BATTLE and growth.active and growth.state.level == 1, "Retry enters a fresh real growth run")
	check(batch_index._entries.is_empty() and batch_index._forces.is_empty() and batch_index._plan_frame == -1, "Retry releases prior actor and force state")
	wave._spawn_queue.clear()
	player.global_position = ground(origin)
	var data: WaveEnemyDefinition = load("res://data/enemies/wave_slime.tres")
	check(wave._spawn_enemy(data, ground(origin + Vector3(1, 0, 0))), "Actual wave interface spawns the living freeze subject")
	if wave.enemies.is_empty(): return
	var enemy := wave.enemies[-1]
	enemy.set_physics_process(false)
	enemy.spawn_delay = 0.0
	batch_index.update(enemy)
	await physics_frame
	batch_index.separation(enemy, enemy.get_crowd_spacing())
	var old_plan := batch_index._plan_frame
	var position := enemy.global_position
	var clock := wave._wave_clock
	growth.drop_experience(player.global_position, 10)
	growth.collect_all()
	check(growth.choice_ui.is_open and wave.combat_frozen, "Actual experience opens upgrade UI and freezes combat")
	enemy._physics_process(0.5)
	wave._physics_process(0.5)
	await settle(3)
	check(enemy.global_position == position and wave._wave_clock == clock and batch_index._plan_frame == old_plan, "Frozen actors and clocks do not build or consume a new crowd plan")
	check(not wave._spawn_enemy(data), "Actual spawn remains rejected during upgrade freeze")
	finish_growth_choices()
	check(not wave.combat_frozen, "Actual upgrade confirmation resumes combat")
	await physics_frame
	batch_index.separation(enemy, enemy.get_crowd_spacing())
	check(batch_index._plan_frame == Engine.get_physics_frames() and batch_index._plan_frame > old_plan, "Resume builds this physics step's force instead of the pre-freeze plan")
	var stale_request := enemy.request_spawn
	var alive := wave.enemies.size()
	check(enemy.request_spawn.call(data, 1, 0.1, ground(origin - Vector3(1, 0, 0))), "Real context summon callback registers a pending actor")
	wave._physics_process(0.2)
	check(wave.enemies.size() == alive + 1 and wave._pending == 0, "Actual delayed summon creates its full actor")
	check(batch_index._fallback_frame == Engine.get_physics_frames(), "Same-step real summon invalidates the common crowd plan")
	for actor in wave.enemies:
		actor.set_physics_process(false)
		check(batch_index._entries.has(actor), "Every summoned actor is registered in the live combat index")
	for actor in wave.enemies.duplicate():
		actor.spawn_delay = 0.0
		batch_index.update(actor)
		actor.take_damage(9999.0)
	wave._spawn_queue.clear()
	wave._physics_process(0.01)
	finish_growth_choices()
	wave._physics_process(0.01)
	check(wave.phase == WavePrototype.Phase.REST and wave.enemies.is_empty(), "Real lethal cleanup and growth settle into safe wave rest")
	check(batch_index._entries.is_empty() and batch_index._forces.is_empty() and batch_index._plan_frame == -1, "Safe rest releases the final ordinary force plan")
	check(wave.start_next_wave(), "Explicit next wave remains usable with the same index object")
	wave._finish("batch lifecycle retry", WavePrototype.Outcome.RETREAT)
	wave.retry()
	check(not stale_request.call(data, 1, 0.0, Vector3.INF), "A stale summon callback cannot populate a retried index")
	confirm_initial()
	check(growth.state.level == 1 and growth.state.total_experience == 0 and batch_index._entries.is_empty() and batch_index._forces.is_empty(), "Retry resets growth, live slots and ordinary plan")
	wave._finish("batch lifecycle done")

func run() -> void:
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	wave = world.get_node("WavePrototype")
	wave.native_chase_enabled = false
	wave.batch_crowd_enabled = true
	batch_index.batch_enabled = true
	batch_index.diagnostics_enabled = true
	wave._spatial_index = batch_index
	index = batch_index
	growth = wave.get_node("RunGrowth")
	growth.enabled = false
	wave.skill_draft.initial_cards_per_draw = 100
	wave.enemy_spawned.connect(observe_spawn)
	root.add_child(world)
	current_scene = world
	await settle(12)
	player = wave.player
	player.set_physics_process(false)
	wave.set_physics_process(false)
	growth.set_physics_process(false)
	growth.choice_ui.open_duration = 0.0
	growth.choice_ui.hover_duration = 0.0
	growth.cards_per_draw = 100
	player.global_position = wave._path.ground_position(wave.global_position) + Vector3.UP * 0.03
	check(wave.start_run(), "Actual formal world starts the focused lifecycle fixture")
	confirm_initial()
	wave._spawn_queue.clear()
	origin = choose_origin()
	await split_checks() # Existing real pot death/children/freeze/rest/next-wave case.
	check(validated_lethal_plans > 0, "Existing quartet split case exercised real lethal plan invalidation")
	check(batch_index._entries.is_empty() and batch_index._forces.is_empty(), "Quartet finish releases every live slot and crowd force")
	await growth_and_summon_checks()
	(world.get_node("MapEffects/GameAudio") as GameAudio).stop_all()
	world.queue_free()
	await settle(4)
	check(get_first_node_in_group(&"gameplay_input_blockers") == null, "World cleanup leaves no growth input blocker")
	print("Batch crowd lifecycle: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
