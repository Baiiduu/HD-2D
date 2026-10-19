extends SceneTree

class Session extends Node:
	signal phase_changed(phase: int)
	signal combat_frozen_changed(frozen: bool)
	signal run_started
	var phase := WavePrototype.Phase.BATTLE
	var combat_frozen := false

var checks := 0
var failures := 0
var audio: GameAudio
var driver: Node
var rules: Resource
var session: Session
var bank: CoreSoundBank

func _initialize() -> void:
	create_timer(25).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func event(point := Vector3.ZERO, source: StringName = &"flight_sword") -> CombatDamageEvent:
	var hit := CombatDamageEvent.new()
	hit.world_position = point
	hit.source = source
	hit.amount = 10.0
	hit.lethal = true
	return hit

func count(cue: StringName) -> int:
	return audio._voices.filter(func(slot): return slot.active and slot.cue == cue).size()

func reset() -> void:
	driver.clear()
	audio.stop_all()
	session.phase = WavePrototype.Phase.BATTLE
	session.combat_frozen = false
	rules.enabled = true

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var script = load("res://scripts/audio/kill_feedback_audio.gd")
	var rules_script = load("res://scripts/audio/kill_audio_rules.gd")
	check(script != null and rules_script != null, "真实击杀声音驱动与独立配置存在")
	if script == null or rules_script == null:
		quit(1)
		return
	var map := Node3D.new()
	root.add_child(map)
	var player := Node3D.new()
	map.add_child(player)
	session = Session.new()
	map.add_child(session)
	audio = GameAudio.new()
	audio.load_local_mix = false
	audio.player = player
	audio.session = session
	map.add_child(audio)
	bank = CoreSoundBank.new()
	var clip := load("res://assets/meowa/audio/core_pack/slime_death_01.wav")
	for cue in [&"kill_slime", &"kill_group", &"kill_air", &"kill_land", &"creature_death"]: bank.cues[cue] = [clip]
	rules = rules_script.new()
	driver = script.new()
	driver.rules = rules
	driver.audio = audio
	driver.bank = bank
	driver.session = session
	map.add_child(driver)
	check(not driver.is_processing(), "闲置没有轮询或额外播放器")
	var hit := event(Vector3(1, 0, 0))
	hit.lethal = false
	check(not driver.record(hit, &"slime"), "非致死命中不触发死亡反馈")
	hit.lethal = true
	hit.simulated = true
	check(not driver.record(hit, &"slime"), "巨量模拟不虚构死亡或群杀")
	hit.simulated = false
	hit.source = &"A02"
	check(not driver.record(hit, &"slime"), "其它远程死亡保留原规则")
	hit.source = &"flight_sword"
	check(driver.record(hit, &"slime") and count(&"core:kill_slime") == 1, "致死瞬间立即确认，不等待群杀窗口")
	var voice: Dictionary = audio._voices.filter(func(slot): return slot.active)[0]
	check(voice.source == driver and voice.position == hit.world_position and voice.priority == 35, "音源由持久组件持有，位置固定在真实死亡点")
	player.position = Vector3(2, 0, 0)
	audio._process(0.001)
	check(voice.position == hit.world_position, "人物离开不拖走击杀音")
	player.position = Vector3.ZERO
	driver._process(0.11)
	check(count(&"core:kill_group") == 0, "单杀不附加群杀重音")
	reset()
	for index in 12: driver.record(event(Vector3(index * 0.01, 0, 0)), &"slime")
	check(count(&"core:kill_slime") == 1, "密集死亡仍共用声音预算和空间合并")
	driver._process(0.11)
	check(count(&"core:kill_group") == 1, "被合并的十二次死亡仍累积为一次群杀重音")
	var group: Dictionary = audio._voices.filter(func(slot): return slot.active and slot.cue == &"core:kill_group")[0]
	check(group.priority < GameAudio.PRIORITIES[GameAudio.Kind.DANGER] and group.voice.pitch_scale < 1.0, "大群杀有更厚音色，优先级低于危险提示")
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")) < 0.0, "只有实际播放的群杀触发短暂环境退让")
	for index in 10: driver.record(event(), &"slime")
	driver._process(0.11)
	check(count(&"core:kill_group") == 1, "连续密集死亡不连发重音")
	audio.set_charge_duck(-3.0, -4.0)
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")), -3.0), "蓄力与群杀取较强退让，避免音量重复叠压")
	driver._process(0.5)
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")), -3.0), "群杀结束保留仍在进行的蓄力退让")
	audio.set_charge_duck(0.0, 0.0)
	check(is_zero_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music"))), "环境音量完整恢复，不写本机增益")
	reset()
	for index in 3: driver.record(event(), &"slime")
	session.combat_frozen = true
	driver._process(1.0)
	check(count(&"core:kill_group") == 0, "升级冻结不推进群杀窗口")
	session.combat_frozen = false
	driver._process(0.11)
	check(count(&"core:kill_group") == 1, "恢复后只补一次尚未播放的群杀重音")
	reset()
	for index in 3: driver.record(event(), &"slime")
	session.phase = WavePrototype.Phase.REST
	session.phase_changed.emit(session.phase)
	check(count(&"core:kill_group") == 1, "最后几只清波时结算待播放的群杀，不遗失击杀反馈")
	session.phase = WavePrototype.Phase.READY
	session.phase_changed.emit(session.phase)
	check(not driver.is_processing() and audio._voices.all(func(slot): return not slot.active), "退出清理待播队列、专属声音与环境退让")
	reset()
	for index in 40: audio.death_presentation.emit(&"air", Vector3.ZERO)
	check(count(&"core:kill_air") == 1, "真实抛飞阶段事件密集合并为一个气流声")
	for index in 40: audio.death_presentation.emit(&"land", Vector3.ZERO)
	check(count(&"core:kill_land") == 1, "落地与抛飞属于不同层，保留各自一次反馈")
	check(audio.get_debug_state().active <= audio.max_voices, "所有附属声音继续服从全局通道上限")
	reset()
	rules.enabled = false
	check(not driver.record(event(), &"slime"), "配置可独立关闭，不影响原死亡链路")
	audio.death_presentation.emit(&"air", Vector3.ZERO)
	check(count(&"core:kill_air") == 0, "关闭后拒绝死亡演出声音")
	rules.enabled = true
	driver.enabled = false
	audio.death_presentation.emit(&"air", Vector3.ZERO)
	check(count(&"core:kill_air") == 0, "核心反馈关闭后不再响应尸体附属声音")
	driver.enabled = true
	driver.record(event(), &"slime")
	session.run_started.emit()
	check(not driver.is_processing() and count(&"core:kill_slime") == 0, "重试不串入上一局的声音")
	map.queue_free()
	await process_frame
	await process_frame
	print("Kill feedback audio: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
