extends SceneTree

const RETIRED := ["S16", "S17", "S19", "S22", "S24", "S25", "S27", "S39", "S46", "S53"]
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var bank: CoreSoundBank = load("res://data/audio/core_sound_bank_world.tres")
	var shared: CoreSoundBank = load("res://data/audio/core_sound_bank.tres")
	var entries := bank.audition_entries()
	check(entries.size() == 55, "停用音源保留全部原试听编号，新受伤提示追加末尾")
	for entry in entries:
		if entry.id in RETIRED:
			check(entry.retired and entry.clip not in bank.clips_for(entry.cue), "正式池停用但保留原槽：" + entry.id)
	for cue in [&"defeat", &"slime_death", &"pot_shatter", &"kill_land"]:
		check(bank.clips_for(cue).is_empty() and not shared.clips_for(cue).is_empty(), "World 停用事件，原资源保留：" + cue)
	for pair in [[&"storm_strike", 0], [&"enemy_hit_hard", 1]]:
		check(bank.clips_for(pair[0]) == [shared.clips_for(pair[0])[pair[1]]], "保留用户未删除的变体：" + pair[0])
	var creature := bank.clips_for(&"creature_death")
	check(creature.size() == 1 and creature[0].resource_path.ends_with("kill_feedback/creature_death_thump.wav") and entries[25].clip == creature[0], "S26 普通生物死亡变体 1 替换为已选 B 厚实顿击，S27 继续停用")
	check(bank.clips_for(&"kill_slime") == shared.clips_for(&"kill_slime"), "S43 击杀确认独立于 S24／S25 旧死亡声")
	var state: SceneState = load("res://scenes/world/world.tscn").get_state()
	var selection: Resource
	for node_index in state.get_node_count():
		if state.get_node_name(node_index) != &"GameAudio": continue
		for property in state.get_node_property_count(node_index):
			if state.get_node_property_name(node_index, property) == &"sound_selection":
				selection = state.get_node_property_value(node_index, property)
	check(selection == bank, "正式地图所有技能与怪物独立入口共用同一音源选择")
	var audio := GameAudio.new()
	audio.load_local_mix = false
	var source := Node3D.new()
	root.add_child(source)
	root.add_child(audio)
	if not "sound_selection" in audio:
		check(false, "公共播放入口需要统一执行音源排除")
	else:
		audio.set("sound_selection", bank)
		for entry in entries:
			if entry.id not in RETIRED: continue
			check(audio.request({"source": source, "cue": bank.playback_cue(entry.cue), "clips": [entry.clip], "kind": GameAudio.Kind.HURT}) == null, "直接持有旧音源也不能绕过停用：" + entry.id)
		check(audio.get_debug_state().active == 0 and audio._recent.is_empty(), "已停用事件不占声道或密集合并窗口")
		var raw := shared.clips_for(&"storm_strike")
		for index in 5:
			audio.stop_all()
			var voice := audio.request({"source": source, "cue": &"ricochet_storm_start", "clips": raw})
			check(voice != null and voice.stream == raw[0], "奔雷原双变体直连池只播放首片变体 1")
		check(raw.size() == 2, "过滤不修改技能共享数组或原素材")
		audio.stop_all()
		audio.set("sound_selection", null)
		check(audio.request({"source": source, "cue": &"legacy_hurt", "clips": shared.clips_for(&"player_hurt")}) != null, "未配置选择的 City 与兼容原型保留原行为")
	var balance: CombatAudioBalance = load("res://data/audio/combat_balance_world.tres")
	check(balance.gain_db(&"prism_hit") == 2.0 and balance.gain_db(&"mirror_hit") >= 12.0, "棱晶接触降低三分贝，镜印保留旧素材补偿")
	audio.balance = balance
	var crystal: AudioStream = load("res://assets/meowa/audio/combat/hit_01.wav")
	for cue in [&"prism_hit", &"prism_bounce", &"mirror_hit", &"mirror_reflect", &"mirror_wall"]:
		audio.stop_all()
		var voice := audio.request({"source": source, "cue": cue, "clips": [crystal], "volume_db": -18.0})
		check(voice != null and is_equal_approx(voice.volume_db, -18.0 + balance.gain_db(cue)), "棱晶／镜印的实际声道接收到各自响度补偿：" + cue)
	audio.queue_free()
	source.queue_free()
	await process_frame
	print("World audio retirements: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
