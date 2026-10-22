extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func frames(name: StringName, count := 8) -> SpriteFrames:
	var result := SpriteFrames.new()
	result.remove_animation(&"default")
	result.add_animation(name)
	result.set_animation_speed(name, 10.0)
	var original := load("res://assets/meowa/player/animations.tres") as SpriteFrames
	for index in count: result.add_frame(name, original.get_frame_texture(&"run", index % 8))
	return result

func animator_checks() -> void:
	# Only exercise animation state/selection; no physics or render window.
	var player := Player.new()
	player.sprite = Sprite3D.new()
	player.add_child(player.sprite)
	var animator := PlayerActionAnimator.new()
	animator.player = player
	animator.visuals = PlayerActionVisuals.new()
	animator.visuals.flight = frames(&"default")
	animator.set_context(&"flight", Vector3.RIGHT)
	animator.render(0.2)
	animator.request_attack(&"flight_attack", Vector3.LEFT)
	check(animator.render(0.1) and player.sprite.texture == animator.visuals.flight.get_frame_texture(&"default", 3), "空飞行攻击槽继续当前滑行循环，不回待机或重启循环")
	animator.visuals.normal_attack = frames(&"default")
	if animator.has_method("play_attack"):
		animator.call("play_attack", &"normal_attack", Vector3.LEFT, 0.2)
		animator.render(0.151)
		check(player.sprite.texture == animator.visuals.normal_attack.get_frame_texture(&"default", 6) and player.sprite.flip_h, "完整普攻帧按真实攻击时长播放并保持左右镜像")
		animator.call("play_attack", &"normal_attack", Vector3.RIGHT, 0.1)
		animator.render(0.05)
		check(player.sprite.texture == animator.visuals.normal_attack.get_frame_texture(&"default", 4) and not player.sprite.flip_h, "下一次真实出剑能接管显示，旧动画不限制攻击频率")
		var texture := player.sprite.texture
		animator.render(0.0)
		check(player.sprite.texture == texture, "战斗冻结时保持实际攻击帧")
	else: check(false, "人物动画须能消费真实剑术时长")
	if animator.has_method("request_bounce"):
		animator.cancel_attack()
		check(not bool(animator.call("request_bounce", Vector3.LEFT)), "空反弹槽不打断现有滑行显示")
		animator.visuals.set("bounce", frames(&"default"))
		check(bool(animator.call("request_bounce", Vector3.LEFT)), "预留反弹素材可独立触发显示")
		animator.render(0.1)
		check(player.sprite.flip_h, "反弹显示跟随出射方向")
		var bounce_age := animator._attack_age
		animator.play_attack(&"flight_attack", Vector3.RIGHT, 0.2)
		check(animator._attack == &"bounce" and animator._attack_heading == Vector3.LEFT and is_equal_approx(animator._attack_age, bounce_age), "真实剑术继续结算时不覆盖尚未播完的反弹动作")
		animator.render(0.0)
		check(is_equal_approx(animator._attack_age, bounce_age), "战斗冻结不推进反弹动作")
		animator.render(0.71)
		check(animator._attack.is_empty() and animator.render(0.0), "反弹单次播完后继续原滑行循环")
		animator.request_bounce(Vector3.RIGHT)
		animator.render(0.1)
		animator.request_bounce(Vector3.LEFT)
		check(is_zero_approx(animator._attack_age) and animator._attack_heading == Vector3.LEFT, "连续真实碰墙从首帧响应新的出射方向")
		animator.cancel_attack()
		check(animator._attack.is_empty(), "取消弹射同时清理反弹动作")
		animator.visuals.bounce = frames(&"side")
		for heading in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3(-0.2, 0, -1).normalized(), Vector3(0.2, 0, 1).normalized()]:
			check(animator.request_bounce(heading), "所有出射方向复用侧向反弹素材：" + str(heading))
			animator.render(0.0)
			check(player.sprite.texture == animator.visuals.bounce.get_frame_texture(&"side", 0) and player.sprite.flip_h == (heading.x < 0.0), "复用相同首帧，仅按屏幕左右分量镜像")
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.rotation.y = PI * 0.5
		player.movement_camera = camera
		for heading in [Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT, Vector3.LEFT]:
			check(animator.request_bounce(heading), "旋转镜头后各方向仍能播放同一反弹素材")
			animator.render(0.0)
			check(player.sprite.flip_h == (heading == Vector3.BACK), "镜像以当前镜头为准，纯上下不因浮点余量翻转")
		camera.free()
		player.movement_camera = null
	else: check(false, "人物动画须预留真实反弹接口")
	player.free()

func quiet(scene: Node) -> void:
	for path in ["WorldEntry", "WorldMainMenu", "LoadoutUI", "GameSettingsUI", "MapEffects/BGM", "MapEffects/GameAudio", "MapEffects/Weather", "MapEffects/CoreFeedbackAudio", "WavePrototype/RunGrowth"]:
		var node := scene.get_node_or_null(path)
		if not node: continue
		match path:
			"WorldEntry": node.preview_on_direct_run = false
			"WorldMainMenu": node.show_on_world_start = false
			"LoadoutUI": node.save_enabled = false
			"GameSettingsUI": node.save_graphics_settings = false
			"MapEffects/BGM": node.music_enabled = false
			"MapEffects/GameAudio": node.load_local_mix = false
			"MapEffects/Weather":
				node.rain_audio_enabled = false
				node.wind_audio_enabled = false
			_: node.enabled = false

func world_checks() -> void:
	var world: Node = load("res://scenes/world/world.tscn").instantiate()
	quiet(world)
	root.add_child(world)
	for index in 12: await process_frame
	var player := world.get_node("Player") as Player
	check(player.animations.resource_path.contains("/scenes/world/player/"), "战斗人物只由 World 独立资源替换")
	check(player.animations.get_frame_texture(&"idle", 0).resource_path.contains("/finalart/idle/"), "待机使用用户提供的战斗形态")
	check(player.animations.get_frame_texture(&"run", 0).resource_path.contains("/finalart/walk/"), "行走接入战斗形态八帧")
	var visuals := world.get_node("BattleConfiguration").configuration.action_visuals as PlayerActionVisuals
	check(visuals.normal_attack != null and visuals.flight != null, "World 已绑定普攻和弹射动作素材")
	check(visuals.bounce != null, "World 绑定已确认并去掉第十帧的人物反弹动画")
	if visuals.bounce:
		check(visuals.bounce.get_frame_count(&"side") == 9 and not visuals.bounce.get_animation_loop(&"side"), "反弹动画仅播放前九帧且不循环")
		check(visuals.bounce.get_frame_texture(&"side", 8).resource_path.ends_with("bounce_side/frame_09.png"), "反弹尾帧使用第九帧，不重新加入被移除的姿势")
		var duration := 0.0
		for index in visuals.bounce.get_frame_count(&"side"):
			duration += visuals.bounce.get_frame_duration(&"side", index) / visuals.bounce.get_animation_speed(&"side")
			check(visuals.bounce.get_frame_texture(&"side", index).get_size() == Vector2(96, 96), "反弹每帧保持原生 96×96 尺寸")
		check(is_equal_approx(duration, 0.23), "移除第十帧后保留九帧原有节奏，共 0.23 秒")
		for heading in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			check(player.action_animator.request_bounce(heading), "World 原生九帧资源支持各个出射方向")
		player.action_animator.cancel_attack()
	var native_imports := true
	var sources := [player.animations, visuals.normal_attack, visuals.flight]
	if visuals.bounce: sources.append(visuals.bounce)
	for source in sources:
		for name in source.get_animation_names():
			for index in source.get_frame_count(name):
				var imported := ConfigFile.new()
				if imported.load(source.get_frame_texture(name, index).resource_path + ".import") != OK:
					native_imports = false
				else:
					native_imports = native_imports and imported.get_value("params", "compress/mode") == 0 and imported.get_value("params", "detect_3d/compress_to") == 0 and imported.get_value("params", "process/size_limit") == 0
	check(native_imports, "全部动作帧保留原尺寸和无损像素，首次用于 3D 也不自动切换有损压缩")
	check(visuals.charge == null, "本次不替换蓄力动作")
	var sprite := player.get_node("Sprite") as Sprite3D
	check(is_equal_approx(sprite.pixel_size * sprite.scale.x, 0.018), "World 拉远镜头后以 0.9 显示缩放补偿人物辨识度，保留原生像素")
	var texture := player.animations.get_frame_texture(&"idle", 0)
	check(not texture.get_image().is_compressed(), "人物贴图采用无损导入，保留原生像素与透明边界")
	var bottom := texture.get_image().get_used_rect().end.y
	var foot := sprite.position.y + (texture.get_height() * 0.5 - bottom) * sprite.pixel_size * sprite.scale.y
	check(is_equal_approx(foot, 0.02), "脚底在碰撞体原点上方两厘米，不由武器宽度缩放人物")
	check(player.animations.has_animation(&"dash"), "闪身显示也沿用战斗形态，避免短暂切回旧人物")
	var blink := player._blink
	player._facing = &"side"
	blink._facing = &"side"
	blink._flip = true
	for age in [0.0, blink._anticipation, blink._anticipation + blink._hold]:
		blink._elapsed = age
		blink.apply_pose()
		check(player.sprite.texture.resource_path.contains("/finalart/walk/") and player.sprite.flip_h, "闪身各阶段保持战斗人物与左右朝向")
	player.sword._begin(Vector3.RIGHT, false)
	check(is_equal_approx(player.action_animator._attack_duration, player.sword._settings.duration()), "真实剑术出手事件传入本刀时长，不由贴图帧数决定伤害时序")
	player.action_visuals = player.action_visuals.duplicate()
	player.action_animator.visuals = player.action_visuals
	player.action_animator.cancel_attack()
	player.body_ricochet.impact_recorded.emit(RicochetImpact.new(Vector3.ZERO, Vector3.RIGHT, Vector3.LEFT * 5.0, Vector3.RIGHT * 4.0, 1, 1, 0.0))
	check(player.action_animator._attack.is_empty(), "通用反弹快照不绕过建筑碰撞限制直接播放人物动作")
	player.action_animator.cancel_attack()
	player.body_ricochet.crowd_deflected.emit(Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD)
	check(player.action_animator._attack.is_empty(), "怪群接触与环绕转向不播放蹬墙动作")
	player.action_animator.request_bounce(Vector3.RIGHT)
	player.body_ricochet.crowd_deflected.emit(Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD)
	check(player.action_animator._attack.is_empty(), "转入怪群绕行立即交回飞行显示，不残留此前蹬墙动作")
	player.action_animator.play_attack(&"flight_attack", Vector3.RIGHT, 0.2)
	player.body_ricochet.crowd_deflected.emit(Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD)
	check(player.action_animator._attack == &"flight_attack", "怪群绕行不取消正常飞行攻击显示")
	player.body_ricochet.cancel()
	var shape := player.get_node("Collision").shape as CapsuleShape3D
	check(is_equal_approx(shape.height, 1.06592) and is_equal_approx(shape.radius, 0.24), "美术替换不改变人物碰撞体")
	world.free()
	await process_frame
	var city: Node = load("res://scenes/city/city.tscn").instantiate()
	quiet(city)
	root.add_child(city)
	for index in 12: await process_frame
	check((city.get_node("Player") as Player).animations != load("res://data/combat/scenes/world/player/character_movement.tres"), "City 与 World 使用独立人物动画资源")
	city.free()
	await process_frame

func run() -> void:
	animator_checks()
	await world_checks()
	print("World character animations: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
