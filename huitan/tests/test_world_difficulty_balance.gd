extends SceneTree

const WORLD := "res://data/combat/scenes/world/"
const PLANNER := preload("res://scripts/combat/wave_schedule_planner.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", message)

func _initialize() -> void:
	run.call_deferred()

func plan(definition: WaveDefinition, profile: SceneCombatConfiguration, number: int, usage: Dictionary) -> Dictionary:
	var pool: Array[WaveEnemyDefinition] = []
	for enemy in profile.enemy_catalog.enemies:
		if enemy.horde_weight > 0.0: pool.append(enemy)
	var counts := {}
	var population := profile.population_rules
	for entry in definition.entries:
		if not entry.mixed_horde:
			counts[entry.enemy.enemy_id] = counts.get(entry.enemy.enemy_id, 0) + entry.count
			continue
		var remaining := entry.count
		while remaining > 0:
			var size := mini(entry.batch_size, remaining)
			var members := WaveHordePlanner.plan(pool, size, population.active_limit(number), population.max_population_cost, population.role_limits, usage)
			check(members.size() == size, "Every mixed batch fits its real role, species and population budgets")
			for enemy in members: counts[enemy.enemy_id] = counts.get(enemy.enemy_id, 0) + 1
			remaining -= size
	return counts

func run() -> void:
	var profile: SceneCombatConfiguration = load(WORLD + "configuration.tres")
	check(profile.validation_error().is_empty(), "The complete current World configuration remains valid")
	var sword := profile.sword_rules
	for enemy in profile.enemy_catalog.enemies:
		if enemy.enemy_id == &"mini_slime": continue
		var hits := ceili(enemy.health / sword.damage)
		check(hits >= 3 and hits <= 6, "%s starts within three to six unmodified sword hits" % enemy.enemy_id)
	var motion := profile.ricochet_rules
	check(motion.maximum_launch_speed < 12.0, "Full-charge launch speed is moderately below the previous twelve metres per second")
	check(absf(motion.coast_seconds(motion.maximum_launch_speed) - 5.0) <= 0.25, "Unmodified full-charge coasting lasts about five seconds before collision losses")
	check(motion.coast_seconds(motion.minimum_launch_speed) < motion.coast_seconds(motion.maximum_launch_speed), "Short charging retains its shorter commitment")
	var modifiers := RunCombatModifiers.new()
	modifiers.apply_buff(load(WORLD + "growth/ricochet/flight_duration.tres"))
	var improved_decay := modifiers.ricochet_value(GrowthBuffDefinition.Attribute.RICOCHET_DURATION, motion.flight_deceleration)
	check((motion.maximum_launch_speed - motion.minimum_bounce_speed) / improved_decay > 6.0, "Momentum growth still extends the new starting endurance")
	var survival := profile.growth_rules
	check(is_equal_approx(survival.orbit_damage_reduction, 0.3) and is_equal_approx(survival.sword_heal_fraction, 0.015) and is_equal_approx(survival.sword_heal_cap, 0.05), "Existing orbit protection and sword recovery remain unchanged")
	var health := profile.health_growth_rules
	check(health.multiplier(3) == 1.0, "The first three waves give growth room before enemy health rises")
	check(health.multiplier(4) < 2.0 and health.multiplier(5) >= 2.0 and health.multiplier(6) >= 3.0, "Pressure starts gently in wave four and catches up in the reported fifth and sixth waves")
	check(health.multiplier(10) > health.multiplier(5), "Midgame health grows after the opening window")
	check(health.multiplier(30) > 50.0, "Late enemies overcome the previous tenfold-only health ceiling")
	check(health.multiplier(15) - health.multiplier(10) > health.multiplier(10) - health.multiplier(5), "Health increments accelerate before reaching the safety cap")
	check(is_finite(health.multiplier(1000000000)) and health.multiplier(1000000000) == health.sustained_maximum_multiplier, "Extreme endless wave numbers remain finite at the sustained-growth cap")
	var catalog := {}
	for enemy in profile.enemy_catalog.enemies: catalog[enemy.enemy_id] = enemy
	for pair in [[&"slime", 6.0], [&"leaf_charger", 3.0], [&"lantern_spitter", 3.0], [&"pot_brood", 1.0]]:
		check(is_equal_approx(catalog[pair[0]].horde_weight, pair[1]), "Main horde weights follow the agreed six to three to three to one mix")
	check(catalog[&"bell_frog"].horde_weight == 0.0 and catalog[&"bell_frog"].max_alive <= 4, "Frogs are scheduled sparingly outside the compulsory mixed-batch coverage")
	check(catalog[&"mini_slime"].horde_weight == 0.0, "Children still come only from their original split mechanism")
	var usage := {}
	var state := RunGrowthState.new()
	state.rules = profile.experience_rules
	var levels := []
	for index in 3:
		var definition := profile.waves[index]
		check(PLANNER.total(definition) == [18, 28, 40][index], "Opening primary populations retain their established totals")
		var counts := plan(definition, profile, index + 1, usage)
		var experience := 0
		for id in counts:
			var reward: int = catalog[id].experience_reward
			if id == &"pot_brood": reward += 2 * int(catalog[&"mini_slime"].experience_reward)
			experience += counts[id] * reward
		state.add_experience(experience)
		levels.append(state.level)
		if index == 2:
			check(counts[&"slime"] == 18 and counts[&"leaf_charger"] == 9 and counts[&"lantern_spitter"] == 9 and counts[&"pot_brood"] == 3 and counts[&"bell_frog"] == 1, "Actual scheduled third-wave composition follows the requested mix with one supporting frog")
	check(levels[0] < 5 and levels[1] >= 5 and levels[2] < 10, "Slower opening XP places the first epic in wave two and avoids a second epic in the first three clears")
	for level in [1, 5, 15, 40]:
		check(profile.experience_rules.required_for(level) >= 2 * (10 + (level - 1) * 5), "World XP costs slow the previous curve without changing rewards or attraction")
	var population := profile.population_rules
	check(population.active_limit(1) == 24 and population.max_active == 80 and profile.max_active_enemies == 80, "World preserves the opening density and caps both the population curve and fallback at eighty enemies")
	check(population.surround_start_wave == 2, "Multi-direction pressure starts after the teaching wave")
	check(PLANNER.endless_total(40, 3, 4, population.enemies_per_wave_increment, population.max_wave_enemies) <= 64, "The fourth wave avoids the previous abrupt forty-to-seventy-two jump")
	for number in [4, 10, 20, 30, 1000000000]:
		var count := PLANNER.endless_total(40, 3, number, population.enemies_per_wave_increment, population.max_wave_enemies)
		var definition := PLANNER.extend_wave(profile.waves[-1], count, maxf(0.25, 1.0 - (number - 3) * population.interval_reduction_per_wave), population.min_spawn_interval,
			func(entry: WaveSpawnEntry): return mini(population.active_limit(number), maxi(entry.batch_size, floori(population.active_limit(number) * 0.5))))
		var counts := plan(definition, profile, number, {})
		check(counts.values().reduce(func(sum, value): return sum + value, 0) == count, "Late generation keeps every primary spawn registered")
		check(counts.get(&"bell_frog", 0) <= ceili(count * 0.05), "Supporting frogs remain a small fraction in extended waves")
	print("World difficulty balance: %d checks, %d failures; opening clear levels %s" % [checks, failures, levels])
	quit(1 if failures else 0)
