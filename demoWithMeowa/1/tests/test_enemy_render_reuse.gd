extends SceneTree

const LIGHTING := preload("res://scripts/rendering/character_lighting.gd")
var checks := 0
var failures := 0
var viewport: SubViewport

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle(count := 3) -> void:
	for frame in count: await process_frame

func capture(shown: Sprite3D, hidden: Sprite3D) -> Image:
	shown.show()
	hidden.hide()
	await settle()
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position.z = 3.0
	camera.current = true
	viewport.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -30, 0)
	light.light_energy = 1.3
	viewport.add_child(light)
	var frames: SpriteFrames = load("res://assets/meowa/slime/animations.tres")
	var original: Sprite3D = LIGHTING.new()
	var pooled: Sprite3D = LIGHTING.new()
	var twin: Sprite3D = LIGHTING.new()
	pooled.set("shared_materials", true)
	twin.set("shared_materials", true)
	for sprite in [original, pooled, twin]:
		sprite.pixel_size = 0.015625
		sprite.texture = frames.get_frame_texture(&"idle_front", 0)
		sprite.shaded = true
		viewport.add_child(sprite)
	twin.hide()
	await settle()
	check(pooled.get("_material") == twin.get("_material"), "同帧和同参数主体共用材质")
	check(pooled.get("_outline_material") == twin.get("_outline_material"), "同帧和同参数轮廓共用材质")
	check(pooled.get("_outline_mesh") == twin.get("_outline_mesh"), "相同画布与像素尺度共用网格")
	pooled.modulate = Color(1.8, 1.8, 1.8, 1.0)
	await settle()
	check(pooled.get("_material") != twin.get("_material") and twin.get("_material").get_shader_parameter("tint") == Color.WHITE, "单体受击闪光不污染其它怪物")
	pooled.modulate = Color.WHITE
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 1.0, 0.1)
	wall.mesh = box
	wall.position.z = 0.8
	viewport.add_child(wall)
	for normals in [false, true]:
		for sprite in [original, pooled]: sprite.set("normal_mapping_enabled", normals)
		for index in [0, 2, 7]:
			for flip in [false, true]:
				for sprite in [original, pooled]:
					sprite.texture = frames.get_frame_texture(&"hop_front_right", index)
					sprite.flip_h = flip
				var before := await capture(original, pooled)
				var after := await capture(pooled, original)
				check(before.get_data() == after.get_data(), "共享主体与遮挡轮廓逐像素保持一致：法线 %s／帧 %d／翻转 %s" % [normals, index, flip])
				if before.get_data() != after.get_data():
					before.save_png("D:/.codexfile/work/enemy-300-growth/render-before.png")
					after.save_png("D:/.codexfile/work/enemy-300-growth/render-after.png")
	var mutable := AtlasTexture.new()
	mutable.atlas = (frames.get_frame_texture(&"idle_front", 0) as AtlasTexture).atlas
	mutable.region = Rect2(0, 0, 80, 80)
	pooled.texture = mutable
	await settle()
	mutable.region = Rect2(0, 80, 80, 80)
	await settle()
	var region: Vector4 = pooled.get("_material").get_shader_parameter("sprite_region")
	check(is_equal_approx(region.y, 80.0 / mutable.atlas.get_height()), "图集原地修改重新选择正确区域")
	pooled.set("occlusion_outline_enabled", false)
	await settle()
	check(not pooled.get("_outline").visible, "关闭轮廓立即生效")
	pooled.set("occlusion_outline_enabled", true)
	await settle()
	check(pooled.get("_outline").visible, "重新开启轮廓时缓存失效并恢复")
	# 完全遮挡时核对关闭的实际像素，覆盖旧辅助节点留存但缓存引用丢失的情况。
	pooled.texture = frames.get_frame_texture(&"idle_front", 0)
	box.size = Vector3(2.0, 2.0, 0.1)
	var enabled_image := await capture(pooled, original)
	var old_outline := pooled.get_node("OcclusionOutline") as MeshInstance3D
	pooled.set("_outline", null)
	pooled.set("occlusion_outline_enabled", false)
	var disabled_image := await capture(pooled, original)
	check(enabled_image.get_data() != disabled_image.get_data(), "真实被挡轮廓随关闭开关从画面消失")
	old_outline.hide()
	var hidden_reference := await capture(pooled, original)
	check(disabled_image.get_data() == hidden_reference.get_data(), "关闭后的画面与直接隐藏辅助面片逐像素一致")
	viewport.queue_free()
	await settle()
	check(LIGHTING._shared_users == 0 and LIGHTING._shared_bodies.is_empty() and LIGHTING._shared_outlines.is_empty() and LIGHTING._shared_quads.is_empty(), "最后实例离场后共享资源缓存释放")
	print("Enemy render reuse: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
