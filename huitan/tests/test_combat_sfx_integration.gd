extends "res://tests/test_aim_path_preview.gd"

const AUDIO_ROOT := "res://assets/meowa/audio/combat_actions/"

func target_checks() -> void:
	pass

func overrides(path: String) -> Dictionary:
	var state: SceneState = load("res://scenes/world/world.tscn").get_state()
	var values := {}
	for node in state.get_node_count():
		if state.get_node_name(node) != StringName(path.get_file()): continue
		for property in state.get_node_property_count(node):
			values[state.get_node_property_name(node, property)] = state.get_node_property_value(node, property)
	return values

func path_checks() -> void:
	AudioServer.set_bus_mute(0, true)
	var bank: CoreSoundBank = load("res://data/audio/core_sound_bank_world.tres")
	var hurt_clips := bank.clips_for(&"player_hurt")
	var hurt_notice: AudioStream = load(AUDIO_ROOT + "player_hurt_notice.wav")
	var rules: PlayerSwordRules = load("res://data/combat/scenes/world/player/basic_sword.tres")
	var values := overrides("WavePrototype/PrismRicochetAutoAttack")
	check(hurt_clips.is_empty(), "World 关闭全部人物受击声音，包括新旧提示音")
	check(rules.sweep_sounds == bank.clips_for(&"enemy_hit_common"), "World 空挥与真实命中共用 S47–S49 音色")
	check(values.has("hit_sounds") and values.has("bounce_sounds"), "World 独立覆盖棱晶接触音源")
	var entries := bank.audition_entries()
	check(entries[15].id == "S16" and entries[15].retired and entries[16].retired, "旧人物受伤槽保持停用")
	var hurt_entries := entries.filter(func(entry): return entry.clip == hurt_notice)
	check(hurt_entries.size() == 1 and hurt_entries[0].retired, "新受伤素材保留对照，但不再进入实战池")
	if rules.sweep_sounds.is_empty() or not values.has("hit_sounds"): return
	var audio := GameAudio.new()
	audio.player = player
	audio.session = session
	audio.load_local_mix = false
	audio.balance = load("res://data/audio/combat_balance_world.tres")
	audio.sound_selection = bank
	world.add_child(audio)
	player.sword.rules = rules.duplicate()
	player.sword._audio = audio
	player.sword._play_sound(false, player.global_position)
	var swing := audio._voices.filter(func(slot): return slot.active and slot.cue == &"basic_sword_swing")
	check(swing.size() == 1 and swing[0].voice.stream in bank.clips_for(&"enemy_hit_common"), "空挥也播放通用命中音色，不要求命中怪物")
	var hurt := audio.request({"source":player, "cue":&"core:player_hurt", "clips":[hurt_notice], "kind":GameAudio.Kind.HURT, "position":player.global_position, "volume_db":-6.0})
	check(hurt == null and not audio._voices.any(func(slot): return slot.active and slot.cue == &"core:player_hurt"), "直接持有新受伤素材也不能绕过地图停用")
	check(not swing.is_empty() and swing[0].voice.playing, "停用受伤提示不影响当前挥剑声")
	audio.stop_all()
	session._path = navigation
	session._path_ready = true
	player.sword.rules.enabled = false
	var prism: PrismRicochetAutoAttack = load("res://scenes/combat/prism_ricochet_auto_attack.tscn").instantiate()
	for property in values: prism.set(property, values[property])
	prism.session = session
	prism.audio_manager = audio
	world.add_child(prism)
	prism.apply_skill_level(1)
	prism.set_physics_process(false)
	var front := enemy(Vector3(2, 0, 0))
	front.health = 1000
	await settle()
	# 普通身体受击已占用原合并组，棱晶的独立接触声仍须可辨。
	audio.request({"source":player, "cue":&"core:enemy_hit_soft", "clips":bank.clips_for(&"enemy_hit_soft"), "kind":GameAudio.Kind.HIT, "position":front.global_position})
	prism.launch(Vector3.ZERO, Vector3.RIGHT, prism.get_attack_stats())
	prism._advance_shot(prism._shots[-1], 0.25)
	var contacts := audio._voices.filter(func(slot): return slot.active and slot.cue in [&"prism_hit", &"prism_bounce"])
	check(contacts.size() == 1 and contacts[0].cue == &"prism_hit" and contacts[0].voice.stream.resource_path == AUDIO_ROOT + "prism_contact.wav", "真实怪物接触只响一条新棱晶音，不叠反弹声")
	if not contacts.is_empty(): check(absf(contacts[0].voice.pitch_scale - 1.0) <= 0.02, "正式棱晶保留试听音色，不沿用旧大幅升调")
	prism.cancel_current()
	audio.stop_all()
	session.combat_modifiers.damage_disabled = true
	front.health_loss_disabled = true
	var previous_health := front.health
	prism.launch(Vector3.ZERO, Vector3.RIGHT, prism.get_attack_stats())
	prism._advance_shot(prism._shots[-1], 0.25)
	contacts = audio._voices.filter(func(slot): return slot.active and slot.cue in [&"prism_hit", &"prism_bounce"])
	check(front.health == previous_health and contacts.size() == 1 and contacts[0].cue == &"prism_hit", "免伤模拟命中怪物也只响一条接触声，不额外叠加反弹音")
	session.combat_modifiers.damage_disabled = false
	prism.cancel_current()
	clear_enemies()
	audio.stop_all()
	var wall := box(Vector3(2, 0.6, 0), Vector3(0.05, 1.2, 6))
	await settle()
	prism.launch(Vector3.ZERO, Vector3.RIGHT, prism.get_attack_stats())
	prism._advance_shot(prism._shots[-1], 0.25)
	contacts = audio._voices.filter(func(slot): return slot.active and slot.cue == &"prism_bounce")
	check(contacts.size() == 1 and contacts[0].voice.stream.resource_path == AUDIO_ROOT + "prism_contact.wav", "真实碰墙仍使用新棱晶接触音")
	wall.queue_free()
	var shared: PrismRicochetAutoAttack = load("res://scenes/combat/prism_ricochet_auto_attack.tscn").instantiate()
	check(shared.hit_sounds[0].resource_path.ends_with("combat/hit_01.wav"), "City 与共享技能保留原声音")
	shared.free()
