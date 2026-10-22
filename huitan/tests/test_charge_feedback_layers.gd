extends SceneTree

const SESSION := preload("res://tests/fixtures/ricochet_session.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(25.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var visuals := PlayerActionVisuals.new()
	if not "charge_dynamic_enabled" in visuals:
		check(false, "蓄力需要可独立启用的渐强视觉配置")
		quit(1)
		return
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(30, 0.2, 30)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	floor_body.position.y = -0.1
	var session := SESSION.new()
	session.name = "WavePrototype"
	session.phase = WavePrototype.Phase.BATTLE
	world.add_child(session)
	var player := Player.new()
	player.animations = load("res://assets/meowa/player/animations.tres")
	player.ricochet_rules = PlayerRicochetRules.new()
	player.ricochet_rules.full_charge_seconds = 0.5
	visuals.set("charge_dynamic_enabled", true)
	visuals.coalesce_charge_preview = true
	visuals.show_aim_guide = false
	player.action_visuals = visuals
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.position.y = 0.75
	player.add_child(sprite)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 1.0
	shape.shape = capsule
	shape.position.y = 0.5
	player.add_child(shape)
	session.player = player
	world.add_child(player)
	var audio := GameAudio.new()
	audio.player = player
	audio.session = session
	audio.load_local_mix = false
	world.add_child(audio)
	var feedback: CoreFeedbackAudio = load("res://scenes/audio/core_feedback_audio.tscn").instantiate()
	feedback.player = player
	feedback.session = session
	feedback.set("charge_progress_audio_enabled", true)
	world.add_child(feedback)
	for frame in 12: await physics_frame
	player.set_physics_process(false)
	var body := player.body_ricochet
	check(body.begin_charge(Vector3.RIGHT), "真实人物开始蓄力")
	var effect := body._charge_effect
	# 正式地图合并到一次显示更新；无界面用例手动提交这一帧。
	effect._process(0.0)
	check(effect._motes.multimesh.instance_count == int(visuals.get("charge_mote_count")), "渐强效果复用可调数量的光点")
	var initial_radius: float = effect._ring_material.get_shader_parameter("radius_pixels")
	var initial_energy: float = effect._ring_material.get_shader_parameter("energy")
	feedback._physics_process(0.0)
	var loops := audio._voices.filter(func(slot): return slot.active and slot.cue == &"core:charge_loop")
	check(loops.size() == 1, "蓄力始终只使用一个循环声道")
	var voice: AudioStreamPlayer3D = loops[0].voice
	var start_volume := voice.volume_db
	var start_pitch := voice.pitch_scale
	body.advance(0.25, Vector3.ZERO, false)
	var phase_before: float = effect.get("_mote_phase")
	effect._sync_visuals(0.1)
	var mid_travel: float = effect.get("_mote_phase") - phase_before
	feedback._physics_process(0.1)
	var mid_radius: float = effect._ring_material.get_shader_parameter("radius_pixels")
	check(mid_radius < initial_radius, "蓄力过程中圆弧向人物收紧")
	check(voice.volume_db > start_volume and voice.pitch_scale > start_pitch, "蓄力循环声随真实进度渐强升调")
	body.advance(0.25, Vector3.ZERO, false)
	phase_before = effect.get("_mote_phase")
	effect._sync_visuals(0.1)
	var full_travel: float = effect.get("_mote_phase") - phase_before
	feedback._physics_process(0.1)
	check(full_travel > mid_travel, "越接近满蓄光点汇聚越快")
	check(float(effect._ring_material.get_shader_parameter("radius_pixels")) < mid_radius, "满蓄圆弧比半蓄更贴身")
	check(float(effect._ring_material.get_shader_parameter("energy")) > initial_energy, "贴身暖光随蓄力增强")
	check(is_equal_approx(voice.volume_db, float(feedback.call("_charge_volume", 1.0)) + audio.cue_gain_db(&"core:charge_loop")) and is_equal_approx(voice.pitch_scale, feedback.call("_charge_pitch", 1.0)), "满蓄音量叠加地图平衡，音高达到配置端点")
	var played: int = audio.get_debug_state().played
	for frame in 4: feedback._physics_process(0.1)
	check(audio.get_debug_state().played == played, "保持满蓄不叠加循环或重复提示音")
	var phase: float = effect.get("_mote_phase")
	var gain := voice.volume_db
	effect.set_process(false)
	session.set_combat_frozen(true)
	effect._sync_visuals(0.3)
	feedback._physics_process(0.3)
	await create_timer(0.06).timeout
	check(effect.get("_mote_phase") == phase and voice.volume_db == gain and voice.stream_paused, "升级冻结保持汇聚节奏与循环声音")
	session.set_combat_frozen(false)
	feedback.set_physics_process(false)
	audio.stop_all()
	var hurt := audio.request({"source":player, "cue":&"core:player_hurt", "clips":feedback.sounds.clips_for(&"player_hurt"), "kind":GameAudio.Kind.HURT, "position":player.global_position, "volume_db":-8.0})
	audio.max_voices = 1
	feedback._physics_process(0.2)
	check(hurt.playing and is_equal_approx(hurt.pitch_scale, 1.0) and is_equal_approx(hurt.volume_db, -8.0 + audio.cue_gain_db(&"core:player_hurt")), "渐强更新不能修改已被受伤反馈占用的声音")
	audio.stop_all()
	feedback._physics_process(0.2)
	check(audio._voices.any(func(slot): return slot.active and slot.cue == &"core:charge_loop"), "循环被抢占后在仍蓄力时有限重试恢复")
	check(body.release_charge() and not effect.visible, "发射立即结束蓄力特效并交回已有飞行表现")
	check(not audio._voices.any(func(slot): return slot.active and slot.cue == &"core:charge_loop"), "发射停止渐强蓄力循环")
	body.cancel(true)
	audio.stop_all()
	audio.max_voices = 12
	check(body.begin_charge(Vector3.RIGHT), "重新蓄力可恢复渐强反馈")
	body.advance(0.5, Vector3.ZERO, false)
	body.release_charge()
	check(audio._voices.any(func(slot): return slot.active and slot.cue == &"core:charge_ready"), "刚满即松手仍保留一次满蓄提示，不依赖额外物理采样")
	body.cancel(true)
	visuals.charge_dynamic_enabled = false
	feedback.charge_progress_audio_enabled = false
	check(body.begin_charge(Vector3.RIGHT), "关闭渐强后可沿用原始蓄力")
	effect._sync_visuals(0.1)
	check(effect._motes.multimesh.instance_count == 10 and is_equal_approx(effect._ring_material.get_shader_parameter("radius_pixels"), visuals.charge_radius_pixels), "关闭渐强保留原来的十枚光点与固定圆弧半径")
	check(is_equal_approx(feedback._charge_volume(1.0), feedback.action_volume_db - 3.0) and is_equal_approx(feedback._charge_pitch(1.0), 1.0), "关闭声音渐强保留原音量和音高")
	body.cancel(true)
	var profile := load("res://data/combat/scenes/world/configuration.tres") as SceneCombatConfiguration
	var city := load("res://data/combat/scenes/city/configuration.tres") as SceneCombatConfiguration
	check(profile.action_visuals.get("charge_dynamic_enabled") == true and city.action_visuals.get("charge_dynamic_enabled") == false, "仅 World 独立启用渐强视觉")
	world.queue_free()
	for frame in 4: await process_frame
	print("Charge feedback layers: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
