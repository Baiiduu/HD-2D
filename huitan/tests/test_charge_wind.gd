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

func wind_slots(audio: GameAudio) -> Array:
	return audio._voices.filter(func(slot): return slot.active and slot.cue == &"core:charge_wind")

func funnel_checks(wind: PlayerChargeWind, visuals: PlayerActionVisuals, formal: PlayerActionVisuals, city: PlayerActionVisuals) -> void:
	if not "charge_wind_funnel_enabled" in visuals:
		check(false, "已确认的下窄上宽风旋需要独立漏斗形配置")
		return
	check(formal.get("charge_wind_funnel_enabled") and not city.get("charge_wind_funnel_enabled"), "仅 World 采用已确认的漏斗形风旋")
	check(formal.charge_wind_opacity <= 0.4, "World 风带默认保持通透")
	visuals.charge_wind_enabled = true
	visuals.set("charge_wind_funnel_enabled", true)
	visuals.charge_wind_radius_pixels = 32.0
	visuals.set("charge_wind_bottom_radius_pixels", 6.0)
	visuals.charge_wind_height_pixels = 64.0
	visuals.set("charge_wind_width_pixels", 8.0)
	visuals.set("charge_wind_turns", 2.25)
	visuals.set("charge_wind_full_speed_multiplier", 2.0)
	visuals.charge_wind_opacity = 0.30
	visuals.charge_wind_cycle_seconds = 1.0
	var material: ShaderMaterial = wind.get("_material")
	var batch: MultiMeshInstance3D = wind.get("_wisps")
	var mesh_id := batch.multimesh.mesh.get_instance_id()
	var material_id := material.get_instance_id()
	var texture_id := visuals.charge_wind_texture.get_instance_id()
	wind.stop()
	wind.synchronize(visuals, 0.016, 0.0, 0.1)
	var start_phase: float = wind.get("_phase")
	var start_radius: float = material.get_shader_parameter("radius")
	wind.stop()
	wind.synchronize(visuals, 0.016, 1.0, 0.1)
	check(float(wind.get("_phase")) > start_phase * 2.0, "蓄力主要加强风速")
	check(material.get_shader_parameter("funnel_enabled") == true, "实际材质启用漏斗形轨迹")
	check(is_equal_approx(float(material.get_shader_parameter("radius")), start_radius), "起手和满蓄保持同一紧凑外沿")
	check(is_equal_approx(float(material.get_shader_parameter("bottom_radius")), 6.0 * 0.016) and float(material.get_shader_parameter("bottom_radius")) < start_radius, "实际材质的脚边半径小于上沿半径")
	check(is_equal_approx(float(material.get_shader_parameter("height")), 64.0 * 0.016) and is_equal_approx(float(material.get_shader_parameter("turns")), 2.25), "高度与螺旋圈数接入实际材质")
	check(is_equal_approx(float(material.get_shader_parameter("width")), 8.0 * 0.016), "风带厚度独立按人物原生像素计量")
	check(is_equal_approx(float(material.get_shader_parameter("opacity")), 0.30 * visuals.charge_effect_opacity), "风旋不透明度独立叠加原有总透明度")
	check(material.get_shader_parameter("airflow_texture").get_instance_id() == texture_id, "直接使用 Meowa 原纹理，不重采样素材")
	var phase: float = wind.get("_phase")
	visuals.charge_wind_opacity = 0.15
	visuals.set("charge_wind_bottom_radius_pixels", 9.0)
	visuals.set("charge_wind_width_pixels", 16.0)
	wind.synchronize(visuals, 0.016, 1.0, 0.0)
	check(is_equal_approx(float(wind.get("_phase")), phase) and is_equal_approx(float(material.get_shader_parameter("opacity")), 0.15 * visuals.charge_effect_opacity), "调不透明度不重启动画或创建新材质")
	check(is_equal_approx(float(material.get_shader_parameter("bottom_radius")), 9.0 * 0.016), "下沿宽度可实时调整")
	var extent := (32.0 + 8.0) * 0.016
	check(batch.custom_aabb.has_point(Vector3(extent, 64.0 * 0.016, 0.0)) and batch.custom_aabb.has_point(Vector3(0.0, -8.0 * 0.016, -extent)), "风带加宽后包围盒仍完整包含顶部及底部")
	visuals.set("charge_wind_bottom_radius_pixels", 80.0)
	wind.synchronize(visuals, 0.016, 1.0, 0.0)
	check(float(material.get_shader_parameter("bottom_radius")) <= float(material.get_shader_parameter("radius")), "误将下沿调得过宽时仍保留下窄上宽约束")
	check(batch.multimesh.mesh.get_instance_id() == mesh_id and material.get_instance_id() == material_id, "参数调整复用原网格与材质")
	wind.stop()
	check(not wind.visible and is_zero_approx(float(wind.get("_phase"))), "漏斗形风旋停止后隐藏并清理相位")
	visuals.set("charge_wind_funnel_enabled", false)
	visuals.set("charge_wind_full_speed_multiplier", 1.45)
	wind.synchronize(visuals, 0.016, 0.5, 0.05)
	check(material.get_shader_parameter("funnel_enabled") == false, "关闭漏斗形模式保留旧螺旋对照")
	wind.stop()

func density_checks(wind: PlayerChargeWind, visuals: PlayerActionVisuals, formal: PlayerActionVisuals, city: PlayerActionVisuals) -> void:
	if not "charge_wind_layers" in visuals:
		check(false, "人物风场需要可调的风带层数与延伸长度")
		return
	check(int(formal.get("charge_wind_layers")) >= 3 and int(city.get("charge_wind_layers")) == 1, "World 加密人物风场，City 保留原层数")
	visuals.charge_wind_enabled = true
	visuals.charge_wind_funnel_enabled = true
	visuals.set("charge_wind_layers", 1)
	wind.synchronize(visuals, 0.016, 1.0, 0.1)
	var batch: MultiMeshInstance3D = wind.get("_wisps")
	var material: ShaderMaterial = wind.get("_material")
	var mesh_id := batch.multimesh.mesh.get_instance_id()
	var batch_id := batch.multimesh.get_instance_id()
	var material_id := material.get_instance_id()
	var phase: float = wind.get("_phase")
	visuals.set("charge_wind_layers", 3)
	visuals.set("charge_wind_trail_span", 0.26)
	wind.synchronize(visuals, 0.016, 1.0, 0.0)
	check(batch.multimesh.instance_count == PlayerChargeWind.WISP_COUNT * 3, "三个风层共同包围人物")
	# Dummy renderer does not retain MultiMesh custom data; validate the actual
	# layer parameters submitted by _set_layers, without a rendered readback.
	var outer := PlayerChargeWind.layer_parameters(0, 3)
	var middle := PlayerChargeWind.layer_parameters(1, 3)
	var inner := PlayerChargeWind.layer_parameters(2, 3)
	check(outer.x != middle.x and middle.x != inner.x, "各层错开旋转方位，形成包围体而非重叠同一条线")
	check(outer.y > middle.y and middle.y > inner.y and inner.y > 0.0, "内外风层具有真实厚度，外沿范围保持不变")
	check(outer.z > middle.z and middle.z > inner.z and inner.z > 0.0, "内层逐渐降低不透明度，保留人物可读性")
	check(is_equal_approx(float(material.get_shader_parameter("trail_span")), 0.26), "长风带接入实际材质，减少零散短风痕")
	check(is_equal_approx(float(wind.get("_phase")), phase), "调密度不重启旋转相位")
	wind.synchronize(visuals, 0.016, 1.0, 0.05)
	check(batch.multimesh.mesh.get_instance_id() == mesh_id and batch.multimesh.get_instance_id() == batch_id and material.get_instance_id() == material_id, "加密后仍复用同一批次、网格与材质")
	visuals.charge_wind_funnel_enabled = false
	wind.synchronize(visuals, 0.016, 1.0, 0.0)
	check(batch.multimesh.instance_count == PlayerChargeWind.WISP_COUNT, "旧风流模式不受新风场层数影响")
	wind.stop()

func outline_checks(wind: PlayerChargeWind, source: Sprite3D, formal: PlayerActionVisuals, city: PlayerActionVisuals) -> void:
	if not "charge_wind_body_clearance_pixels" in formal:
		check(false, "风场需要保护人物实际轮廓并留出可调间隙")
		return
	var gap := float(formal.get("charge_wind_body_clearance_pixels"))
	check(gap > 0.0 and float(city.get("charge_wind_body_clearance_pixels")) == 0.0, "仅 World 启用风场轮廓留白")
	var movement: SpriteFrames = load("res://data/combat/scenes/world/player/character_movement.tres")
	var half_width := 0.0
	for index in movement.get_frame_count(&"idle"):
		var texture := movement.get_frame_texture(&"idle", index)
		var rect := texture.get_image().get_used_rect()
		half_width = maxf(half_width, maxf(absf(rect.position.x - texture.get_width() * 0.5), absf(rect.end.x - texture.get_width() * 0.5)))
	var inner_scale := PlayerChargeWind.layer_parameters(formal.charge_wind_layers - 1, formal.charge_wind_layers).y
	var clear_radius := formal.charge_wind_bottom_radius_pixels * inner_scale - formal.charge_wind_width_pixels * 0.5
	check(clear_radius >= half_width + gap, "最内层风带的内缘仍在当前人物待机轮廓之外")
	check(formal.charge_wind_radius_pixels > formal.charge_wind_bottom_radius_pixels, "扩大后的风场仍保持下窄上宽")
	wind.synchronize(formal, 0.016, 1.0, 0.1)
	var material: ShaderMaterial = wind.get("_material")
	var phase: float = wind.get("_phase")
	wind.call("sync_body_mask", source, gap)
	check(is_equal_approx(float(material.get_shader_parameter("body_mask_margin_pixels")), gap), "轮廓间隙提交到实际风场材质")
	check(is_equal_approx(float(wind.get("_phase")), phase), "同步人物实际帧不重启风场相位")
	wind.call("sync_body_mask", source, 0.0)
	check(material.get_shader_parameter("body_mask_enabled") == false, "间隙设为零可以独立关闭轮廓保护")
	wind.stop()

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var visuals := PlayerActionVisuals.new()
	if not "charge_wind_enabled" in visuals:
		check(false, "蓄力需要独立的绕身聚力风配置")
		quit(1)
		return
	visuals.set("charge_wind_enabled", true)
	visuals.set("charge_wind_texture", load("res://assets/meowa/combat/body_rebound/departure_airflow.png"))
	visuals.show_aim_guide = false
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(30.0, 0.2, 30.0)
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
	feedback.set("charge_wind_audio_enabled", true)
	world.add_child(feedback)
	for frame in 10: await physics_frame
	player.set_physics_process(false)
	feedback.set_physics_process(false)
	var body := player.body_ricochet
	check(body.begin_charge(Vector3.RIGHT), "开始真实蓄力")
	var effect := body._charge_effect
	effect.set_process(false)
	effect._sync_visuals(0.1)
	feedback._physics_process(0.1)
	var wind = effect.get("_wind")
	check(wind != null and wind.visible, "聚力风随真实蓄力出现")
	check(wind_slots(audio).size() == 1, "聚力风复用一个公共池循环声道")
	if wind == null or wind_slots(audio).is_empty():
		world.queue_free()
		quit(1)
		return
	var mesh_id: int = wind.get("_wisps").get_instance_id()
	var voice: AudioStreamPlayer3D = wind_slots(audio)[0].voice
	var start_gain := voice.volume_db
	body.advance(0.5, Vector3.ZERO, false)
	effect._sync_visuals(0.1)
	feedback._physics_process(0.1)
	check(voice.volume_db > start_gain, "聚力风声随真实蓄力增强")
	var played: int = audio.get_debug_state().played
	var full_gain := voice.volume_db
	var phase: float = wind.get("_phase")
	for frame in 6:
		effect._sync_visuals(0.1)
		feedback._physics_process(0.1)
	check(audio.get_debug_state().played == played and wind_slots(audio).size() == 1, "满蓄持续保持，不重复叠音")
	check(is_equal_approx(voice.volume_db, full_gain) and not is_equal_approx(float(wind.get("_phase")), phase), "满蓄风声稳定，气流保持旋转")
	phase = wind.get("_phase")
	session.set_combat_frozen(true)
	effect._sync_visuals(0.3)
	feedback._physics_process(0.3)
	await create_timer(0.06).timeout
	check(is_equal_approx(float(wind.get("_phase")), phase) and voice.stream_paused, "升级冻结同步暂停风流与风声：phase %f → %f，paused %s" % [phase, float(wind.get("_phase")), voice.stream_paused])
	session.set_combat_frozen(false)
	check(body.release_charge(), "风流不延迟实际发射")
	check(not wind.is_visible_in_tree(), "发射立即撤去绕身气流")
	feedback._physics_process(0.2)
	check(wind_slots(audio).is_empty(), "风声短淡出后交回原发射与飞行声音")
	body.cancel(true)
	audio.stop_all()
	check(body.begin_charge(Vector3.RIGHT), "重新蓄力")
	effect._sync_visuals(0.1)
	feedback._physics_process(0.1)
	check(wind.get("_wisps").get_instance_id() == mesh_id, "重复蓄力复用原气流网格")
	body.cancel(true)
	check(body.begin_charge(Vector3.RIGHT), "淡出中快速重按")
	feedback._physics_process(0.1)
	check(wind_slots(audio).size() == 1, "快速重按接住现有风声，不增加声道：%s，level %f，retry %f" % [audio.get_debug_state(), feedback.get("_charge_wind_level"), feedback.get("_charge_wind_retry")])
	audio.stop_all()
	audio.max_voices = 1
	var hurt := audio.request({"source":player, "cue":&"core:player_hurt", "clips":feedback.sounds.clips_for(&"player_hurt"), "kind":GameAudio.Kind.HURT, "volume_db":-8.0})
	feedback._physics_process(0.3)
	check(hurt.playing and is_equal_approx(hurt.volume_db, -8.0), "风声更新不修改已被受伤声抢占的声道")
	audio.stop_all()
	feedback._physics_process(0.3)
	check(wind_slots(audio).size() == 1, "被抢占后仅在蓄力中有限重试")
	feedback._phase_changed(WavePrototype.Phase.READY)
	check(wind_slots(audio).is_empty(), "离开战斗立即清除聚力风声，不保留循环尾音")
	audio.max_voices = 12
	feedback._physics_process(0.3)
	feedback.set("charge_wind_audio_enabled", false)
	visuals.set("charge_wind_enabled", false)
	effect._sync_visuals(0.1)
	check(wind_slots(audio).is_empty() and not wind.visible, "独立关闭后立即停止，无闲置循环")
	body.cancel(true)
	var formal := load("res://data/combat/scenes/world/player/action_visuals.tres") as PlayerActionVisuals
	var city := load("res://data/combat/scenes/city/player/action_visuals.tres") as PlayerActionVisuals
	check(formal.get("charge_wind_enabled") == true and city.get("charge_wind_enabled") == false, "仅正式 World 开启聚力风")
	funnel_checks(wind, visuals, formal, city)
	density_checks(wind, visuals, formal, city)
	outline_checks(wind, player.sprite, formal, city)
	var bank := feedback.sounds
	var entries := bank.audition_entries()
	check(entries[-1].cue == &"charge_wind" and entries.filter(func(entry): return entry.id == "S41")[0].cue == &"flight_loop", "聚力风追加试听末尾，保留原 S41")
	world.queue_free()
	for frame in 4:
		await physics_frame
		await process_frame
	print("Charge wind: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
