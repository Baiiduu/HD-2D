extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for frame in 5:
		await process_frame

func progress(hud: AttributeHUD, index: int) -> float:
	var row := hud._bars[index]
	return (row.get_node("Progress") as Control).size.x / (row.get_node("Progress/Fill") as TextureRect).size.x

func run() -> void:
	root.size = Vector2i(1280, 800)
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	var loadout: LoadoutUI = world.get_node("LoadoutUI")
	loadout.save_enabled = false
	root.add_child(world)
	current_scene = world
	await settle()
	var player: Player = world.get_node("Player")
	var hud := loadout._attribute_hud
	check(hud.player == player and player.character_state == loadout.state, "HUD binds the actual player and shared attribute state")
	check(player.max_health == player.get_attributes().health and player.max_mana == player.get_attributes().mana, "Maxima use base, equipment and training attributes")
	check(player.current_health == player.max_health and player.current_mana == player.max_mana, "Spawn is full after starting equipment is applied")
	check(progress(hud, 0) == 1.0 and progress(hud, 1) == 1.0, "Both full bars reflect actual spawn values")
	var full_fill_size := (hud._bars[0].get_node("Progress/Fill") as TextureRect).size
	check(player.take_damage(25.0) == 25.0, "Damage updates actual health")
	check(is_equal_approx(progress(hud, 0), player.current_health / player.max_health), "Damage immediately changes the health bar")
	check((hud._bars[0].get_node("Progress/Fill") as TextureRect).size == full_fill_size, "Progress clips the artwork without squeezing it")
	var expected := "%d / %d" % [int(player.current_health), int(player.max_health)]
	check((hud._bars[0].get_node("Value") as Label).text == expected, "Text displays actual current and maximum health")
	player.take_damage(0.25)
	check((hud._bars[0].get_node("Value") as Label).text.begins_with("109.75 / "), "Fractional health remains readable")
	player.heal(0.25)
	check(player.spend_mana(40.0) and is_equal_approx(progress(hud, 1), 0.6), "Mana debit immediately changes the blue bar")
	check(not player.spend_mana(61.0) and player.current_mana == 60.0, "Insufficient mana cannot overdraw")
	check(player.heal(10.0) == 10.0 and player.restore_mana(20.0) == 20.0, "Healing and mana restoration update actual values")
	var lost_health := player.max_health - player.current_health
	var old_max := player.max_health
	check(loadout.state.train("health"), "Existing health training succeeds")
	check(player.max_health == old_max + 10.0 and player.max_health - player.current_health == lost_health, "Training raises the maximum while preserving lost health")
	check(is_equal_approx(progress(hud, 0), player.current_health / player.max_health), "Training refreshes the bound HUD")
	loadout.state.unequip(EquipmentDefinition.Slot.ARMOR)
	check(player.max_health == player.get_attributes().health and player.max_health - player.current_health == lost_health, "Unequipping recalculates the maximum without restoring damage")
	var before := player.current_health
	loadout.state.toggle_favorite("sword")
	check(player.current_health == before, "Unrelated inventory changes do not refill health")
	player.current_health = -50.0
	check(player.current_health == 0.0 and not (hud._bars[0].get_node("Progress") as Control).visible, "Zero health hides all colored fill")
	player.current_health = player.max_health + 20.0
	check(player.current_health == player.max_health and progress(hud, 0) == 1.0, "Health clamps to its real maximum")
	player.current_mana = -5.0
	check(player.current_mana == 0.0 and progress(hud, 1) == 0.0, "Mana clamps to zero")
	check(player.restore_mana(500.0) == player.max_mana and progress(hud, 1) == 1.0, "Mana restoration clamps to its maximum")
	check(not player.spend_mana(-1.0) and player.take_damage(-1.0) == 0.0, "Negative transactions cannot invert their effects")
	hud.glow_strength = 0.4
	hud.background_opacity = 0.5
	hud.show_values = false
	var skin := (hud._bars[0].get_node("Frame") as TextureRect).material as ShaderMaterial
	check(skin.get_shader_parameter("glow_strength") == 0.4 and skin.get_shader_parameter("background_opacity") == 0.5, "Visual controls update independently of player values")
	check(not (hud._bars[0].get_node("Value") as Label).visible, "Value text can be hidden")
	hud.bar_width = 420.0
	hud.screen_margin = Vector2(30, 40)
	await settle()
	check(hud.size.x == 420.0 and hud.position == Vector2(30, 40) and progress(hud, 1) == 1.0, "Layout changes retain the binding and progress")
	loadout.open_menu()
	check(not hud.visible and not paused, "Opening the character menu hides the HUD with a live world")
	player.spend_mana(30.0)
	check(is_equal_approx(progress(hud, 1), 0.7), "Hidden HUD keeps receiving actual value changes")
	loadout.close_menu()
	await create_timer(loadout.close_duration + 0.05).timeout
	check(hud.visible and not paused, "Closing the menu restores the HUD")
	hud.bar_width = 720.0
	root.size = Vector2i(300, 200)
	root.content_scale_size = Vector2i(300, 200)
	await settle()
	check(hud.scale.x < 1.0 and hud.position.x + hud.size.x * hud.scale.x <= 300.1, "Small windows keep the bars on screen")
	var old_state := player.character_state
	var rules := TrainingRules.new()
	rules.base_health = 200.0
	rules.base_mana = 80.0
	var state := LoadoutState.new(loadout.catalog, 4, rules)
	player.starting_health_ratio = 0.5
	player.starting_mana_ratio = 0.25
	player.character_state = state
	check(player.current_health == 100.0 and player.current_mana == 20.0, "New character state applies configured spawn ratios")
	old_state.train("health")
	check(player.max_health == 200.0 and player.current_health == 100.0, "Previous character state no longer changes the player")
	check(is_equal_approx(progress(hud, 0), 0.5) and is_equal_approx(progress(hud, 1), 0.25), "HUD follows the replacement character state")
	world.free()
	current_scene = null
	await settle()
	print("Attribute HUD: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
