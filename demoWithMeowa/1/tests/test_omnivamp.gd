extends SceneTree
## 全能吸血不设每秒预算；基础剑术恢复仍保留自己的滑动一秒上限。
const A := GrowthBuffEffect.Attribute
var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func _initialize() -> void:
	var rules := RunGrowthRules.new()
	var survival := RunSurvival.new()
	survival.rules = rules
	var mods := RunCombatModifiers.new()
	mods.growth_rules = rules
	var vamp: GrowthBuffDefinition = load("res://data/combat/scenes/world/growth/epic/omnivamp.tres")
	check(vamp.extra_effects.all(func(effect): return effect.attribute != A.LIFESTEAL_CAP), "The actual World card no longer grants a healing cap")
	check(mods.apply_buff(vamp) and is_equal_approx(mods.bonus(A.LIFESTEAL), 0.03), "Removing the cap preserves the initial 3% lifesteal")
	var hit := CombatDamageEvent.new()
	hit.source = &"A02"
	hit.amount = 1000.0
	check(is_equal_approx(survival.recovery(hit, mods, 100.0, 50.0), 30.0), "One hit heals its full actual-damage fraction even above the old per-second cap")
	var burst_healing := 0.0
	for index in 20: burst_healing += survival.recovery(hit, mods, 2000.0, 1000.0)
	check(is_equal_approx(burst_healing, 600.0), "Repeated hits in the same instant do not share an omnivamp budget")
	check(is_equal_approx(survival.recovery(hit, mods, 100.0, 0.1), 0.1), "Recovery still stops at actual missing health")
	check(survival.recovery(hit, mods, 100.0, 0.0) == 0.0, "Full health cannot gain surplus healing")
	mods._bonuses[A.LIFESTEAL_CAP] = 0.0001
	check(is_equal_approx(survival.recovery(hit, mods, 100.0, 50.0), 30.0), "Legacy cap values cannot restore the removed limit")
	mods.apply_buff(vamp)
	check(is_equal_approx(survival.recovery(hit, mods, 100.0, 90.0), 60.0), "Upgrading the actual card continues to increase lifesteal without a cap")
	hit.simulated = true
	check(survival.recovery(hit, mods, 100.0, 90.0) == 0.0, "Simulation cannot restore health")
	hit.simulated = false
	for amount in [0.0, -1.0, INF, NAN]:
		hit.amount = amount
		check(survival.recovery(hit, mods, 100.0, 90.0) == 0.0, "Invalid or nonpositive actual damage cannot restore health")
	# 剑术的基础恢复上限仍单独生效，不能因取消吸血上限一并消失。
	survival.reset()
	hit.source = &"flight_sword"
	hit.amount = 10.0
	var basic_mods := RunCombatModifiers.new()
	var basic_healing := 0.0
	for index in 8:
		hit.attack_snapshot = CombatAttackSnapshot.new()
		basic_healing += survival.recovery(hit, basic_mods, 100.0, 50.0)
	check(is_equal_approx(basic_healing, 5.0), "Basic sword healing retains its independent 5%-per-second limit")
	hit.amount = 1000.0
	check(is_equal_approx(survival.recovery(hit, mods, 100.0, 90.0), 60.0), "A full sword-healing budget never suppresses omnivamp")
	survival.advance(1.01)
	check(survival.basic_used() == 0.0, "Basic healing still expires with combat time")
	print("Omnivamp: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
