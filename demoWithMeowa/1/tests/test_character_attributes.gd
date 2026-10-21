extends SceneTree
## Read-only attribute data, conditional effects and extensible registration.
const SESSION = preload("res://tests/fixtures/ricochet_session.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func run() -> void:
	var path := "res://scripts/ui/character_attribute_catalog.gd"
	check(ResourceLoader.exists(path), "Character attributes have a dedicated registered data source")
	if failures:
		quit(1)
		return
	# Use real player/combat components and World resources without unrelated map/UI startup.
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var config: SceneCombatConfiguration = load("res://data/combat/scenes/world/configuration.tres")
	var wave: WavePrototype = SESSION.new()
	wave.name = "WavePrototype"
	wave.growth_rules = config.growth_rules
	wave.combat_modifiers.growth_rules = config.growth_rules
	wave.critical_chance = config.critical_chance
	wave.critical_multiplier = config.critical_multiplier
	world.add_child(wave)
	var player := Player.new()
	player.name = "Player"
	player.ricochet_rules = load("res://data/combat/scenes/world/player/body_ricochet.tres")
	player.sword_rules = load("res://data/combat/scenes/world/player/basic_sword.tres")
	player.add_child(Sprite3D.new())
	player.get_child(0).name = "Sprite"
	wave.player = player
	world.add_child(player)
	var catalog = load(path).new()
	catalog.configure(world)
	player.set_physics_process(false)
	player.sword.set_physics_process(false)
	var mods := wave.combat_modifiers
	var data: Dictionary = catalog.capture()
	check(data.health_max == player.max_health and data.health_current == player.current_health, "Health uses the current character, including training")
	check(data.crit_chance == wave.critical_chance and data.crit_multiplier == wave.critical_multiplier, "Critical values use the actual map combat configuration")
	check(data.normal_damage == player.sword.get_stats(false).damage and data.flight_interval == player.sword.get_stats(true).interval, "Both sword modes use the actual attack interface")
	check(data.energy == 0.0 and data.motion_speed == 0.0, "Idle energy is distinct from launch parameters")
	var ids := {}
	for definition in catalog.definitions:
		check(not ids.has(definition.id), "Registered IDs remain unique: " + String(definition.id))
		ids[definition.id] = true
	check(not ids.has(&"mana") and not ids.has(&"defense") and not ids.has(&"push_force"), "Inactive legacy attributes are excluded")
	var damage := GrowthBuffDefinition.new()
	damage.id = &"catalog_damage"
	damage.attribute = GrowthBuffDefinition.Attribute.DAMAGE
	damage.bonus_per_level = 0.2
	mods.apply_buff(damage)
	data = catalog.capture()
	check(is_equal_approx(data.normal_damage, player.sword.get_stats(false).damage), "Growth changes the same damage shown by combat")
	mods._bonuses[GrowthBuffDefinition.Attribute.ATTACK_SPEED] = 100.0
	data = catalog.capture()
	check(data.normal_interval == player.sword.get_stats(false).interval and data.normal_interval >= player.sword.rules.minimum_attack_interval, "Shown interval respects the real action floor")
	mods._bonuses[GrowthBuffDefinition.Attribute.LIFESTEAL] = 0.03
	data = catalog.capture()
	check(is_equal_approx(data.vamp, 0.03) and not data.has("vamp_cap"), "Lifesteal reports its real percentage without a removed cap")
	var vamp_row: Dictionary = catalog.rows(&"survival", data).filter(func(row): return row.id == &"vamp")[0]
	check(vamp_row["values"] == ["3.0%"] and vamp_row.detail.contains("无每秒恢复上限"), "The actual survival row has no misleading health-per-second limit")
	player.body_ricochet.state = PlayerRicochet.State.FLYING
	player.body_ricochet.flight_speed = 9.0
	player.body_ricochet._settings = player.ricochet_rules.duplicate()
	player.body_ricochet._settings.maximum_launch_speed = 17.0
	player.body_ricochet._orbit_speed_blend = 1.0
	var tier := wave._strike_speed_tier
	var serial := wave._strike_flight_serial
	data = catalog.capture()
	check(wave._strike_speed_tier == tier and wave._strike_flight_serial == serial, "Inspecting conditional sword counts never advances attack state")
	check(data.energy == 9.0 and data.motion_speed == player.body_ricochet.movement_speed, "Energy and actual movement are read independently")
	check(data.launch_max == 17.0 and data.ricochet_context == "本次弹射", "An active flight displays its frozen launch snapshot")
	mods._bonuses[GrowthBuffDefinition.Attribute.RICOCHET_SPEED] = 1.0
	check(catalog.capture().launch_max == 17.0, "Later growth does not rewrite the active flight snapshot")
	player.body_ricochet.cancel(true)
	check(catalog.capture().launch_max == player.body_ricochet.get_stats().maximum_launch_speed, "Idle displays the next launch after growth")
	var before: Dictionary = mods._bonuses.duplicate()
	var result: bool = catalog.register_stat({"id": &"future", "categories": [&"combat"], "group": "新增属性", "label": "测试扩展", "keys": [&"crit_chance"], "formats": ["percent"], "source": "注册扩展"})
	check(result and catalog.rows(&"combat").any(func(row): return row.id == &"future"), "A registered attribute appears without changing layout components")
	check(not catalog.register_stat({"id": &"future"}), "Duplicate registrations cannot silently replace an attribute")
	check(mods._bonuses == before, "Reading and formatting attributes never modifies combat")
	mods.reset()
	check(is_equal_approx(catalog.capture().damage_multiplier, 1.0), "Reset is reflected without retaining stale growth")
	for frame in 4: await process_frame
	world.free()
	for frame in 4: await process_frame
	print("Character attributes: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
