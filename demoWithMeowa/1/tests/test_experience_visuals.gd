extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for frame in 4: await process_frame

func run() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	var loadout: LoadoutUI = world.get_node("LoadoutUI")
	loadout.save_enabled = false
	root.add_child(world)
	current_scene = world
	await settle()
	var wave: WavePrototype = world.get_node("WavePrototype")
	var growth: RunGrowth = wave.get_node("RunGrowth")
	var hud := growth.experience_hud
	var attributes := loadout._attribute_hud
	wave.player.set_physics_process(false)
	wave.set_physics_process(false)
	wave.get_node("FanAutoAttack").set_physics_process(false)
	growth.set_physics_process(false)
	growth.choice_ui.open_duration = 0.0
	check(hud.state == growth.state and hud.attribute_hud == attributes, "XP HUD binds the live run and existing attribute HUD")
	check(hud._level.text == "Lv. 1" and hud._value.text == "0 / 10" and not hud._clip.visible, "Fresh run has real level and an empty XP bar")
	check(hud._root.position.y >= attributes.get_global_rect().end.y + hud.attribute_gap - 0.01, "XP HUD sits below HP and mana without overlap")
	check(hud._root.mouse_filter == Control.MOUSE_FILTER_IGNORE and hud._clip.mouse_filter == Control.MOUSE_FILTER_IGNORE, "XP HUD does not intercept gameplay pointer input")
	wave.player.global_position = wave._path.ground_position(wave.global_position) + Vector3.UP * 0.03
	check(wave.start_run(), "Actual wave run starts for visual integration")
	growth.drop_experience(wave.player.global_position + Vector3(8, 0, 0), 3)
	var pickup := growth._drops[0]
	check(pickup.visual_tier == 0 and pickup._gem.texture == pickup.cyan_texture, "Default monster experience uses cyan artwork")
	pickup.amount += 10
	check(pickup.amount == 13 and pickup.visual_tier == 1 and pickup._gem.texture == pickup.violet_texture, "Merged experience refreshes violet artwork immediately")
	pickup.amount += 20
	check(pickup.amount == 33 and pickup.visual_tier == 2 and pickup._gem.texture == pickup.amber_texture, "Large merged experience refreshes amber artwork")
	check(growth.state.total_experience == 0, "Choosing an appearance never grants XP")
	growth.max_pickups = 1
	growth.drop_experience(pickup.global_position, 4)
	check(growth._drops.size() == 1 and pickup.amount == 37, "Visual integration preserves capped-drop value merging")
	pickup.medium_threshold = 40
	pickup.large_threshold = 80
	check(pickup.visual_tier == 0 and pickup.amount == 37, "Visual thresholds are adjustable without changing XP")
	check(pickup._gem.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST and pickup._gem.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Pixel pickup keeps nearest filtering and no false plane shadow")
	growth._clear_drops()
	growth.max_pickups = 256
	growth.drop_experience(wave.player.global_position, 6)
	var full_fill := hud._fill.size
	growth._physics_process(1.0)
	check(growth.state.experience == 6 and hud._value.text == "6 / 10" and is_equal_approx(hud.progress_ratio, 0.6), "Actual attraction updates XP numbers and progress")
	check(hud._fill.size == full_fill and is_equal_approx(hud._clip.size.x / full_fill.x, 0.6), "Progress clips artwork without squeezing it")
	check(growth._absorb.visible and hud._feedback_left > 0.0, "Actual collection triggers small world and HUD feedback")
	growth.drop_experience(wave.player.global_position + Vector3(8, 0, 0), 1)
	var waiting := growth._drops[0]
	growth.drop_experience(wave.player.global_position, 8)
	growth._physics_process(1.0)
	check(wave.combat_frozen and growth.choice_ui.is_open and hud._level.text == "Lv. 2" and hud._value.text == "4 / 15", "Existing growth choice and HUD reflect the same level and overflow")
	var clock := waiting._clock
	var gem_position := waiting._gem.position
	growth._physics_process(10.0)
	check(waiting._clock == clock and waiting._gem.position == gem_position, "Level choices freeze pickup visual animation as well as attraction")
	hud._process(0.0)
	check(hud._root.visible and not paused, "XP remains visible during the existing growth UI without pausing the world")
	growth.choice_ui.confirm_selection()
	check(not wave.combat_frozen, "Existing confirmation resumes battle")
	wave._spawn_queue.clear()
	wave._physics_process(0.01)
	check(wave.phase == WavePrototype.Phase.REST, "Management UI checks use actual safe rest")
	loadout.open_menu()
	hud._process(0.0)
	check(not hud._root.visible, "XP hides with attributes in the character/inventory book")
	loadout.close_menu()
	await create_timer(0.3).timeout
	hud._process(0.0)
	check(hud._root.visible, "Closing the book restores XP HUD")
	loadout.hide()
	hud._process(0.0)
	check(not hud._root.visible, "Training-style owner hiding also hides XP")
	loadout.show()
	attributes.bar_width = 420.0
	attributes.screen_margin = Vector2(35, 42)
	await settle()
	hud.update_layout()
	check(is_equal_approx(hud._root.position.x, attributes.position.x) and hud._root.position.y >= attributes.get_global_rect().end.y, "XP follows live attribute layout edits")
	growth.rules.level_cap = 3
	growth.state.add_experience(99)
	check(hud._level.text == "Lv. 3" and hud._value.text == "MAX" and hud.progress_ratio == 1.0, "Level cap displays MAX with a full track")
	while growth.choice_ui.is_open: growth.choice_ui.confirm_selection()
	wave.retreat()
	wave.retry()
	check(growth.state.level == 1 and hud._value.text == "0 / 10" and hud.progress_ratio == 0.0 and not growth._absorb.visible, "Retry resets real XP, HUD and lingering world feedback")
	var replacement := RunGrowthState.new()
	replacement.rules = ExperienceRules.new()
	replacement.add_experience(5)
	hud.bind_state(replacement, attributes, loadout)
	growth.state.changed.emit()
	check(hud.state == replacement and hud._value.text == "5 / 10", "Rebinding removes the old state subscription")
	replacement.rules.first_level_experience = 10000
	replacement.add_experience(9994)
	check(hud._value.text == "9999 / 10000" and hud._value.position.x + hud._value.size.x <= hud._root.size.x, "Large XP numbers remain inside the HUD bounds")
	hud.follow_attributes = false
	hud.screen_margin = Vector2(50, 150)
	check(hud._root.position == Vector2(50, 150), "HUD position can also be adjusted independently")
	hud.follow_attributes = true
	hud.bind_state(growth.state, attributes, loadout)
	growth.enabled = false
	check(not hud.visible and not growth.active and growth._drops.is_empty(), "Disabling growth also hides its HUD and removes drops")
	for audio in world.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	world.free()
	await settle()
	# 无界面测试会快速退出，留给音频线程时间释放已停止的 UI 和环境声。
	await create_timer(0.15).timeout
	print("Experience visuals: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
