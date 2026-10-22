extends SceneTree

func _initialize() -> void:
	var failures := 0
	var shared: CoreSoundBank = load("res://data/audio/core_sound_bank.tres")
	var bank := shared
	var state: SceneState = load("res://scenes/world/world.tscn").get_state()
	for index in state.get_node_count():
		if state.get_node_name(index) != &"CoreFeedbackAudio": continue
		for property in state.get_node_property_count(index):
			if state.get_node_property_name(index, property) == &"sounds":
				bank = state.get_node_property_value(index, property)
	var launches := bank.clips_for(&"launch")
	if launches.size() != 1 or launches[0] != shared.clips_for(&"launch")[1]:
		push_error("World 发射只使用用户认可的原变体 2")
		failures += 1
	if bank.clips_for(&"charge_ready")[0].resource_path != "res://assets/meowa/audio/core_pack/charge_ready_gathering.wav":
		push_error("World 满蓄采用用户认可的聚气收束音源")
		failures += 1
	var entries := bank.audition_entries()
	if entries.size() != 55 or entries[3].id != "S04" or entries[4].id != "S05" or entries[53].id != "S54" or entries[54].id != "S55":
		push_error("停用单个变体保留原试听编号")
		failures += 1
	if not entries[3].get("retired", false) or entries[4].get("retired", true):
		push_error("试听将变体 1 标记停用，变体 2 保持有效")
		failures += 1
	if shared.clips_for(&"launch").size() != 2 or shared.clips_for(&"charge_ready")[0].resource_path.contains("gathering"):
		push_error("World 选择不覆盖 City 共用默认音源")
		failures += 1
	if bank.clips_for(&"wave_start") != shared.clips_for(&"wave_start"):
		push_error("World 音源选择保留其它声音")
		failures += 1
	var bounce_hashes: Array[String] = []
	for cue in [&"bounce_stone", &"bounce_wood", &"bounce_metal"]:
		var clips := bank.clips_for(cue)
		if clips.size() != 1:
			push_error("每种材质固定使用一条独立本体反弹音：" + cue)
			failures += 1
			continue
		bounce_hashes.append(FileAccess.get_sha256(clips[0].resource_path))
	if bounce_hashes.size() != 3 or bounce_hashes[0] == bounce_hashes[1] or bounce_hashes[0] == bounce_hashes[2] or bounce_hashes[1] == bounce_hashes[2]:
		push_error("石／木／金属不复用相同反弹声音内容")
		failures += 1
	print("World audio selection: %d failures" % failures)
	quit(1 if failures else 0)
