extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var scene: Node = load("res://scenes/world/world.tscn").instantiate()
	scene.get_node("LoadoutUI").save_enabled = false
	scene.get_node("WavePrototype/RunGrowth").enabled = false
	var catalog := preload("res://addons/parameter_hub/catalog.gd").new()
	var entries: Array[Dictionary] = catalog.collect(scene)
	var found := {}
	var categories := {}
	for entry in entries:
		found[entry.path + ":" + entry.property] = entry
		categories[entry.category] = true
	var required := ["VisualSample:style", "MapEffects/Camera3D:fov", "Player:blink_distance", "WavePrototype/FanAutoAttack:damage",
		"WavePrototype/RunGrowth → 规则资源:first_level_experience", "Homestead → 地表画笔列表 → brushes[0]:texture",
		"LoadoutUI/AttributeHUD:glow_strength", "WavePrototype/RunGrowth/ExperienceHUD:track_width", "MapEffects/Weather:rain_volume_db"]
	required.append("WavePrototype/WaveHUD:font_size")
	required.append("Player:crowd_clearance_distance")
	for property in ["crowd_deflection_enabled", "crowd_contact_radius", "crowd_turn_distance", "crowd_exit_outward", "crowd_speed_retention", "crowd_release_clearance"]:
		required.append("Player → 人物本体弹射规则:" + property)
	required.append("MapEffects/GameAudio:max_voices")
	required.append("MapEffects/GameAudio:merge_window")
	required.append("MapEffects/GameAudio:limiter_ceiling_db")
	for property in ["playlists", "music_transition_time", "music_enabled"]:
		required.append("MapEffects/BGM:" + property)
	required.append("MapEffects/BGM → playlists[0]:play_order")
	required.append("MapEffects/BGM → playlists[0] → tracks[0]:loop_crossfade")
	required.append("MapEffects/BGM → playlists[1] → tracks[0]:stream")
	required.append("WavePrototype:endless_mode")
	required.append("WavePrototype:endless_enemies_per_wave")
	required.append("WavePrototype:endless_max_enemies")
	required.append("WavePrototype/RunBuffs → definitions[0]:bonus_per_level")
	required.append("WavePrototype/RunBuffs → definitions[1]:bonus_cap")
	required.append("WavePrototype/RunBuffs → definitions[2]:max_level")
	for property in ["diminishing_after", "breakthrough_every", "breakthrough_multiplier", "required_levels", "extra_effects"]:
		required.append("WavePrototype/RunBuffs → definitions[0]:" + property)
	required.append("WavePrototype/RunBuffs → definitions[6] → extra_effects[0]:bonus_per_level")
	for property in ["damage", "attack_interval", "mark_duration", "reflection_limit", "match_player_pixel_density"]:
		required.append("WavePrototype/MirrorMarkAutoAttack:" + property)
	var failures: Array[String] = []
	if not is_equal_approx(scene.get_node("Player").crowd_clearance_distance, 0.12): failures.append("formal map clearance must start at 0.12 m")
	for name in required:
		if not found.has(name): failures.append(name)
	for category in catalog.CATEGORIES:
		if not categories.has(category): failures.append(category)
	if found.has("Player:crowd_clearance_distance"):
		var clearance: Dictionary = found["Player:crowd_clearance_distance"]
		if not clearance.common or clearance.category != "人物" or clearance.label != "人物周身留白距离（额外）": failures.append("personal clearance must be a common player parameter")
	if found.has("WavePrototype/FanAutoAttack:damage") and not found["WavePrototype/FanAutoAttack:damage"].common: failures.append("damage must be common")
	if found.has("WavePrototype/MirrorMarkAutoAttack:mark_duration"):
		var mirror_entry: Dictionary = found["WavePrototype/MirrorMarkAutoAttack:mark_duration"]
		if not mirror_entry.common or mirror_entry.category != "战斗与成长": failures.append("mirror values must be common combat parameters")
	if found.has("MapEffects/GameAudio:max_voices"):
		var audio_entry: Dictionary = found["MapEffects/GameAudio:max_voices"]
		if not audio_entry.common or audio_entry.category != "声音": failures.append("global voice budget must be a common sound parameter")
	if found.has("MapEffects/BGM → playlists[0] → tracks[0]:loop_crossfade"):
		var bgm_entry: Dictionary = found["MapEffects/BGM → playlists[0] → tracks[0]:loop_crossfade"]
		if not bgm_entry.common or bgm_entry.category != "声音": failures.append("track transition must be a common sound parameter")
	if found.has("WavePrototype/RunGrowth/ExperienceHUD:track_width") and not found["WavePrototype/RunGrowth/ExperienceHUD:track_width"].common: failures.append("experience width must be common")
	if found.has("WavePrototype/RunBuffs → definitions[0]:bonus_per_level"):
		var buff_entry: Dictionary = found["WavePrototype/RunBuffs → definitions[0]:bonus_per_level"]
		if not buff_entry.common or buff_entry.category != "战斗与成长": failures.append("buff values must be common combat parameters")
	print(JSON.stringify({"parameters": entries.size(), "categories": categories.keys(), "failures": failures}))
	# 在未运行的场景结构上索引，再初始化以让组件正常释放其运行时对象。
	root.add_child(scene)
	current_scene = scene
	for index in 12: await physics_frame
	catalog.entries.clear()
	for audio in scene.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	await create_timer(0.1).timeout
	await process_frame
	scene.free()
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
	quit(0 if failures.is_empty() else 1)
