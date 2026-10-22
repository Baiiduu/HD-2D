extends SceneTree

const LIGHTING := preload("res://scripts/rendering/character_lighting.gd")
const ENEMIES := ["slime", "leaf_charger", "lantern_spitter", "pot_brood", "bell_frog", "mini_slime"]
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func sync(sprite: Sprite3D, texture: Texture2D, opacity: float) -> void:
	sprite.texture = texture
	sprite.modulate.a = opacity
	sprite.call("_process", 0.0)

func run() -> void:
	var enemy := WaveEnemy.new()
	root.add_child(enemy)
	for name in ENEMIES:
		var source: SlimeEnemy = load("res://scenes/enemies/" + name + ".tscn").instantiate()
		var frames := source.animations
		var sprite: Sprite3D = source.get_node("Sprite").duplicate()
		sprite.set("shared_materials", true)
		enemy.add_child(sprite)
		source.free()
		var textures: Array[Texture2D] = []
		for animation in frames.get_animation_names():
			for frame in frames.get_frame_count(animation):
				var texture := frames.get_frame_texture(animation, frame)
				if texture and texture not in textures: textures.append(texture)
		var materials: Array[Material] = []
		for texture in textures:
			for opacity in [0.4, 1.0]:
				sync(sprite, texture, opacity)
				materials.append(sprite.material_overlay)
		var warmed := LIGHTING._shared_effect_masks.size()
		var reused := true
		for cycle in 3:
			var index := 0
			for texture in textures:
				for opacity in [0.4, 1.0]:
					sync(sprite, texture, opacity)
					reused = reused and sprite.material_overlay == materials[index]
					index += 1
		check(reused, name + "：完整动画循环与出生透明度复用原有遮罩材质")
		check(LIGHTING._shared_effect_masks.size() == warmed, name + "：持续播放动画不增长遮罩缓存")
		sync(sprite, null, 1.0)
		check(sprite.material_overlay == null, name + "：移除贴图不残留遮罩")
		sync(sprite, textures[0], 0.4)
		check(sprite.material_overlay == materials[0], name + "：移除再恢复贴图仍复用缓存")
		var twin: Sprite3D = sprite.duplicate()
		enemy.add_child(twin)
		check(twin.material_overlay == sprite.material_overlay, name + "：多个怪物共用相同帧的遮罩")
		twin.free()
		sprite.free()
	enemy.free()
	await process_frame
	check(LIGHTING._shared_effect_masks.is_empty() and LIGHTING._shared_users == 0, "最后实例离场后释放全部遮罩缓存")
	print("Enemy effect mask cache: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
