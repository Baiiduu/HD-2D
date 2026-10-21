extends SceneTree

var checks := 0
var failures := 0
var events: Array[CombatDamageEvent] = []
var active := true

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	create_timer(35.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func target(chance: float, rng: RandomNumberGenerator) -> WaveEnemy:
	var enemy := WaveEnemy.new()
	enemy.configure_wave({"player":null, "navigation":null, "attack_root":null,
		"damage_player":Callable(), "request_spawn":Callable(), "combat_active":func(): return active,
		"critical_chance":chance, "critical_multiplier":2.0, "critical_random":rng}, WaveEnemyDefinition.new(), 0.0)
	enemy.health = 100000.0
	enemy.max_health = enemy.health
	root.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.damaged.connect(func(event): events.append(event))
	return enemy

func run() -> void:
	var probe := WaveEnemy.new()
	check("critical_chance" in probe, "Enemy damage can receive the scene's fixed critical rules")
	probe.free()
	if failures: quit(1); return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7123
	var mob := target(1.0, rng)
	var context := {"source": &"A02", "style": &"lightning"}
	mob.take_damage(10.0, context)
	var hit := events[-1]
	check(hit.amount == 20.0 and hit.requested_amount == 20.0, "A real critical hit deals exactly twice the resolved attack damage")
	check(hit.get("critical") == true and hit.get("critical_multiplier") == 2.0 and hit.style == &"critical", "Critical result and visual style share the same settled event")
	check(context.style == &"lightning" and not context.has("critical"), "Resolution never mutates a reusable weapon context")
	mob.set("critical_chance", 0.0)
	mob.take_damage(10.0, context)
	hit = events[-1]
	check(hit.amount == 10.0 and not hit.get("critical") and hit.style == &"lightning", "Noncritical hits retain their original damage and lightning style")
	mob.set("critical_chance", 1.0)
	for source: StringName in [&"basic_sword", &"flight_sword", &"A01", &"A02", &"A03", &"mirror_mark", &"ricochet_storm"]:
		mob.take_damage(7.0, {"source":source})
		check(events[-1].amount == 14.0 and events[-1].source == source and events[-1].style == &"critical", "All player attacks use the same resolver: " + source)
	mob.take_damage(30.0 * 1.4, {"source":&"flight_sword"})
	check(is_equal_approx(events[-1].amount, 84.0), "Critical multiplication follows existing damage and speed bonuses once")
	mob.take_damage(8.0)
	check(events[-1].amount == 8.0 and not events[-1].get("critical"), "Administrative damage without a player source remains deterministic")
	mob.set("critical_chance", 0.1)
	var count := events.size()
	var state := rng.state
	active = false
	mob.take_damage(10.0, context)
	active = true
	mob.spawn_delay = 1.0
	mob.take_damage(10.0, context)
	mob.spawn_delay = 0.0
	for invalid in [0.0, -1.0, NAN, INF]: mob.take_damage(invalid, context)
	check(events.size() == count and rng.state == state, "Freeze, spawn protection and invalid hits consume neither health nor a critical roll")
	mob.free()
	var expected := RandomNumberGenerator.new()
	rng.seed = 37129
	expected.seed = 37129
	mob = target(0.1, rng)
	var criticals := 0
	for index in 1000:
		var critical := expected.randf() < 0.1
		mob.take_damage(1.0, {"source":&"basic_sword"})
		hit = events[-1]
		check(hit.get("critical") == critical and hit.requested_amount == (2.0 if critical else 1.0), "Fixed 10 percent resolution follows its independent random stream")
		if hit.get("critical"): criticals += 1
	check(criticals > 0 and criticals < 1000, "A seeded run includes both ordinary and critical hits")
	mob.free()
	mob = target(1.0, rng)
	mob.health_loss_disabled = true
	var health := mob.health
	mob.take_damage(10.0, {"source":&"ricochet_storm", "style":&"lightning"})
	hit = events[-1]
	check(mob.health == health and hit.amount == 0.0 and hit.display_amount() == 20.0 and hit.get("critical"), "Horde simulation displays the critical request without health loss or recovery damage")
	mob.health_loss_disabled = false
	mob.health = 5.0
	var batch := CombatDamageEvent.ScoreBatch.new()
	var snapshot := CombatAttackSnapshot.new()
	mob.take_damage(10.0, {"source":&"flight_sword", "flight_id":4, "score_batch":batch, "attack_snapshot":snapshot})
	hit = events[-1]
	check(hit.amount == 5.0 and hit.requested_amount == 20.0 and hit.lethal and hit.get("critical"), "Overkill still reports actual health loss separately from critical damage")
	check(hit.score_batch == batch and hit.attack_snapshot == snapshot and hit.flight_id == 4, "Scoring and shared sword recovery keep the original attack identity")
	count = events.size()
	mob.take_damage(10.0, context)
	check(events.size() == count, "A dead target cannot emit another critical damage event")
	await process_frame
	var world := load("res://data/combat/scenes/world/configuration.tres") as SceneCombatConfiguration
	var city := load("res://data/combat/scenes/city/configuration.tres") as SceneCombatConfiguration
	check(world.get("critical_chance") == 0.1 and world.get("critical_multiplier") == 2.0, "World enables fixed 10 percent critical chance and double damage")
	check(city.get("critical_chance") == 0.0, "The independent City configuration keeps its previous rules")
	var numbers := DamageNumbers.new()
	numbers.number_styles = world.number_styles
	var normal := numbers.style_for(&"normal")
	var critical := numbers.style_for(&"critical")
	check(critical != normal and critical.number_font == normal.number_font, "Critical digits reuse the approved pixel font with a distinct style")
	check(critical.number_font_size > normal.number_font_size and critical.number_color != normal.number_color and critical.format_amount(20.0) == "20!", "Critical digits are larger, differently colored and marked with an exclamation")
	numbers.free()
	await formal_checks(world)
	print("Critical damage: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func formal_checks(profile: SceneCombatConfiguration) -> void:
	var scene: Node3D = load("res://scenes/world/world.tscn").instantiate()
	var isolated := profile.duplicate() as SceneCombatConfiguration
	isolated.population_rules = null
	isolated.spawn_shadow_settings = null
	isolated.sword_rules = profile.sword_rules.duplicate()
	isolated.sword_rules.audio_enabled = false
	scene.get_node("BattleConfiguration").configuration = isolated
	scene.get_node("WorldMainMenu").show_on_world_start = false
	scene.get_node("WorldEntry").preview_on_direct_run = false
	scene.get_node("LoadoutUI").save_enabled = false
	scene.get_node("GameSettingsUI").save_graphics_settings = false
	scene.get_node("MapEffects/BGM").music_enabled = false
	scene.get_node("MapEffects/Weather").rain_audio_enabled = false
	scene.get_node("MapEffects/Weather").wind_audio_enabled = false
	scene.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	scene.get_node("WavePresentation").enabled = false
	scene.get_node("WavePrototype/SkillDraft").enabled = false
	scene.get_node("WavePrototype/RunGrowth").enabled = false
	load("res://tests/fixtures/combat_scene_fixture.gd").clear_placed_obstacles(scene)
	root.add_child(scene)
	for frame in 12: await physics_frame
	var session := scene.get_node("WavePrototype") as WavePrototype
	var player := session.player
	player.set_physics_process(false)
	player.sword.set_physics_process(false)
	session.set_physics_process(false)
	player.global_position = session._path.ground_position(session.global_position) + Vector3.UP * 0.03
	check(session.critical_chance == 0.1 and session.critical_multiplier == 2.0, "Formal scene binds its fixed critical values before starting")
	check(session.start_run(), "The real scene starts with critical rules enabled")
	check(session._spawn_enemy(), "The real spawn path configures an enemy for critical damage")
	if session.enemies.is_empty():
		scene.free()
		await process_frame
		return
	var mob := session.enemies[-1]
	check(mob.critical_chance == 0.1 and mob.critical_random == session._critical_random, "Spawned enemies share the scene's dedicated critical stream")
	mob.set_physics_process(false)
	mob.health = 1000.0
	mob.global_position = player.global_position + Vector3.RIGHT * 0.9
	mob.commit_spatial_state()
	var actual: Array[CombatDamageEvent] = []
	mob.damaged.connect(func(event): actual.append(event))
	var preview := RandomNumberGenerator.new()
	for seed in 100:
		preview.seed = seed
		if preview.randf() < 0.1:
			session._critical_random.seed = seed
			break
	var spawn_state := session._random.state
	var sword := player.sword
	var base: float = sword.get_combat_stats().damage
	sword._begin(Vector3.RIGHT, false)
	sword._simulate(player.global_position, player.global_position, sword._settings.duration() + 0.001, false, Vector3.RIGHT)
	sword._drain_hits()
	check(actual.size() == 1 and actual[0].critical and is_equal_approx(actual[0].amount, base * 2.0), "A real sword contact deals critical damage through the configured enemy")
	check(session._random.state == spawn_state, "Critical damage does not consume the wave spawning random stream")
	for definition in profile.growth_definitions: session.combat_modifiers.apply_buff(definition)
	check(session.critical_chance == 0.1 and mob.critical_chance == 0.1, "Applying current normal and epic growth cannot increase critical chance")
	var page: Variant = load("res://scripts/ui/character_stats_page.gd").new()
	root.add_child(page)
	page.configure(scene)
	check("暴击率　10%　　暴击伤害　×2.00" in page._values.text, "Read-only character stats show the actual fixed critical values")
	page.free()
	session.retreat()
	scene.free()
	for frame in 2: await process_frame
