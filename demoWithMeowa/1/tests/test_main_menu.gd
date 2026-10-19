extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func run() -> void:
	var timing_path := "res://scripts/ui/main_menu_timeline.gd"
	var flow_path := "res://scripts/ui/main_menu_flow.gd"
	check(FileAccess.file_exists(timing_path) and FileAccess.file_exists(flow_path), "Menu timeline and guarded start flow exist")
	if not failures.is_empty():
		quit(1)
		return
	var timeline = load(timing_path).new()
	check(timeline.advance(1.1) == [&"launch"], "Launch crosses its cue once")
	check(timeline.advance(0.0).is_empty(), "A held frame cannot replay cues")
	check(timeline.advance(0.5) == [&"bounce"], "Wall bounce follows launch")
	check(timeline.advance(0.7) == [&"hit", &"flyby"], "Crowd hit precedes foreground flyby")
	check(timeline.advance(-1.0).is_empty(), "Negative time does not rewind audio")
	var before: float = timeline.time
	timeline.advance(NAN)
	check(timeline.time == before, "Invalid time cannot poison the animation clock")
	check(timeline.advance(240.0).size() <= 4, "Returning from a long stall cannot flood the sound pool")
	check(timeline.time >= 0.0 and timeline.time < timeline.period, "Long frames preserve a bounded loop clock")
	timeline.reset()
	check(is_zero_approx(timeline.time), "Reset returns to charge preparation")
	timeline.reset(1.4)
	check(timeline.advance(10.9) == [&"bounce", &"hit", &"flyby", &"launch"], "Loop crossings preserve chronological cue order")
	timeline.period = 0.0
	timeline.advance(1.0)
	check(is_finite(timeline.time), "Invalid exported period is sanitized")
	var flow = load(flow_path).new()
	flow.minimum_transition = 0.65
	flow.modal_open = true
	check(not flow.begin(), "Settings cannot accidentally launch the map")
	flow.modal_open = false
	check(flow.begin() and not flow.begin(), "Repeated start inputs queue a single scene change")
	check(flow.advance(0.1, true, false) == &"wait", "Cached scenes still allow button feedback to finish")
	check(flow.advance(0.6, false, false) == &"wait", "Animation completion never blocks on unfinished loading")
	check(flow.advance(0.0, true, false) == &"commit", "Loaded map and completed feedback permit one handoff")
	check(flow.advance(1.0, true, false) == &"wait", "A committed handoff cannot repeat")
	flow.recover()
	check(flow.begin(), "A failed handoff restores start eligibility")
	check(flow.advance(0.1, false, true) == &"failed", "Loading failure returns a recoverable result")
	check(not flow.busy and flow.begin(), "Players can retry after a load failure")
	flow.recover()
	var menu_path := "res://scenes/ui/main_menu.tscn"
	check(ResourceLoader.exists(menu_path), "Menu has a runnable scene entry")
	if ResourceLoader.exists(menu_path):
		var menu = load(menu_path).instantiate()
		menu.save_preferences = false
		menu.audio_enabled = false
		menu.auto_prepare_world = false
		root.add_child(menu)
		for i in 4: await process_frame
		check(menu.buttons.size() == 3, "Menu exposes start, settings and quit")
		check(not menu.flow.busy and menu.stage != null, "Stage animation does not claim menu input")
		var exploration := load("res://data/audio/music/exploration.tres") as BgmTrack
		check(is_equal_approx(menu._music.volume_db, exploration.volume_db), "Standalone menu shares the exploration track gain instead of a separate music level")
		menu.open_settings()
		check(menu.flow.modal_open and menu.settings_panel.visible, "Settings owns navigation while the stage stays alive")
		check(menu._controls_page.buttons.size() >= 17, "Main menu shares the complete controls page")
		var settings_tabs: TabContainer = menu._controls_page.get_parent().get_parent()
		settings_tabs.current_tab = settings_tabs.get_tab_count() - 1
		menu._controls_page.begin_capture(&"toggle_rain", 0)
		var stage_time: float = menu.stage.timeline.time
		await process_frame
		check(menu.stage.timeline.time > stage_time, "Settings does not pause the performance")
		menu.close_settings()
		check(not menu.flow.modal_open and not menu.settings_panel.visible, "Back restores the menu without changing scenes")
		check(not menu._controls_page.is_capturing(), "Closing main-menu settings cancels pending key capture")
		var request = load("res://scripts/world/world_entry_request.gd")
		request.request()
		menu.flow.begin()
		menu._handoff(null)
		check(not menu.flow.busy and not request.consume(), "Failed scene handoff clears the one-shot intro request and restores input")
		for viewport_size in [Vector2(800, 600), Vector2(1440, 900), Vector2(2560, 1080)]:
			var rect: Rect2 = menu.panel_rect_for(viewport_size)
			check(Rect2(Vector2.ZERO, viewport_size).encloses(rect), "Central menu remains inside %s" % viewport_size)
		check(menu.stage.z_index + 35 < menu._footer.z_index, "Foreground actors cannot cover the menu or settings")
		# Exercise the real threaded loader and scene handoff with an inexpensive map fixture.
		var fixture := Node3D.new()
		fixture.name = "MainMenuFixture"
		var packed := PackedScene.new()
		packed.pack(fixture)
		fixture.free()
		var scratch_dir := "D:/.codexfile/work/main-menu-tests"
		DirAccess.make_dir_recursive_absolute(scratch_dir)
		var fixture_path := scratch_dir.path_join("menu_load_fixture-%d.tscn" % OS.get_process_id())
		check(ResourceSaver.save(packed, fixture_path) == OK, "Threaded-loading fixture saves in task scratch")
		menu.world_scene = fixture_path
		menu.start_feedback_seconds = 0.3
		current_scene = menu
		var weak_menu: WeakRef = weakref(menu)
		menu.start_game()
		menu.start_game()
		check(menu.flow.busy and menu._loading_notice.visible and menu.buttons[0].disabled, "Real start immediately locks duplicate input and exposes loading feedback")
		check(not request.consume(), "Intro is not requested before the map is ready")
		await create_timer(0.7).timeout
		check(current_scene != null and current_scene.name == "MainMenuFixture", "Threaded loading switches to the intended map")
		check(request.consume() and not request.consume(), "Successful menu handoff sets exactly one intro request")
		check(weak_menu.get_ref() == null, "Scene handoff frees the menu and its decorative/audio nodes")
		if is_instance_valid(weak_menu.get_ref()): weak_menu.get_ref().queue_free()
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/world/world.tscn", "F5 keeps the formal map entry")
	print("MAIN_MENU: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
