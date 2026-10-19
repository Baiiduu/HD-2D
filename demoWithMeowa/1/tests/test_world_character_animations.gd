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
	var native_imports := true
	for source in [player.animations, visuals.normal_attack, visuals.flight]:
		for name in source.get_animation_names():
			for index in source.get_frame_count(name):
				var imported := ConfigFile.new()
				if imported.load(source.get_frame_texture(name, index).resource_path + ".import") != OK:
					native_imports = false
				else:
					native_imports = native_imports and imported.get_value("params", "compress/mode") == 0 and imported.get_value("params", "detect_3d/compress_to") == 0 and imported.get_value("params", "process/size_limit") == 0
	check(native_imports, "全部动作帧保留原尺寸和无损像素，首次用于 3D 也不自动切换有损压缩")
	check(visuals.charge == null and visuals.get("bounce") == null, "蓄力和反弹保留空槽，不伪造动作")
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
	player.action_visuals.bounce = frames(&"default")
	player.body_ricochet.impact_recorded.emit(RicochetImpact.new(Vector3.ZERO, Vector3.RIGHT, Vector3.LEFT * 5.0, Vector3.RIGHT * 4.0, 1, 1, 0.0))
	check(player.action_animator._attack == &"bounce", "真实反弹事件已连到空槽背后的动作接口")
	player.body_ricochet.cancel()
	var shape := player.get_node("Collision").shape as CapsuleShape3D
	check(is_equal_approx(shape.height, 1.06592) and is_equal_approx(shape.radius, 0.24), "美术替换不改变人物碰撞体")
	world.free()
	await process_frame
	var city: Node = load("res://scenes/city/city.tscn").instantiate()
	quiet(city)
	root.add_child(city)
	for index in 12: await process_frame
	check(not (city.get_node("Player") as Player).animations.get_frame_texture(&"idle", 0).resource_path.contains("finalart"), "City 保留独立人物配置")
	city.free()
	await process_frame

func run() -> void:
	animator_checks()
	await world_checks()
	print("World character animations: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
