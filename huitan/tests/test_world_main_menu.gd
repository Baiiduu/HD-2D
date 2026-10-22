extends SceneTree

const WORLD := "res://scenes/world/world.tscn"
const MENU := "res://scenes/ui/main_menu.tscn"
const REQUEST = preload("res://scripts/world/world_entry_request.gd")
const WORK := "D:/.codexfile/work/audio-preferences-20261020"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(WORK)
	create_timer(40.0).timeout.connect(func(): quit(2))
	node_added.connect(quiet_scene)
	run.call_deferred()

func quiet_scene(node: Node) -> void:
	if node.scene_file_path == WORLD:
		node.get_node("LoadoutUI").save_enabled = false
		node.get_node("GameSettingsUI").save_graphics_settings = false
		node.get_node("MapEffects/BGM").music_enabled = false
		node.get_node("MapEffects/GameAudio").load_local_mix = false
		node.get_node("MapEffects/GameAudio").mix_save_path = WORK + "/world-main-menu.cfg"
		node.get_node("MapEffects/Weather").rain_audio_enabled = false
		node.get_node("MapEffects/Weather").wind_audio_enabled = false
		node.get_node("MapEffects/CoreFeedbackAudio").enabled = false
		node.get_node("WorldEntry").preview_on_direct_run = false
		var startup := node.get_node_or_null("WorldMainMenu")
		if startup: startup.prewarm_entry = false
	elif node.scene_file_path == MENU:
		node.audio_enabled = false
		node.save_preferences = false

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)

func frames(count := 4) -> void:
	for i in count: await process_frame

func wait_property(node: Node, property: StringName, expected: Variant = true, invert := false) -> bool:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if is_instance_valid(node) and ((node.get(property) == expected) != invert): return true
		await create_timer(0.01).timeout
	return false

func wait_world() -> bool:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if current_scene and current_scene.scene_file_path == WORLD: return true
		await create_timer(0.01).timeout
	return false

func feedback_lifecycle_checks(world: Node) -> void:
	var wave := world.get_node("WavePrototype") as WavePrototype
	world.get_node("WavePresentation").enabled = false
	wave.skill_draft.enabled = false
	wave.get_node("RunGrowth").enabled = false
	wave.set_physics_process(false)
	var reserve := wave._prepared_feedback
	var exits := [0]
	reserve.tree_exiting.connect(func(): exits[0] += 1)
	check(wave.start_run() and wave._attack_root.get_node("EnemyFeedbackPool") == reserve, "Battle leases the exact prepared pool without replacing its nodes")
	check(exits[0] == 0 and not reserve.is_processing() and wave._prepared_feedback == null, "Leasing does not reenter the tree or continue warming during battle")
	var effect := reserve.death(wave.player.sprite, false, wave.player.action_visuals)
	wave.set_combat_frozen(true)
	var age := effect._age
	await frames(3)
	check(effect._age == age, "Prepared death effects still inherit combat freeze")
	wave.set_combat_frozen(false)
	wave._spawn_state.clear()
	wave._clear_wave()
	check(wave.phase == WavePrototype.Phase.REST and is_instance_valid(reserve) and effect._active, "Clear keeps the real death presentation running while entering rest")
	check(wave._prepared_feedback != null and wave._prepared_feedback != reserve, "Rest prepares a new reserve without stealing active death nodes")
	await frames(16)
	var next := wave._prepared_feedback
	check(wave.feedback_prewarm_ready() and next._idle_deaths.size() == 20 and next._idle_contacts.size() == 8, "Next wave has a complete reserve before continuing")
	check(wave.start_next_wave() and wave._attack_root.get_node("EnemyFeedbackPool") == next, "Following waves reuse their own completed reserve")
	wave.retreat()
	await frames(2)
	wave.reset_for_menu()
	check(wave.phase == WavePrototype.Phase.READY and wave._prepared_feedback != null, "Returning to menu resumes preparation without retaining combat work")

func run() -> void:
	var world = load(WORLD).instantiate()
	check(world.has_node("WorldMainMenu"), "World owns the real startup menu and preparation controller")
	if not failures.is_empty():
		world.free()
		quit(1)
		return
	var startup = world.get_node("WorldMainMenu")
	startup.show_on_world_start = false
	root.add_child(world)
	current_scene = world
	await frames(10)
	startup.prewarm_entry = true
	startup.open_menu()
	check(await wait_property(startup, &"menu", null, true), "Embedded menu appears in the already-instantiated World")
	var menu = startup.menu
	var music := world.get_node("MapEffects/BGM") as BackgroundMusic
	var original_gain := music.music_volume_db
	var exploration: BgmTrack = music.playlists[0].tracks[0]
	check(is_equal_approx(menu._music.volume_db, original_gain + exploration.volume_db), "Menu and gameplay share the same steady exploration music level")
	music.music_volume_db = -3.5
	menu._sync_music_mix()
	check(is_equal_approx(menu._music.volume_db, music.music_volume_db + exploration.volume_db), "Changing the map music gain also applies to its embedded menu")
	music.music_volume_db = original_gain
	menu.flow.elapsed = 0.65
	menu._update_start_fade()
	var fading_gain: float = menu._music.volume_db
	menu._mix_manager.mix.set_bus_gain(&"Music", -5.0)
	check(is_equal_approx(menu._music.volume_db, fading_gain) and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")), menu._mix_manager.music_volume_db - 5.0), "Shared volume changes preserve the start fade and use the same Music bus")
	menu._mix_manager.mix.reset_all()
	menu.flow.elapsed = 0.0
	menu._update_start_fade()
	var entry = world.get_node("WorldEntry")
	check(await wait_property(entry, &"active"), "Entry effects are warmed behind the menu before Start")
	check(not entry.is_processing_input(), "Hidden entry warmup does not swallow menu controls")
	entry.advance(0.5)
	check(entry._traversal == null, "Hidden preparation keeps the cinematic traversal sound silent")
	check(menu.buttons[0].disabled and not menu.flow.busy, "Preparation gates Start while keeping menu interactions available")
	menu.start_game()
	check(not menu.flow.busy, "Calling Start directly cannot bypass preparation")
	entry.skip()
	check(await wait_property(startup, &"game_ready"), "Navigation, initialization and normal-view warmup finish before Start is enabled")
	check(not menu.buttons[0].disabled and menu.startup_controller == startup, "Ready menu binds to the live World")
	check(menu.get_node("Presentation").layer > world.get_node("GameSettingsUI").layer, "Menu draws above gameplay HUD and post-processing")
	check(get_first_node_in_group(&"gameplay_input_blockers") == startup, "World stays input-blocked while menu owns the screen")
	var wave = world.get_node("WavePrototype")
	check(wave.feedback_prewarm_ready() and wave._prepared_feedback != null and wave._prepared_feedback._idle_deaths.size() == 20 and wave._prepared_feedback._idle_contacts.size() == 8, "Start waits for complete, hidden combat feedback reserves")
	check(wave._path_ready and wave.phase == WavePrototype.Phase.READY and wave.enemies.is_empty(), "Prepared game has navigation and an empty, unstarted run")
	var world_id: int = world.get_instance_id()
	var old_menu: WeakRef = weakref(menu)
	# A fully prepared start must succeed even when the standalone loading path is unusable.
	menu.world_scene = "res://no_scene_should_load_when_starting_prepared_world.tscn"
	menu.start_feedback_seconds = 0.3
	menu.start_game()
	menu.start_game()
	check(menu.flow.busy, "Prepared Start accepts one transition")
	await create_timer(0.55).timeout
	check(current_scene == world and world.get_instance_id() == world_id, "Start reuses the same World without loading or instantiating another map")
	check(startup.started and old_menu.get_ref() == null, "Completed feedback removes the menu without freeing World")
	check(entry.active and entry.is_processing_input() and not REQUEST.consume(), "Actual entry plays normally with a consumed, one-shot request")
	entry.advance(0.5)
	check(entry._traversal != null and entry._traversal.playing and entry._traversal.bus == &"Movement", "Real Start plays traversal sound on the independent movement bus")
	entry.skip()
	await frames()
	check(get_nodes_in_group(&"gameplay_input_blockers").is_empty(), "Entry hands control back without a stale menu blocker")
	await feedback_lifecycle_checks(world)
	world.free()
	await frames()
	# Standalone F6/return-to-menu entry also prepares World before permitting Start.
	var standalone = load(MENU).instantiate()
	root.add_child(standalone)
	current_scene = standalone
	check(standalone.buttons[0].disabled, "Standalone menu begins preparation before any click")
	check(await wait_world(), "Standalone menu promotes to an initialized World during preparation")
	if current_scene and current_scene.scene_file_path == WORLD:
		startup = current_scene.get_node("WorldMainMenu")
		check(await wait_property(startup, &"game_ready"), "Returned/standalone World is ready before Start")
		check(startup.menu != null and not startup.menu.buttons[0].disabled, "Prepared World exposes the interactive menu")
		check(not REQUEST.consume() and not current_scene.get_node("WorldEntry").active, "Background preparation does not prematurely begin the visible entry")
	if current_scene: current_scene.free()
	await frames()
	await create_timer(0.3).timeout
	REQUEST.clear()
	print("WORLD_MAIN_MENU: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
