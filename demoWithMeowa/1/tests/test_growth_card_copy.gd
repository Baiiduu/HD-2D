extends SceneTree
## 文案读取真实成长规则与技能数值，不渲染或验收视觉布局。
var checks := 0
var failures: Array[String] = []

class SessionFixture extends Node3D:
	var combat_modifiers := RunCombatModifiers.new()
	var player := Player.new()
	func get_attack_stats(modifiers: RunCombatModifiers = null) -> Array[Dictionary]:
		if not modifiers: modifiers = combat_modifiers
		return [{"damage": 10.0 * modifiers.damage_multiplier(), "interval": modifiers.interval_multiplier(), "range": modifiers.range_multiplier()}]

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var configuration: SceneCombatConfiguration = load("res://data/combat/scenes/world/configuration.tres")
	var session := SessionFixture.new()
	session.combat_modifiers.growth_rules = configuration.growth_rules.duplicate()
	session.player.ricochet_rules = configuration.ricochet_rules
	session.player.body_ricochet = PlayerRicochet.new()
	session.player.body_ricochet._player = session.player
	session.player.sword = PlayerSword.new()
	session.player.sword.rules = configuration.sword_rules
	var buffs := RunBuffs.new()
	buffs.session = session
	buffs.definitions = configuration.growth_definitions
	var definitions := {}
	for definition in buffs.definitions: definitions[definition.id] = definition
	var text := {}
	for option in buffs.candidates(): text[option.id] = option.description
	check(text[&"E02"].contains("20%") and text[&"E02"].contains("100%") and not text[&"E02"].contains("增伤强度"), "Speed damage describes the actual low/high damage benefits instead of its internal strength")
	check(text[&"E03"].contains("2～4") and not text[&"E03"].contains("基数"), "Multistrike describes total slash counts, including speed tiers")
	check(text[&"E04"].contains("攻速") and text[&"E04"].contains("×0.50"), "First heavy strike explicitly displays its actual attack-speed cost")
	check(text[&"E05"].contains("无每秒恢复上限") and not text[&"E05"].contains("每秒上限 "), "Lifesteal describes uncapped healing without a numerical cap row")
	check(text[&"L01"].contains("10 层") and text[&"L01"].contains("4 秒") and text[&"L01"].contains("独立计时"), "Kill haste retains duration, stack cap, and independent expiry")
	check(not text[&"P02"].contains("判定动作") and not text[&"E01"].contains("特效同步"), "Cards omit implementation details that do not help a choice")
	check(session.combat_modifiers.levels.is_empty(), "Generating descriptions never grants a buff")
	# Descriptions follow changed rules instead of hardcoded default percentages/counts.
	session.combat_modifiers.growth_rules.additional_strike_damage_ratio = 0.5
	session.combat_modifiers.growth_rules.maximum_strikes = 3
	session.combat_modifiers.growth_rules.heavy_interval_multiplier = 4.0
	check(buffs._description(definitions[&"E03"]).contains("50%") and buffs._description(definitions[&"E03"]).contains("2～3"), "Multistrike copy follows configured damage ratio and total strike cap")
	check(buffs._description(definitions[&"E04"]).contains("×0.25"), "Heavy cost follows the actual map interval multiplier")
	session.combat_modifiers.apply_buff(definitions[&"E04"])
	check(not buffs._description(definitions[&"E04"]).contains("×0.25 →"), "Heavy upgrades do not imply another attack-speed penalty")
	var prism := PrismRicochetAutoAttack.new()
	prism.skill_definition = configuration.skill_definitions.filter(func(value): return value.id == &"prism_ricochet")[0]
	var upgrade := prism.describe_skill_upgrade(3, 4)
	check(not upgrade.contains("弹射 4 → 4"), "Skill upgrades omit unchanged numerical rows")
	check(prism.describe_skill_upgrade(4, 5).contains("间隔"), "A changed attack interval is visible instead of omitted")
	var storm := RicochetStorm.new()
	storm.skill_definition = configuration.skill_definitions.filter(func(value): return value.id == &"ricochet_storm")[0]
	check(storm.describe_skill_upgrade(0, 1).contains("最多6只"), "Storm explains the maximum targets per round in player terms")
	check(not storm.describe_skill_upgrade(1, 2).contains("扩散 2 → 2"), "Storm upgrades omit unchanged layer counts")
	prism.free()
	storm.free()
	buffs.free()
	session.player.body_ricochet.free()
	session.player.sword.free()
	session.player.free()
	session.free()
	print("Growth card copy: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
