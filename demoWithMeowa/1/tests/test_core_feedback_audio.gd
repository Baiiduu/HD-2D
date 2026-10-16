extends SceneTree

var checks := 0
var failures := 0
var world: Node3D
var wave: WavePrototype
var player: Player
var feedback: CoreFeedbackAudio
var audio: GameAudio
var ui_cues: Array[StringName] = []
const FIXTURE := preload("res://tests/fixtures/combat_scene_fixture.gd")

func _initialize() -> void:
	create_timer(70.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func settle(count := 4) -> void:
	for frame in count: await physics_frame

func playing(cue: StringName) -> bool:
	return audio._voices.any(func(slot): return slot.active and slot.cue == cue)

func reset_audio() -> void:
	audio.stop_all()
	ui_cues.clear()
	feedback._ui._last_played.clear()

func physical_bounces() -> void:
	var center := wave.battle_area.get_center()
	var origin := wave._path.ground_position(Vector3(center.x, 0, center.y)) + Vector3.UP * 0.03
	for surface in [0, 4, 5]:
		player.body_ricochet.cancel(true)
		var wall := StaticBody3D.new()
		wall.set_meta("movement_surface", surface)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.16, 2.4, 3)
		shape.shape = box
		wall.add_child(shape)
		world.add_child(wall)
		wall.global_position = origin + Vector3(1.2, 1, 0)
		player.global_position = origin
		player.set_physics_process(true)
		await settle(10)
		player.set_physics_process(false)
		reset_audio()
		check(player.body_ricochet.begin_charge(Vector3.RIGHT), "材质反弹用例可真实蓄力：%d" % surface)
		player.body_ricochet.advance(0.85, Vector3.ZERO, false)
		player.body_ricochet.release_charge()
		player.body_ricochet.advance(0.25, Vector3.ZERO, false)
		var cue := &"core:bounce_wood" if surface == 4 else (&"core:bounce_metal" if surface == 5 else &"core:bounce_stone")
		check(player.body_ricochet.bounce_count > 0 and playing(cue), "真实胶囊反弹根据碰撞材质播放对应声音：%d" % surface)
		player.body_ricochet.cancel(true)
		wall.queue_free()
		await settle()

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var bank := load("res://data/audio/core_sound_bank.tres") as CoreSoundBank
	check(bank != null and bank.cues.size() == 28, "完整音效包登记二十八种真实事件")
	var count := 0
	for cue in bank.cues:
		check(not bank.clips_for(cue).is_empty(), "事件具有成品音源：" + cue)
		for clip in bank.clips_for(cue):
			count += 1
			check(clip is AudioStreamWAV and clip.mix_rate == 48000 and not clip.stereo and clip.get_length() > 0.05, "单声道四十八千赫 WAV 可播放：" + cue)
	check(count == 41, "成品和变体合计四十一条，不包含制作源文件")
	world = load("res://scenes/world/world.tscn").instantiate()
	FIXTURE.clear_placed_obstacles(world)
	var profile := FIXTURE.isolate_profile(world)
	profile.population_rules = profile.population_rules.duplicate()
	profile.population_rules.simulation_mode = false
	profile.sword_rules = profile.sword_rules.duplicate()
	profile.sword_rules.enabled = false
	# 正式地图保持关闭拨怪；此兼容音效用例显式验证启用时的真实触发。
	profile.ricochet_rules = profile.ricochet_rules.duplicate()
	profile.ricochet_rules.enemy_push_enabled = true
	world.get_node("MapEffects/GameAudio").load_local_mix = false
	DirAccess.make_dir_recursive_absolute("D:/.codexfile/work/game-audio-mix-20261015")
	world.get_node("MapEffects/GameAudio").mix_save_path = "D:/.codexfile/work/game-audio-mix-20261015/core-test.cfg"
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	player = world.get_node("Player")
	world.get_node("Player/MovementAudio").enabled = false
	root.add_child(world)
	current_scene = world
	await settle(15)
	wave = world.get_node("WavePrototype")
	feedback = world.get_node("MapEffects/CoreFeedbackAudio")
	audio = world.get_node("MapEffects/GameAudio")
	feedback._ui.cue_played.connect(func(cue: StringName): ui_cues.append(cue))
	check(feedback.player == player and feedback.session == wave and feedback._audio == audio, "正式场景绑定实际人物与公共战斗音效池")
	check(not feedback.is_physics_processing(), "未蓄力时没有额外逐帧工作")
	check(feedback._loop_clips[0].loop_end == roundi(feedback._loop_clips[0].get_length() * feedback._loop_clips[0].mix_rate), "压缩导入后的循环终点仍按解码采样数计算")
	var skills := wave.get_node("RunSkillManager") as RunSkillManager
	var growth := wave.get_node("RunGrowth") as RunGrowth
	wave.skill_draft.initial_cards_per_draw = 100
	wave.skill_draft.initial_choice.open_duration = 0.0
	growth.choice_ui.open_duration = 0.0
	check(wave.start_run(), "真实挑战进入初始选择")
	check(ui_cues.count(&"card_reveal") == 1, "整次三选一开牌只触发一份揭晓音")
	check(wave.skill_draft.initial_choice._audio.sounds.confirm == bank.clips_for(&"growth_apply")[0], "实际成长界面使用新成功音而非叠加两个确认声")
	wave.skill_draft.initial_choice.select_option(&"initial:ricochet_storm")
	wave.skill_draft.initial_choice.confirm_selection()
	check(ui_cues.has(&"wave_start"), "确认初始技能后真实开战才播放波次提示")
	wave.set_physics_process(false)
	wave._spawn_queue.clear()
	growth.set_physics_process(false)
	player.set_physics_process(false)
	reset_audio()
	check(player.body_ricochet.begin_charge(Vector3.RIGHT), "真实人物可以开始蓄力")
	check(playing(&"core:charge_start") and playing(&"core:charge_loop"), "蓄力起手与稳定循环由现有池播放")
	audio.mix.set_clip_gain(bank.clips_for(&"charge_loop")[0].resource_path, -6.0)
	audio._process(0.0)
	var loops := audio._voices.filter(func(slot): return slot.active and slot.cue == &"core:charge_loop")
	check(loops.size() == 1 and is_equal_approx(loops[0].voice.volume_db, feedback.action_volume_db - 3.0 - 6.0), "实际蓄力循环副本使用本机单条增益")
	audio.mix.reset_all()
	wave.set_combat_frozen(true)
	await settle(2)
	check(audio._voices.filter(func(slot): return slot.active).all(func(slot): return slot.voice.stream_paused), "升级冻结同时暂停蓄力循环")
	wave.set_combat_frozen(false)
	player.body_ricochet.advance(0.9, Vector3.ZERO, false)
	feedback._physics_process(0.01)
	var played: int = audio.get_debug_state().played
	feedback._physics_process(0.3)
	check(playing(&"core:charge_ready") and audio.get_debug_state().played == played, "满蓄只提示一次，保持蓄力不反复响铃")
	check(player.body_ricochet.release_charge(), "真实发射成功")
	check(playing(&"core:launch") and not playing(&"core:charge_loop"), "发射停止蓄力循环并播放发射声")
	feedback._physics_process(0.5)
	var flight_loops := audio._voices.filter(func(slot): return slot.active and slot.cue == &"core:flight_loop")
	check(flight_loops.size() == 1 and flight_loops[0].follow_source, "飞行只保留一个跟随人物的气流循环")
	var fast_volume: float = flight_loops[0].voice.volume_db
	check(absf(fast_volume - feedback.action_volume_db - feedback.flight_gain_db) < 0.1, "达到参考速度时接近配置的气流音量")
	player.body_ricochet.flight_speed = feedback.flight_reference_speed * 0.25
	feedback._physics_process(0.5)
	check(flight_loops[0].voice.volume_db < fast_volume - 8.0, "实际余速降低会平滑减小气流音量")
	var flight_level := feedback._flight_level
	wave.set_combat_frozen(true)
	feedback._physics_process(1.0)
	# 物理追帧可能在同一进程帧完成；给独立混音线程提交新声道暂停的时间。
	await settle(2)
	await create_timer(0.05).timeout
	check(is_equal_approx(feedback._flight_level, flight_level) and flight_loops[0].voice.stream_paused, "升级冻结暂停飞行循环及其音量过渡")
	wave.set_combat_frozen(false)
	check(not flight_loops[0].voice.stream_paused, "解冻继续原循环，不叠加新的气流")
	player.body_ricochet.cancel(true)
	var fade_volume: float = flight_loops[0].voice.volume_db
	check(playing(&"core:flight_loop"), "主动取消后保留气流的淡出尾音")
	feedback._physics_process(feedback.flight_fade_out_seconds * 0.5)
	check(playing(&"core:flight_loop") and flight_loops[0].voice.volume_db < fade_volume - 5.9, "淡出过半时降低振幅而非突然截断")
	feedback._physics_process(feedback.flight_fade_out_seconds * 0.5 + 0.001)
	check(not playing(&"core:flight_loop") and not feedback.is_physics_processing(), "淡出完成释放声道并停止闲置逐帧工作")
	check(player.body_ricochet.begin_charge(Vector3.RIGHT) and player.body_ricochet.release_charge(), "快速点按同样能发射")
	player.body_ricochet.cancel(true)
	check(not playing(&"core:flight_loop"), "发射同帧取消不会遗留静音循环")
	reset_audio()
	audio.max_voices = 1
	audio.important_reserve = 0
	audio._process(0)
	feedback._body_state(PlayerRicochet.State.CHARGING)
	feedback._play_world(&"player_hurt", player.global_position, GameAudio.Kind.HURT)
	check(playing(&"core:player_hurt"), "高优先级受伤能够抢占蓄力声音")
	feedback._stop_charge()
	check(playing(&"core:player_hurt"), "结束旧循环不会误停已复用的受伤声道")
	feedback._body_state(PlayerRicochet.State.IDLE)
	audio.max_voices = 12
	audio.important_reserve = 2
	reset_audio()
	player.take_damage(5)
	check(playing(&"core:player_hurt"), "人物真实扣血发出受伤音")
	player.current_health = player.max_health * 0.24
	check(ui_cues.count(&"low_health") == 1, "首次进入濒危区提示一次")
	player.take_damage(1)
	check(ui_cues.count(&"low_health") == 1, "停留低血量不反复报警")
	player.heal(player.max_health)
	await physical_bounces()
	reset_audio()
	check(wave._spawn_enemy(), "真实怪物创建可用于反馈验证")
	var enemy := wave.enemies[-1]
	enemy.set_physics_process(false)
	enemy.spawn_delay = 0.0
	enemy.global_position = player.global_position + Vector3(1, 0, 0)
	wave._spatial_index.update(enemy)
	enemy.health = 1000
	player.body_ricochet.cancel(true)
	check(player.body_ricochet.begin_charge(Vector3.RIGHT), "拨怪音用例启动真实弹射")
	player.body_ricochet.advance(0.85, Vector3.ZERO, false)
	player.body_ricochet.release_charge()
	player.body_ricochet.advance(0.15, Vector3.ZERO, false)
	check(playing(&"core:push_stun") and enemy.stun_remaining > 0.0, "真实切线拨怪与眩晕成功后播放反馈")
	player.body_ricochet.cancel(true)
	reset_audio()
	enemy.take_damage(1, {"source":&"feedback_test"})
	check(playing(&"core:enemy_hit_soft"), "真实伤害事件连接怪物材质受击音")
	reset_audio()
	enemy.take_damage(1000)
	check(playing(&"core:slime_death"), "真实史莱姆死亡发出消散音")
	await settle()
	reset_audio()
	growth._grant_experience(10)
	check(wave.combat_frozen and ui_cues.has(&"level_up") and ui_cues.has(&"experience"), "拾取引发升级时经验和升级提示在战斗冻结中可播放")
	var rerolls := growth.rerolls_left
	growth.choice_ui.request_reroll()
	check(growth.rerolls_left == rerolls - 1 and ui_cues.has(&"reroll"), "真实成功重抽触发换牌音并只支付一次预算")
	var revealed := ui_cues.count(&"card_reveal")
	growth.choice_ui.reveal_now()
	check(ui_cues.count(&"card_reveal") == revealed, "已揭晓后重复点击不会重播开牌音")
	growth.choice_ui.select_option(growth.choice_options[0].id)
	growth.choice_ui.confirm_selection()
	check(not wave.combat_frozen, "新反馈不会改变成长确认和恢复流程")
	reset_audio()
	feedback._experience(3)
	feedback._experience(3)
	check(ui_cues.count(&"experience") <= 1, "连续经验拾取合并为有限提示")
	feedback._batch_spawned(2, player.global_position)
	check(not ui_cues.has(&"horde_arrival"), "普通小股进场不冒充怪潮")
	var started: Array[int] = []
	wave.batch_spawned.connect(func(size: int, _point: Vector3): started.append(size))
	var queued := wave._spawn_queue.size()
	check(wave.queue_spawn(wave.default_enemy, 4, 0.0, Vector3.INF, PackedStringArray(), 0.0, 0.01, 4), "通过真实队列接口建立完整怪潮数据")
	var batch: Dictionary = wave._spawn_queue[queued].batch
	for index in 4:
		check(wave._spawn_enemy(null, Vector3.INF, PackedStringArray(), 0.0, batch), "怪潮成员按实际容量和安全位置创建")
	check(started == [4], "分帧创建整批时仅第一只成功后发出一次实际入场信号")
	feedback._batch_spawned(10, player.global_position)
	check(ui_cues.count(&"horde_arrival") == 1, "密集怪潮入口同一时刻只提示一次")
	reset_audio()
	wave.wave_cleared.emit(1)
	check(ui_cues.has(&"wave_clear"), "完整清波信号触发休整提示")
	feedback.enabled = false
	feedback._play_ui(&"level_up")
	feedback._play_world(&"launch", player.global_position)
	check(ui_cues.size() == 1 and audio.get_debug_state().active == 0, "总开关停止并禁用新增声音")
	check(wave.skill_draft.initial_choice._audio.sounds.confirm != bank.clips_for(&"growth_apply")[0], "关闭核心包恢复界面原确认音")
	feedback.enabled = true
	var storm := wave.get_node("RicochetStorm") as RicochetStorm
	check(storm.hit_sounds.size() == 2 and storm.propagation_sounds.size() == 1, "雷潮分别使用首片落雷变体与后续传导音")
	reset_audio()
	for clip in storm.hit_sounds: audio.mix.set_clip_gain(clip.resource_path, -9.0)
	storm._play_patch_sound(player.global_position, 0)
	check(playing(&"ricochet_storm_start"), "首片落雷能够独立于普通命中合并播放")
	var strikes := audio._voices.filter(func(slot): return slot.active and slot.cue == &"ricochet_storm_start")
	check(strikes.size() == 1 and is_equal_approx(strikes[0].voice.volume_db, storm.hit_volume_db - 9.0), "实际奔雷触发沿用当前单条增益")
	storm._play_patch_sound(player.global_position, 1)
	var chains := audio._voices.filter(func(slot): return slot.active and slot.cue == &"ricochet_storm_chain")
	check(chains.size() == 1 and is_equal_approx(chains[0].gain_db, storm.hit_volume_db - 3.0), "后续层按片播放并减弱三分贝")
	check(load("res://data/player/basic_sword.tres").hit_sounds[0].resource_path.ends_with("combat/hit_01.wav"), "剑术仍保留现有音源")
	check(load("res://scenes/combat/light_pierce_auto_attack.tscn").get_state() != null, "其它技能资源保持可加载")
	wave._finish("Audio validation", WavePrototype.Outcome.RETREAT)
	world.queue_free()
	await settle()
	await create_timer(0.25).timeout
	print("Core feedback audio: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
