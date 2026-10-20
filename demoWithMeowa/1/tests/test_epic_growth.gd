extends SceneTree

const Rules = preload("res://scripts/growth/run_growth_rules.gd")
const Survival = preload("res://scripts/growth/run_survival.gd")
const Snapshot = preload("res://scripts/combat/combat_attack_snapshot.gd")
const A = GrowthBuffEffect.Attribute
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func option(id: StringName, epic := false, owned := 0) -> GrowthChoiceOption:
	var value := GrowthChoiceOption.new()
	value.id = id
	value.epic = epic
	value.growth_level = owned
	return value

func _initialize() -> void:
	var rules := Rules.new()
	var ordinary := option(&"ordinary")
	var unlock := option(&"unlock", true)
	var upgrade := option(&"upgrade", true, 1)
	var pool: Array[GrowthChoiceOption] = [ordinary, unlock, upgrade]
	check(rules.candidates(pool, 4) == [ordinary, upgrade], "Owned epics upgrade in ordinary rounds")
	check(rules.candidates(pool, 5) == [unlock], "Milestones prefer new epic mechanics")
	check(rules.candidates([ordinary, upgrade], 10) == [upgrade], "Exhausted unlocks fall back to epic upgrades")
	check(rules.candidates([ordinary], 15) == [ordinary], "Empty epic pool never blocks progression")
	var state := RunGrowthState.new()
	state.level = 7
	state.pending_choices = 4
	check(state.next_choice_level() == 4, "XP burst starts at first pending level")
	state.complete_choice()
	check(rules.is_epic_level(state.next_choice_level()), "XP burst includes level five exactly once")
	var mods := RunCombatModifiers.new()
	mods.growth_rules = rules
	var heavy := GrowthBuffDefinition.new()
	heavy.id = &"heavy"
	heavy.attribute = A.HEAVY_STRIKE
	heavy.bonus_per_level = 2.0
	mods.apply_buff(heavy)
	check(is_equal_approx(mods.damage_multiplier(), 3.0) and is_equal_approx(mods.interval_multiplier(), 2.0), "Heavy strike trades cadence for real damage")
	mods.apply_buff(heavy)
	check(is_equal_approx(mods.damage_multiplier(), 5.0) and is_equal_approx(mods.interval_multiplier(), 2.0), "Heavy upgrade never repeatedly halves frequency")
	var speed := heavy.duplicate() as GrowthBuffDefinition
	speed.id = &"speed"
	speed.attribute = A.SPEED_DAMAGE
	speed.bonus_per_level = 1.0
	mods.apply_buff(speed)
	check(mods.speed_damage_multiplier(12.0, true) > mods.speed_damage_multiplier(4.0, true), "Remaining energy controls damage")
	check(mods.speed_damage_multiplier(12.0, false) == 1.0, "Walking receives no speed damage")
	var thousand := speed.duplicate() as GrowthBuffDefinition
	thousand.id = &"thousand"
	thousand.attribute = A.MULTISTRIKE
	mods.apply_buff(thousand)
	check(mods.strike_count(0, true) == 2 and mods.strike_count(2, true) == 4 and mods.strike_count(2, false) == 1, "Thousand hands only repeats flight sword")
	var survival := Survival.new()
	survival.rules = rules
	check(is_equal_approx(survival.incoming_damage(100, true), 70) and survival.incoming_damage(100, false) == 100, "Orbit damage reduction keeps ordinary damage real")
	var hit := CombatDamageEvent.new()
	hit.source = &"flight_sword"
	hit.amount = 10
	hit.attack_snapshot = Snapshot.new()
	check(is_equal_approx(survival.recovery(hit, mods, 100, 50), 1.5), "First real sword hit grants baseline recovery")
	check(survival.recovery(hit, mods, 100, 50) == 0, "A repeated slash or crowd hit cannot duplicate root healing")
	hit.simulated = true
	hit.attack_snapshot = Snapshot.new()
	check(survival.recovery(hit, mods, 100, 50) == 0, "Simulation grants no healing")
	hit.simulated = false
	for i in 8:
		hit.attack_snapshot = Snapshot.new()
		survival.recovery(hit, mods, 100, 50)
	check(is_equal_approx(survival.basic_used(), 5.0), "Baseline recovery has its own sliding second cap")
	survival.advance(1.01)
	check(survival.basic_used() == 0, "Budget expires with combat time")
	var vamp := speed.duplicate() as GrowthBuffDefinition
	vamp.id = &"vamp"
	vamp.attribute = A.LIFESTEAL
	vamp.bonus_per_level = 0.03
	var cap := GrowthBuffEffect.new()
	cap.attribute = A.LIFESTEAL_CAP
	cap.bonus_per_level = 0.05
	vamp.extra_effects = [cap]
	mods.apply_buff(vamp)
	hit.source = &"A02"
	hit.amount = 1000
	check(is_equal_approx(survival.recovery(hit, mods, 100, 50), 5.0), "Omnivamp uses actual damage with a separate cap")
	survival.reset()
	hit.amount = 10
	check(is_equal_approx(survival.recovery(hit, mods, 100, 0.1), 0.1), "Only actual missing health consumes the healing budget")
	check(is_equal_approx(survival.vamp_used(), 0.1), "Full health cannot spend recovery budget")
	check(rules.speed_tier(8.1, 0) == 0 and rules.speed_tier(8.5, 0) == 1 and rules.speed_tier(7.9, 1) == 1, "Tier hysteresis prevents threshold flicker")
	mods.reset()
	var area: GrowthBuffDefinition = load("res://data/combat/scenes/world/growth/epic/global_range.tres")
	var attacks: Array[Node3D] = [LightPierceAutoAttack.new(), PrismRicochetAutoAttack.new(), MirrorMarkAutoAttack.new(), RicochetStorm.new(), FanAutoAttack.new()]
	var before: Array[Dictionary] = []
	for attack in attacks: before.append(attack.get_attack_stats(1, mods))
	mods.apply_buff(area)
	for index in 3:
		var after: Dictionary = attacks[index].get_attack_stats(1, mods)
		check(is_equal_approx(after.distance, float(before[index].distance) * 1.3), "Global range extends each projectile's real distance")
	var storm: Dictionary = attacks[3].get_attack_stats(1, mods)
	check(is_equal_approx(storm.max_radius, float(before[3].max_radius) * 1.3) and storm.visual_scale == 1.3, "Storm range and appearance share the grown propagation limit")
	var haste := GrowthBuffDefinition.new()
	haste.id = &"haste"
	haste.attribute = A.ATTACK_SPEED
	haste.bonus_per_level = 0.2
	mods.apply_buff(haste)
	var fan: Dictionary = attacks[4].get_attack_stats(1, mods)
	check(is_equal_approx(fan.rotation_speed, float(before[4].rotation_speed) * 1.2) and is_equal_approx(fan.motion_scale, 1.0 / 1.2), "Attack speed scales sword rotation and complete attack motion")
	for attack in attacks: attack.free()
	print("PASS epic growth: %d checks" % checks)
	quit()
