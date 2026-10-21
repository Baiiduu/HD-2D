extends SceneTree

const WORLD := "res://data/combat/scenes/world/"
const A := GrowthBuffDefinition.Attribute
var checks := 0
var failures := 0
var profile: SceneCombatConfiguration
var definitions := {}

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", message)

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func apply(mods: RunCombatModifiers, id: StringName, count: int) -> void:
	for index in count: check(mods.apply_buff(definitions[id]), "Real growth remains available: %s" % id)

func build(rank: int, rules: RunGrowthRules) -> RunCombatModifiers:
	var result := RunCombatModifiers.new()
	result.growth_rules = rules
	for id in [&"P01", &"E04", &"E02"]: apply(result, id, rank)
	for id in [&"R01", &"R02"]: apply(result, id, 4)
	return result

func run() -> void:
	profile = load(WORLD + "configuration.tres")
	check(profile != null and profile.validation_error().is_empty(), "World profile validates before the numerical comparison")
	if not profile:
		quit(1)
		return
	for definition in profile.growth_definitions: definitions[definition.id] = definition
	var sword := PlayerSword.new()
	sword.rules = profile.sword_rules
	var storm := RicochetStorm.new()
	storm.damage = profile.storm_damage
	for definition in profile.skill_definitions:
		if definition.id == &"ricochet_storm": storm.skill_definition = definition
	var first := build(1, profile.growth_rules)
	var invalid := profile.growth_rules.duplicate() as RunGrowthRules
	for value in [0.0, 1.1, INF, NAN]:
		invalid.damage_growth_exponent = value
		check(not invalid.validation_error().is_empty(), "Damage growth exponent rejects invalid ranges and non-finite values")
	check(is_equal_approx(first.multiplier(A.HEAVY_STRIKE), 3.0) and is_equal_approx(first.speed_damage_multiplier(18.0, true), 2.0), "First-card heavy and high-speed transformations keep their threefold and twofold effects")
	check(is_equal_approx(first.interval_multiplier(), 2.0), "The original heavy attack-frequency cost stays in force")
	var five := build(5, profile.growth_rules)
	var ten := build(10, profile.growth_rules)
	var five_hit: float = sword.get_stats(true, five).damage * five.speed_damage_multiplier(18.0, true)
	var ten_hit: float = sword.get_stats(true, ten).damage * ten.speed_damage_multiplier(18.0, true)
	check(five_hit > 350.0 and five_hit < 450.0, "Three rank-five damage branches retain power while avoiding the previous 1638 damage")
	check(ten_hit > 900.0 and ten_hit < 1200.0 and ten_hit > five_hit, "Three rank-ten damage branches keep growing without the previous 8832 damage")
	var preview := ten.preview_after(definitions[&"E04"])
	check(preview.damage_multiplier() > ten.damage_multiplier() and preview.interval_multiplier() == ten.interval_multiplier(), "Further heavy upgrades remain useful without repeatedly changing attack frequency")
	preview = ten.preview_after(definitions[&"E02"])
	check(preview.speed_damage_multiplier(18.0, true) > ten.speed_damage_multiplier(18.0, true), "Further momentum damage keeps a real positive return")
	check(ten.speed_damage_multiplier(18.0, false) == 1.0 and ten.speed_damage_multiplier(4.0, true) < ten.speed_damage_multiplier(18.0, true), "Damage softening retains the flight-only speed curve")
	var buffs := RunBuffs.new()
	check(is_equal_approx(buffs._value(A.SPEED_DAMAGE, ten), ten.speed_damage_multiplier(16.0, true) - 1.0), "Card strength readout uses the effective damage bonus rather than the unsoftened accumulator")
	buffs.free()
	var decay := ten.ricochet_value(A.RICOCHET_DURATION, profile.ricochet_rules.flight_deceleration)
	var speed := ten.ricochet_value(A.RICOCHET_SPEED, profile.ricochet_rules.maximum_launch_speed)
	check(is_equal_approx((speed - profile.ricochet_rules.minimum_bounce_speed) / decay, 20.0), "The rank-four speed and endurance build still coasts for twenty seconds")
	check(profile.storm_damage == 20.0, "World keeps the agreed twenty base storm damage")
	var top := build(15, profile.growth_rules)
	apply(top, &"E03", 5)
	var top_hit: float = sword.get_stats(true, top).damage * top.speed_damage_multiplier(18.0, true)
	var strikes := top.strike_count(profile.growth_rules.speed_tier(18.0), true)
	var swing: float = top_hit * (1.0 + (strikes - 1) * profile.growth_rules.additional_strike_damage_ratio)
	var thunder: float = storm.get_attack_stats(4, top).damage * top.speed_damage_multiplier(18.0, true)
	var health := profile.health_growth_rules
	var slime_health := profile.default_enemy.health
	check(health.multiplier(3) == 1.0 and is_equal_approx(health.multiplier(5), 2.4) and is_equal_approx(health.multiplier(6), 3.6), "Opening difficulty and the agreed fifth/sixth-wave pressure are preserved")
	check(health.multiplier(18) == health.multiplier(21), "The first late waves leave a health plateau for builds to pay off")
	check(health.multiplier(25) > health.multiplier(21) and health.multiplier(40) > health.multiplier(25), "Enemy health resumes gradual growth after the payoff window")
	check(swing >= slime_health * health.multiplier(25) and thunder >= slime_health * health.multiplier(25), "A high-end rank-fifteen build can clear common enemies with one complete swing or storm hit in its payoff window")
	check(swing < 60.0 * health.multiplier(25) and thunder < 60.0 * health.multiplier(25), "The same payoff does not erase every heavier enemy in one attack")
	check(swing < slime_health * health.multiplier(40) and thunder < slime_health * health.multiplier(40), "Later waves restore pressure against the same completed build")
	check(is_finite(health.multiplier(1000000000)) and health.multiplier(1000000000) <= 1000.0, "Sustained endless health remains finite and bounded for extreme wave numbers")
	var legacy := build(10, RunGrowthRules.new())
	var legacy_hit: float = sword.get_stats(true, legacy).damage * legacy.speed_damage_multiplier(18.0, true)
	check(is_equal_approx(legacy_hit, 8832.0), "Unopted legacy growth rules keep their previous damage calculation")
	print("Endgame balance: %d checks, %d failures; rank5=%.2f rank10=%.2f top_swing=%.2f top_storm=%.2f common_hp25=%.2f common_hp40=%.2f" % [checks, failures, five_hit, ten_hit, swing, thunder, slime_health * health.multiplier(25), slime_health * health.multiplier(40)])
	sword.free()
	storm.free()
	quit(1 if failures else 0)
