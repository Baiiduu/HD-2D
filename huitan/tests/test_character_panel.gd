extends SceneTree
## Headless input/pause ownership and data binding; visual acceptance stays manual.
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(40.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func run() -> void:
	var world := load("res://scenes/world/world.tscn").instantiate() as Node3D
	world.get_node("WorldMainMenu").show_on_world_start = false
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("GameSettingsUI").save_graphics_settings = false
	world.get_node("MapEffects/GameAudio").load_local_mix = false
	root.add_child(world)
	current_scene = world
	for frame in 12: await process_frame
	await create_timer(0.12).timeout
	var panel = world.get_node("CharacterPanel")
	var settings: GameSettingsUI = world.get_node("GameSettingsUI")
	var wave: WavePrototype = world.get_node("WavePrototype")
	var player: Player = world.get_node("Player")
	var controls := root.get_node("GameControls")
	var hud_visibility := [world.get_node("LoadoutUI").visible, wave.get_node("WaveHUD").visible, wave.get_node("ScoreHUD").visible]
	check(not panel.panel_open and not panel.is_processing(), "Closed panel performs no periodic stat updates")
	check(settings._character_page == null and not settings.include_character_page, "World character attributes are removed from settings")
	check(controls.action_available(&"character") and not controls.action_available(&"inventory"), "The independent action is available while the old backpack remains hidden")
	var blocker := Node.new()
	world.add_child(blocker)
	blocker.add_to_group(&"gameplay_input_blockers")
	key(KEY_C)
	check(not panel.panel_open and not paused, "Existing modal blockers take priority over the character shortcut")
	blocker.free()
	key(KEY_C)
	check(panel.panel_open and paused and not player.can_process() and panel.can_process(), "C opens the independent panel and pauses gameplay")
	check(not settings.menu_open and not settings._launcher.visible, "Settings does not overlap the character panel")
	check(not world.get_node("LoadoutUI").visible and not wave.get_node("WaveHUD").visible and not wave.get_node("ScoreHUD").visible, "Opening hides gameplay bars and level badges behind the character sheet")
	panel.open_panel()
	panel.select_category(&"combat")
	check(panel._rows.has(&"normal_sword") and panel._rows.has(&"flight_sword"), "Combat page uses independently registered sword modes")
	var damage: float = player.sword.get_stats().damage
	panel.refresh()
	check(panel._rows[&"normal_sword"]._numbers[0].text == panel.catalog.format_value(damage, "number"), "Rows display actual final sword damage while paused")
	panel.select_category(&"ricochet")
	check(panel._rows.has(&"energy") and panel._rows.has(&"motion_speed"), "Ricochet separates kinetic reserve and actual motion")
	key(KEY_ESCAPE)
	check(not panel.panel_open and not paused and not settings.menu_open, "Esc closes only the character panel, without reopening settings")
	check([world.get_node("LoadoutUI").visible, wave.get_node("WaveHUD").visible, wave.get_node("ScoreHUD").visible] == hud_visibility, "Closing restores each gameplay HUD's previous visibility")
	settings.open_menu()
	settings.select_page(4)
	check(settings._controls_page.buttons.has(&"character"), "Character shortcut is listed in the common rebinding page")
	settings._controls_page.begin_capture(&"character", 0)
	key(KEY_C)
	check(settings.menu_open and not panel.panel_open and not settings._controls_page.is_capturing(), "C is captured by rebinding instead of opening the panel")
	settings._controls_page.begin_capture(&"character", 0)
	key(KEY_ESCAPE)
	check(settings.menu_open and paused and not settings._controls_page.is_capturing(), "Esc cancels rebinding before closing settings")
	key(KEY_ESCAPE)
	check(not paused and not settings.menu_open, "Next Esc closes settings")
	check(controls.rebind(&"character", 0, KEY_H).is_empty(), "Character action supports normal rebinding")
	key(KEY_C)
	check(not panel.panel_open, "Old character key stops opening the panel after rebinding")
	key(KEY_H)
	check(panel.panel_open, "Rebound key opens the same panel")
	player.body_ricochet._press_pending = true
	player.body_ricochet._attack_pending = true
	player._blink._buffer_remaining = 0.1
	key(KEY_H)
	check(not panel.panel_open and not paused and not player.body_ricochet._press_pending and not player.body_ricochet._attack_pending and player._blink._buffer_remaining == 0.0, "Closing discards paused combat/dash input")
	paused = true
	panel.open_panel()
	panel.close_panel(false)
	check(paused, "Closing preserves an earlier tree pause")
	paused = false
	wave.set_combat_frozen(true)
	panel.open_panel()
	panel.close_panel(false)
	check(not paused and wave.combat_frozen, "Closing does not release independent combat freeze")
	wave.set_combat_frozen(false)
	panel.open_panel()
	world.remove_child(panel)
	check(not paused and get_first_node_in_group(&"gameplay_input_blockers") == null, "Removing an open panel releases only its own pause and lock")
	panel.free()
	controls.reset_defaults()
	world.free()
	for frame in 4: await process_frame
	var city: PackedScene = load("res://scenes/city/city.tscn")
	var city_state := city.get_state()
	var city_has_panel := false
	for index in city_state.get_node_count():
		if city_state.get_node_name(index) == &"CharacterPanel": city_has_panel = true
	var shared_settings := GameSettingsUI.new()
	check(not city_has_panel and shared_settings.include_character_page, "City resources and the shared settings retain independent legacy policy")
	shared_settings.free()
	print("Character panel: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
