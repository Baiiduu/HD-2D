extends SceneTree

var checks := 0
var failures: Array[String] = []
var world: Node
var wave: WavePrototype
var presentation: WavePresentation

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func spawn(point: Vector3, id := "wave_slime") -> WaveEnemy:
	var data := load("res://data/enemies/%s.tres" % id).duplicate() as WaveEnemyDefinition
	var enemy := data.scene.instantiate() as WaveEnemy
	enemy.configure_wave({"player":wave.player, "terrain":wave.terrain, "camera":wave.player.movement_camera,
		"navigation":wave._path, "attack_root":wave._attack_root, "spatial_index":wave._spatial_index,
		"damage_player":Callable(), "request_spawn":Callable(),
		"combat_active":wave.combat_active, "request_spawn_by_id":wave._request_spawn_by_id.bind(wave.get_combat_generation())}, data, 0.0)
	wave.add_child(enemy)
	enemy.global_position = point
	enemy.set_wave_tick_enabled(false)
	enemy.set_process(false)
	wave._enemy_roster.register(enemy)
	wave._spatial_index.update(enemy)
	enemy.defeated.connect(wave._enemy_defeated)
	return enemy

func kill(enemy: WaveEnemy) -> void:
	enemy.take_damage(100000.0, {"source":&"basic_sword", "contact_distance":1.0, "motion_velocity":Vector3.RIGHT * 8.0})

func run() -> void:
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("GameSettingsUI").save_graphics_settings = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	world.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	for index in 12: await physics_frame
	wave = world.get_node("WavePrototype")
	presentation = world.get_node("WavePresentation")
	wave.set_physics_process(false)
	wave.player.set_physics_process(false)
	wave.start_run()
	var choice := wave.skill_draft.initial_choice
	choice.reveal_now()
	choice.select_option(choice._options[0].id)
	choice.confirm_selection()
	presentation.set_process(false)
	presentation.advance(0.2)
	var opening_camera := wave.player.movement_camera as FollowCamera
	check(not presentation.shot.active and not opening_camera.wave_shot_active and is_equal_approx(opening_camera.wave_shot_distance_scale, 1.0), "First wave announcement does not move or zoom the camera")
	check(is_equal_approx(presentation.settings.finish_shot_seconds, 3.0), "Final-kill presentation defaults to three real seconds")
	presentation.advance(5.0)
	wave._spawn_state.clear()
	check(presentation.get("shot") != null and wave.has_method("is_wave_finish_pending"), "Last kill needs a camera shot and a bounded clear/upgrade barrier")
	if presentation.get("shot") == null or not wave.has_method("is_wave_finish_pending"):
		wave.retreat()
		world.free()
		finish()
		return
	var shot: RefCounted = presentation.get("shot")
	var camera := wave.player.movement_camera as FollowCamera
	var growth := wave.get_node("RunGrowth") as RunGrowth
	var experience := growth.experience_hud
	# 此夹具前段关闭升级逻辑，单独显示真实经验 HUD 来检查演出遮隐。
	experience.show()
	experience._process(0.0)
	var experience_color := Color(0.9, 0.8, 0.7, 0.65)
	experience._root.modulate = experience_color
	check(experience.visible and experience._root.visible, "Experience HUD is visible before the final kill")
	var authored := [camera.distance, camera.fov, camera.pitch_degrees, camera.yaw_degrees]
	var first := spawn(wave.player.global_position + Vector3.RIGHT)
	var last := spawn(wave.player.global_position + Vector3.RIGHT * 2.0)
	var impact := world.get_node("HitImpactPresentation")
	impact.call("_watch", first)
	kill(first)
	check(not shot.active and camera.hit_stop_active, "Ordinary kills use the immediate short kill hold without triggering the wave-final cinematic")
	impact.call("advance", 0.0)
	impact.set_process(false)
	check(camera.hit_stop_active and Engine.time_scale < 0.01, "A real preceding kill owns a short hit stop before the final kill")
	kill(last)
	check(not camera.hit_stop_active, "The final-kill shot synchronously cancels the preceding hit stop")
	presentation.set_process(false)
	check(shot.active and wave.is_wave_finish_pending() and Engine.time_scale < 0.5, "True final kill immediately starts world slow motion before the corpse disappears")
	check(experience._root.modulate.a == 0.0 and experience.visible, "Final-kill closeup immediately removes XP pixels without changing its owning layer")
	experience._process(Engine.time_scale * 0.1)
	check(experience._root.modulate.a == 0.0, "Experience HUD refresh cannot reveal the bar during the closeup")
	check(wave.kills == 2 and wave.enemies.is_empty() and not wave.combat_frozen and not paused, "Deaths settle immediately without pausing the tree or freezing combat")
	check(get_first_node_in_group(&"gameplay_input_blockers") == null, "Cinematic does not take player input")
	wave._clear_wave()
	check(wave.phase == WavePrototype.Phase.BATTLE, "Clear and last-kill upgrades wait until the short shot ends")
	var wave_clock := wave._wave_clock
	wave._physics_process(0.1)
	check(is_equal_approx(wave._wave_clock, wave_clock), "Presentation time does not penalize the completed wave's combat clock")
	presentation.advance(0.22)
	check(camera.get("wave_shot_distance_scale") < 0.85 and camera.get("wave_shot_weight") > 0.5, "The shot actually moves/zooms the real camera")
	check([camera.distance, camera.fov, camera.pitch_degrees, camera.yaw_degrees] == authored, "Shot preserves authored camera settings")
	check(wave.player.sprite.get_instance_shader_parameter("wave_finish_silhouette") > 0.0, "Impact emphasis uses the actual character silhouette")
	check(wave.loadout._root.modulate.a < 0.1 and wave.loadout.visible, "Combat HUD gently retreats without changing menu-owned layer visibility")
	var score_hud := wave.get_node("ScoreHUD")
	score_hud.set("_count_time", 0.0)
	score_hud.call("_process", Engine.time_scale * 0.01)
	check(is_equal_approx(score_hud.get("_count_time"), 0.01), "Score UI advances at normal speed during world slow motion")
	growth.enabled = true
	growth.active = true
	growth._grant_experience(100)
	check(growth.state.pending_choices > 0 and not growth.choice_ui.is_open and not wave.combat_frozen, "Earned upgrades remain pending without interrupting the final kill")
	check(experience._root.modulate.a == 0.0 and experience.state == growth.state, "Real experience and level updates remain bound while their bar is hidden")
	presentation.advance(2.0)
	check(shot.active and wave.is_wave_finish_pending() and not growth.choice_ui.is_open, "Final-kill focus and upgrade barrier remain active beyond two seconds")
	presentation.advance(0.77)
	check(shot.active and wave.is_wave_finish_pending(), "The shot remains active until its three-second boundary")
	check(experience._root.modulate.a == 0.0, "XP stays completely hidden throughout the camera return")
	presentation.advance(0.02)
	check(not shot.active and Engine.time_scale == 1.0 and not wave.is_wave_finish_pending(), "Shot ends on real time and restores the world clock")
	check(is_zero_approx(camera.get("wave_shot_weight")) and is_equal_approx(camera.get("wave_shot_distance_scale"), 1.0), "Camera fully restores its normal live follow pose")
	check(is_zero_approx(wave.player.sprite.get_instance_shader_parameter("wave_finish_silhouette")), "No silhouette material state leaks after the shot")
	check(is_equal_approx(wave.loadout._root.modulate.a, 1.0), "Combat HUD opacity is restored after the closeup")
	check(experience._root.modulate == experience_color, "Closeup restores the experience HUD's original color and opacity")
	growth._try_open_choice()
	check(growth.choice_ui.is_open and wave.combat_frozen, "Queued upgrade choice opens normally after camera recovery")
	growth._end_run("")
	growth.enabled = false
	wave._clear_wave()
	check(wave.phase == WavePrototype.Phase.REST, "Normal rest and active continuation remain available")
	wave.start_next_wave()
	check(not shot.active and not camera.wave_shot_active and is_equal_approx(camera.wave_shot_distance_scale, 1.0), "Later wave starts also preserve the existing camera pose")
	presentation.advance(5.0)
	wave._spawn_state.clear()
	var mother := spawn(wave.player.global_position + Vector3.RIGHT, "pot_brood")
	kill(mother)
	check(wave._pending > 0 and not shot.finishing, "Splitting mother is not a final kill while its children are pending")
	wave._spawn_state.clear()
	last = spawn(wave.player.global_position + Vector3.RIGHT)
	kill(last)
	check(shot.finishing, "New wave owns an independent final-kill shot")
	var blocker := Node.new()
	root.add_child(blocker)
	blocker.add_to_group(&"gameplay_input_blockers")
	presentation.advance(0.01)
	check(not shot.active and Engine.time_scale == 1.0 and not wave.is_wave_finish_pending(), "Opening management UI immediately releases slow motion and the camera")
	check(not experience.visible and experience._root.modulate == experience_color, "Interrupted closeup restores XP opacity without reopening a disabled experience layer")
	blocker.free()
	wave._clear_wave()
	wave.start_next_wave()
	presentation.advance(5.0)
	wave._spawn_state.clear()
	last = spawn(wave.player.global_position + Vector3.RIGHT)
	kill(last)
	Engine.time_scale = 0.7
	presentation.advance(0.01)
	presentation.enabled = false
	check(is_equal_approx(Engine.time_scale, 0.7), "An external time owner is not overwritten on cancellation")
	Engine.time_scale = 1.0
	presentation.enabled = true
	wave._clear_wave()
	wave.start_next_wave()
	presentation.advance(5.0)
	wave._spawn_state.clear()
	last = spawn(wave.player.global_position + Vector3.RIGHT)
	last.take_damage(100000.0, {"source":&"A01"})
	check(shot.finishing and is_instance_valid(shot.get("_corpse")), "A ranged final kill also retains an actual native-frame death snapshot")
	wave.set_combat_frozen(true)
	check(not shot.active and Engine.time_scale == 1.0 and not wave.get_node("WaveHUD").presentation_active, "External freeze releases both camera and HUD ownership synchronously")
	check(experience._root.modulate == experience_color and not experience.visible, "External freeze also restores XP presentation without changing its enabled state")
	wave.set_combat_frozen(false)
	wave._clear_wave()
	wave.start_next_wave()
	presentation.advance(5.0)
	wave._spawn_state.clear()
	last = spawn(wave.player.global_position + Vector3.RIGHT)
	var charge := world.get_node("MapEffects/ChargePresentation") as ChargePresentation
	charge._time_scale.advance(0.12, true, 0.82, 0.12, 0.06)
	check(is_equal_approx(Engine.time_scale, 0.82), "An existing orbit slow-motion owner is active before the final hit")
	var saved_duration := presentation.settings.finish_shot_seconds
	presentation.settings.finish_shot_seconds = 8.0
	kill(last)
	check(shot.active, "Return-to-menu cleanup is tested during an active shot")
	check(is_equal_approx(Engine.time_scale, presentation.settings.finish_slow_scale), "Final shot cleanly takes over orbit slow motion instead of multiplying or saving a stale rate")
	check(int(wave.get("_wave_finish_deadline")) - Time.get_ticks_usec() <= 5000000, "Out-of-range duration cannot indefinitely block clear or upgrades")
	wave.reset_for_menu()
	presentation.settings.finish_shot_seconds = saved_duration
	check(not shot.active and not wave.is_wave_finish_pending() and Engine.time_scale == 1.0, "Returning to menu cannot leave a pending cinematic or slow world")
	world.free()
	for index in 3: await process_frame
	# 频繁开牌／返回会有短 UI 音源，让混音线程退休已停止的播放。
	await create_timer(0.35, true, false, true).timeout
	check(Engine.time_scale == 1.0, "Scene teardown leaves the global clock intact")
	finish()

func finish() -> void:
	print(JSON.stringify({"suite":"wave_finish_shot", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
