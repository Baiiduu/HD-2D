extends SceneTree

const SESSION := preload("res://tests/fixtures/ricochet_session.gd")
var checks := 0
var failures := 0
var world: Node3D
var player: Player
var session: WavePrototype
var body: PlayerRicochet
var trail: PlayerFlightTrail
var camera: Camera3D
var segments: Array[Dictionary] = []
var frames: SpriteFrames = load("res://assets/meowa/player/animations.tres")

func _initialize() -> void:
	create_timer(80.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle(count := 4) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func box(point: Vector3, size: Vector3) -> void:
	var block := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	block.add_child(collision)
	world.add_child(block)
	block.position = point

func active_echoes() -> Array[Dictionary]:
	return trail._echoes.filter(func(echo): return echo.active)

func launch() -> void:
	body.cancel(true)
	check(body.begin_charge(Vector3.RIGHT), "从真实接地状态蓄力")
	check(not trail.visible and not trail.is_processing(), "蓄力不产生飞行人形残影")
	check(body.release_charge(), "真实弹射发射成功")
	trail.set_physics_process(false)
	trail.set_process(false)

func advance(delta: float) -> void:
	body.advance(delta, Vector3.ZERO, false)
	trail._physics_process(delta)
	trail._display_at(trail._clock)

func reset() -> void:
	body.cancel(true)
	player.global_position = Vector3(0, 0.02, 0)
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	await settle(8)
	player.set_physics_process(false)
	player.set_process(false)

func echo_checks() -> void:
	check(player.sword == null, "人物残影不依赖剑术组件")
	check(not trail.visible and not trail.is_physics_processing(), "闲置隐藏并停止处理")
	check(trail._echoes.size() == PlayerFlightTrail.CAPACITY, "残影节点与材质预先固定池化")
	var instance_ids := trail._echoes.map(func(echo): return echo.sprite.get_instance_id())
	var material_ids := trail._echoes.map(func(echo): return echo.material.get_rid())
	launch()
	advance(0.32)
	check(body.bounce_count == 1 and segments.size() == 2, "真实胶囊同一物理步产生墙前和墙后运动段")
	var echoes := active_echoes()
	check(echoes.size() >= 5, "低帧率单步运动沿经过路径补齐残影样本")
	for echo in echoes:
		var expected: Vector3 = segments[0].start
		var distance: float = echo.distance
		for piece in segments:
			var length: float = piece.start.distance_to(piece.end)
			expected = piece.start.lerp(piece.end, clampf(distance / length, 0.0, 1.0))
			if distance <= length: break
			distance -= length
		check(echo.sprite.global_position.is_equal_approx(expected + player.sprite.position), "残影落在真实折线路段上，保留原生脚底锚点")
	check(echoes.any(func(echo): return echo.distance > segments[0].start.distance_to(segments[0].end)), "墙后返回段也产生独立残影")
	var first: Dictionary = echoes[0]
	var old_texture: Texture2D = first.sprite.texture
	var old_flip: bool = first.sprite.flip_h
	var old_scale: Vector3 = first.sprite.global_basis.get_scale()
	player.sprite.texture = frames.get_frame_texture(&"idle_back", 0)
	player.sprite.flip_h = not old_flip
	player.sprite.scale *= 1.1
	check(first.sprite.texture == old_texture and first.sprite.flip_h == old_flip and first.sprite.global_basis.get_scale().is_equal_approx(old_scale), "已留下的帧、翻转和尺度不随主体后续改变")
	check(first.material.get_shader_parameter("source_tint") == player.sprite.modulate, "人物原始乘色作为快照保留")
	var positions := echoes.map(func(echo): return echo.sprite.global_position)
	camera.rotation.y += PI * 0.5
	trail._display_at(trail._clock)
	check(positions == echoes.map(func(echo): return echo.sprite.global_position), "镜头旋转不移动已有世界残影")
	session.set_combat_frozen(true)
	var clock := trail._clock
	var frozen_time := trail._render_clock()
	trail._display_at(frozen_time)
	var opacity: float = first.material.get_shader_parameter("opacity")
	trail._physics_process(0.4)
	trail._display_at(trail._render_clock())
	check(trail._clock == clock and frozen_time > 0.0 and trail._render_clock() == frozen_time, "升级冻结保留正确采样时刻")
	check(first.material.get_shader_parameter("opacity") == opacity and positions == echoes.map(func(echo): return echo.sprite.global_position), "升级冻结同时保留残影位置与透明度")
	session.set_combat_frozen(false)
	advance(0.02)
	check(trail._clock > clock, "升级结束继续消散")
	player.flight_trail_settings.flight_trail_max_length = 0.5
	trail._display_at(trail._clock)
	check(active_echoes().all(func(echo): return trail._distance - echo.distance < 0.50001), "长度上限按真实折线路程移除旧残影")
	player.flight_trail_settings.flight_trail_max_length = 6.0
	body._end_flight(&"duration")
	var stationary := active_echoes().map(func(echo): return echo.sprite.global_position)
	player.global_position += Vector3(5, 0, 2)
	trail._display_at(trail._clock + 0.01)
	check(stationary == active_echoes().map(func(echo): return echo.sprite.global_position), "飞行结束后人物离开，已有残影原地淡出")
	trail._physics_process(0.8)
	trail._display_at(trail._clock)
	check(not trail.visible and not trail.is_processing() and not trail.is_physics_processing(), "完全消散后停止全部处理")
	check(instance_ids == trail._echoes.map(func(echo): return echo.sprite.get_instance_id()) and material_ids == trail._echoes.map(func(echo): return echo.material.get_rid()), "持续运动与消散复用同一批节点和材质")
	await reset()
	launch()
	body.advance(0.2, Vector3.ZERO, false)
	check(active_echoes().is_empty() and not trail._pending.is_empty(), "物理段只排队，人物选择实际画面后再生成残影")
	trail._display_at(0.01)
	check(active_echoes().all(func(echo): return echo.born <= 0.01), "不会提前显示尚未到达的路径样本")
	trail.clear()

func lifecycle_checks() -> void:
	await reset()
	launch()
	advance(0.1)
	player.flight_trail_settings.enabled = false
	trail._process(0.01)
	check(not trail.visible and active_echoes().is_empty() and trail._pending.is_empty(), "关闭开关立即清掉所有残影和排队样本")
	player.flight_trail_settings.enabled = true
	launch()
	advance(0.05)
	check(not active_echoes().is_empty(), "重新启用后的下一次发射恢复显示")
	session._set_phase(WavePrototype.Phase.REST)
	check(not trail.visible and active_echoes().is_empty(), "波次结束立即清理残影")
	session._set_phase(WavePrototype.Phase.BATTLE)
	launch()
	advance(0.05)
	body.cancel()
	check(not trail.is_physics_processing() and active_echoes().is_empty(), "取消弹射立即停止残影")
	launch()
	advance(0.05)
	player.current_health = 0.0
	trail._physics_process(0.01)
	check(not trail.visible and active_echoes().is_empty(), "人物死亡不残留人形")
	player.heal(player.max_health)
	body.cancel(true)
	trail._on_launched(Vector3.RIGHT, 8.0, 1.0)
	for index in 400:
		trail._on_segment(Vector3(index, 0, 0), Vector3(index + 1, 0, 0), Vector3.RIGHT, 0.001)
	check(trail._pending.size() == PlayerFlightTrail.MAX_PENDING, "积压样本有固定容量")
	trail._physics_process(0.4)
	trail._display_at(0.4)
	check(active_echoes().size() <= player.flight_trail_settings.flight_echo_count and trail._echoes.size() == PlayerFlightTrail.CAPACITY, "极速与低帧率不会无限创建残影节点")
	trail.clear()
	trail._on_launched(Vector3.RIGHT, 8.0, 1.0)
	trail._on_segment(Vector3.ZERO, Vector3(0.5, 0, 0), Vector3.RIGHT, 0.1)
	trail._on_segment(Vector3(20, 0, 0), Vector3(20.5, 0, 0), Vector3.RIGHT, 0.1)
	check(trail._pending.all(func(sample): return sample.point.x <= 0.5 or sample.point.x >= 20.0), "不连续位移不在跨越区域生成残影")
	trail.clear()
	var valid := player.flight_trail_settings
	var invalid := PlayerFlightTrailSettings.new()
	invalid.flight_echo_count = 0
	check(not invalid.validation_error().is_empty(), "拒绝零数量避免池索引除零")
	player.flight_trail_settings = invalid
	trail._on_launched(Vector3.RIGHT, 8.0, 1.0)
	check(not trail.is_processing(), "非法配置不启动残影")
	player.flight_trail_settings = valid

func render_checks() -> void:
	if DisplayServer.get_name() == "headless": return
	body.cancel(true)
	trail._settings = player.flight_trail_settings
	player.position = Vector3.ZERO
	player.sprite.position = Vector3(0, 0.75, 0)
	player.sprite.scale = Vector3.ONE * 0.8
	player.reset_physics_interpolation()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.world_3d = world.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view := Camera3D.new()
	view.projection = Camera3D.PROJECTION_ORTHOGONAL
	view.size = 1.6
	view.position = Vector3(0, 0.75, 3)
	view.current = true
	viewport.add_child(view)
	player.sprite.texture = frames.get_frame_texture(&"idle", 0)
	player.sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	player.sprite.shaded = false
	player.sprite.modulate = Color.WHITE
	var reference := player.sprite.texture.get_image()
	var sheet := Image.create(reference.get_width() * 2, reference.get_height() * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	sheet.blit_rect(reference, Rect2i(Vector2i.ZERO, reference.get_size()), reference.get_size())
	var atlas := AtlasTexture.new()
	atlas.atlas = ImageTexture.create_from_image(sheet)
	atlas.region = Rect2(Vector2(reference.get_size()), Vector2(reference.get_size()))
	for variant in 10:
		view.projection = Camera3D.PROJECTION_PERSPECTIVE if variant == 8 else Camera3D.PROJECTION_ORTHOGONAL
		view.position = Vector3(-2, 1.9, 2.6) if variant == 8 else Vector3(0, 0.75, 3)
		view.fov = 35.0
		view.look_at(Vector3(0, 0.75, 0))
		var source := player.sprite
		source.modulate = Color(0.8, 0.65, 0.4, 0.6) if variant == 9 else Color.WHITE
		source.texture = frames.get_frame_texture(&"idle", variant % 2)
		source.flip_h = variant % 2 == 1
		source.flip_v = variant == 2
		source.offset = Vector2(3, -4) if variant >= 3 else Vector2.ZERO
		source.centered = variant != 4
		source.hframes = 2 if variant == 5 else 1
		source.vframes = 2 if variant == 5 else 1
		source.frame = 3 if variant == 5 else 0
		source.region_enabled = variant == 7
		if variant == 6:
			source.texture = atlas
		if variant == 7:
			source.texture = atlas.atlas
			source.region_rect = atlas.region
		source.billboard = BaseMaterial3D.BILLBOARD_ENABLED if variant == 8 else BaseMaterial3D.BILLBOARD_FIXED_Y
		trail.clear()
		source.show()
		await settle(3)
		await RenderingServer.frame_post_draw
		var original := viewport.get_texture().get_image()
		trail.show()
		trail._cursor = 0
		trail._spawn_echo({"point": player.global_position, "time": 0.0, "distance": 0.0})
		var echo: Dictionary = trail._echoes[0]
		echo.material.set_shader_parameter("opacity", 1.0)
		echo.material.set_shader_parameter("saturation", 1.0)
		echo.material.set_shader_parameter("brightness", 1.0)
		echo.material.set_shader_parameter("echo_color", Color.WHITE)
		echo.material.set_shader_parameter("energy", 0.0)
		source.hide()
		await settle(3)
		await RenderingServer.frame_post_draw
		var snapshot := viewport.get_texture().get_image()
		var mismatches := 0
		var opaque := 0
		for y in 256:
			for x in 256:
				var a := original.get_pixel(x, y)
				var b := snapshot.get_pixel(x, y)
				if a.a > 0.1: opaque += 1
				if absf(a.a - b.a) > 0.01 or (a.a > 0.01 and (absf(a.r - b.r) > 0.01 or absf(a.g - b.g) > 0.01 or absf(a.b - b.b) > 0.01)): mismatches += 1
		check(opaque > 20 and mismatches == 0, "原生渲染人物帧、UV、翻转、留白、尺度和配色逐像素一致：%d（差异 %d）" % [variant, mismatches])
		var args := OS.get_cmdline_user_args()
		if "--capture-echo" in args:
			var directory: String = args[args.find("--capture-echo") + 1]
			DirAccess.make_dir_recursive_absolute(directory)
			original.save_png(directory.path_join("source-%d.png" % variant))
			snapshot.save_png(directory.path_join("echo-%d.png" % variant))
		await body_mask_check(viewport, view, echo, variant)
		trail.clear()
	# 墙体仍应遮住残影；残影没有人物的穿墙轮廓，也不禁用深度测试。
	player.sprite.texture = frames.get_frame_texture(&"idle", 0)
	player.sprite.modulate = Color.WHITE
	player.sprite.offset = Vector2.ZERO
	player.sprite.centered = true
	player.sprite.show()
	trail.show()
	trail._cursor = 0
	trail._spawn_echo({"point": player.global_position, "time": 0.0, "distance": 0.0})
	var ghost: Dictionary = trail._echoes[0]
	ghost.material.set_shader_parameter("opacity", 1.0)
	ghost.material.set_shader_parameter("saturation", 1.0)
	ghost.material.set_shader_parameter("brightness", 1.0)
	ghost.material.set_shader_parameter("echo_color", Color.WHITE)
	player.sprite.hide()
	await settle(3)
	await RenderingServer.frame_post_draw
	var unobstructed := viewport.get_texture().get_image()
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(1.5, 1.8, 0.1)
	wall.mesh = wall_mesh
	var wall_material := StandardMaterial3D.new()
	wall_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall_material.albedo_color = Color(0.08, 0.1, 0.14)
	wall.material_override = wall_material
	world.add_child(wall)
	wall.position = Vector3(0, 0.75, 1.0)
	await settle(3)
	await RenderingServer.frame_post_draw
	var blocked := viewport.get_texture().get_image()
	ghost.sprite.hide()
	await settle(3)
	await RenderingServer.frame_post_draw
	var wall_only := viewport.get_texture().get_image()
	check(unobstructed.get_used_rect().has_area() and unobstructed.get_data() != blocked.get_data(), "墙体确实挡在可见人物残影前方")
	check(blocked.get_data() == wall_only.get_data(), "被墙完全遮住时与只有墙的画面逐像素一致，无残影或穿墙轮廓泄露")
	wall.queue_free()
	trail.clear()
	player.sprite.show()
	viewport.queue_free()
	await settle()

func body_mask_check(viewport: SubViewport, view: Camera3D, echo: Dictionary, variant: int) -> void:
	var source := player.sprite
	source.show()
	echo.sprite.hide()
	await settle(3)
	await RenderingServer.frame_post_draw
	var body_only := viewport.get_texture().get_image()
	# 故意放到主体前方并提高显色，确保普通深度测试无法掩盖重叠问题。
	echo.sprite.global_position += view.global_basis.z * 0.3 + view.global_basis.x * (0.14 if variant % 2 else -0.14)
	echo.material.set_shader_parameter("opacity", 0.85)
	echo.material.set_shader_parameter("echo_color", Color(1.0, 0.1, 0.8))
	echo.sprite.show()
	trail._sync_body_mask()
	await settle(3)
	await RenderingServer.frame_post_draw
	var protected := viewport.get_texture().get_image()
	var body_pixels := 0
	var overwritten := 0
	var outside := 0
	for y in 256:
		for x in 256:
			var a := body_only.get_pixel(x, y)
			var b := protected.get_pixel(x, y)
			if a.a > 0.05:
				body_pixels += 1
				if absf(a.a - b.a) > 0.01 or absf(a.r - b.r) > 0.01 or absf(a.g - b.g) > 0.01 or absf(a.b - b.b) > 0.01: overwritten += 1
			elif a.a < 0.01 and b.a > 0.01: outside += 1
	check(body_pixels > 20 and overwritten == 0, "前景残影不覆盖主体像素（翻转、裁切及镜头 %d）：%d" % [variant, overwritten])
	check(outside > 10, "剔除重叠后仍保留主体外侧残影：%d" % variant)
	var args := OS.get_cmdline_user_args()
	if "--capture-echo" in args:
		var directory: String = args[args.find("--capture-echo") + 1]
		body_only.save_png(directory.path_join("body-%d.png" % variant))
		protected.save_png(directory.path_join("protected-%d.png" % variant))

func integration_checks() -> void:
	var formal: Node = load("res://scenes/world/world.tscn").instantiate()
	var source: PlayerFlightTrailSettings = formal.get_node("Player").flight_trail_settings
	check(source != null and source.enabled and source.resource_path == "res://data/player/flight_trail.tres", "正式地图沿用唯一飞行拖尾配置")
	check(source.flight_trail_color == Color.WHITE and source.flight_echo_count == 4 and source.flight_trail_energy == 0.0, "默认四道人物帧残影，无额外发光")
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(formal)
	for property in ["enabled", "flight_echo_count", "flight_echo_spacing", "flight_trail_color", "flight_echo_saturation", "flight_echo_brightness", "flight_trail_max_length", "flight_trail_lifetime", "flight_trail_opacity", "flight_trail_energy"]:
		check(entries.any(func(item): return item.object == source and item.property == property and item.category == "人物" and item.common), "统一人物参数入口可调整残影：" + property)
	formal.get_node("LoadoutUI").save_enabled = false
	formal.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(formal)
	await settle(6)
	check(formal.get_node("Player").flight_trail != null, "正式地图运行时创建人物残影组件")
	for audio in formal.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	formal.free()
	await settle()

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	box(Vector3(0, -0.1, 0), Vector3(40, 0.2, 40))
	box(Vector3(2, 0.8, 0), Vector3(0.1, 1.6, 4))
	session = SESSION.new()
	session.name = "WavePrototype"
	session.phase = WavePrototype.Phase.BATTLE
	world.add_child(session)
	player = Player.new()
	player.name = "Player"
	player.ricochet_rules = PlayerRicochetRules.new()
	player.ricochet_rules.bounce_speed_retention = 1.0
	player.flight_trail_settings = PlayerFlightTrailSettings.new()
	player.flight_trail_settings.flight_echo_count = 8
	player.flight_trail_settings.flight_echo_spacing = 0.4
	player.flight_trail_settings.flight_trail_max_length = 6.0
	player.flight_trail_settings.flight_trail_lifetime = 0.6
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.texture = frames.get_frame_texture(&"idle", 0)
	sprite.pixel_size = 0.02
	sprite.scale = Vector3.ONE * 0.8
	sprite.position.y = 0.75
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	player.add_child(sprite)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 1.0
	collision.shape = capsule
	collision.position.y = 0.5
	player.add_child(collision)
	session.player = player
	world.add_child(player)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(4, 5, 8)
	camera.look_at(Vector3.ZERO)
	await settle(10)
	player.set_physics_process(false)
	player.set_process(false)
	body = player.body_ricochet
	trail = player.flight_trail
	body.flight_segment_travelled.connect(func(start, end, _heading, seconds): segments.append({"start": start, "end": end, "seconds": seconds}))
	await echo_checks()
	await lifecycle_checks()
	await render_checks()
	await integration_checks()
	world.queue_free()
	await settle()
	print("Player flight afterimages: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
