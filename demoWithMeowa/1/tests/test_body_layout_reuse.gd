extends SceneTree

const LAYOUT := preload("res://scripts/rendering/sprite_body_layout.gd")
const WARMUP := preload("res://scripts/world/combat_feedback_warmup.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func texture(size: Vector2i) -> ImageTexture:
	return ImageTexture.create_from_image(Image.create(size.x, size.y, false, Image.FORMAT_RGBA8))

func run() -> void:
	var sprite := Sprite3D.new()
	var first := texture(Vector2i(96,96))
	var second := texture(Vector2i(96,96))
	sprite.texture = first
	var key := LAYOUT.key_for(sprite)
	var layout := [Vector3.ZERO,Vector3.RIGHT,Vector3.UP,Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN]
	sprite.set_meta(LAYOUT.META,{key:layout})
	sprite.texture = second
	check(LAYOUT.key_for(sprite) == key,"相同画布的普通贴图共用原生顶点和 UV 布局")
	if LAYOUT.key_for(sprite) == key:
		check(LAYOUT.sample(sprite) == layout,"更换同尺寸人物帧直接命中已有布局，无须渲染读回")
	var before_pose := LAYOUT.key_for(sprite)
	sprite.position = Vector3(3,4,5)
	sprite.rotation.y = 0.7
	check(LAYOUT.key_for(sprite) == before_pose,"人物世界姿态不参与局部布局")
	var changes := {"offset":Vector2(0,9),"centered":false,"pixel_size":0.03,"axis":Vector3.AXIS_X,"hframes":2,"vframes":2,"flip_h":true,"flip_v":true}
	for property in changes:
		var previous: Variant = sprite.get(property)
		var before := LAYOUT.key_for(sprite)
		sprite.set(property,changes[property])
		check(LAYOUT.key_for(sprite) != before,"保留影响原生布局的配置："+property)
		sprite.set(property,previous)
	sprite.texture = texture(Vector2i(64,96))
	check(LAYOUT.key_for(sprite) != key,"不同画布尺寸不会复用布局")
	sprite.texture = first
	sprite.region_enabled = true
	sprite.region_rect = Rect2(8,16,48,32)
	check(LAYOUT.key_for(sprite) != key,"局部区域的顶点和 UV 独立缓存")
	sprite.region_enabled = false
	sprite.hframes = 2
	var first_frame_key := LAYOUT.key_for(sprite)
	sprite.frame = 1
	check(LAYOUT.key_for(sprite) != first_frame_key,"同一贴图的不同分帧保留实际 UV 偏移")
	sprite.hframes = 1
	var atlas := AtlasTexture.new()
	atlas.atlas = texture(Vector2i(384,384))
	atlas.region = Rect2(0,0,96,96)
	sprite.texture = atlas
	var atlas_key := LAYOUT.key_for(sprite)
	atlas.region.position = Vector2(96,0)
	check(LAYOUT.key_for(sprite) != atlas_key,"图集相同尺寸的不同帧仍使用实际 UV")
	atlas_key = LAYOUT.key_for(sprite)
	atlas.margin = Rect2(2,3,4,5)
	check(LAYOUT.key_for(sprite) != atlas_key,"图集裁边和留白变化仍使缓存失效")
	var warmup := WARMUP.new()
	root.add_child(warmup)
	warmup.set_process(false)
	warmup._proxies = Node3D.new()
	warmup.add_child(warmup._proxies)
	sprite.texture = first
	sprite.remove_meta(LAYOUT.META)
	for image in [first,second]:
		for flipped in [false,true]: warmup._prepare_body_card(image,flipped,sprite)
	check(warmup._proxies.get_child_count() == 2,"菜单只创建每种真实布局的一张原生取样卡，保留两种水平朝向")
	warmup.free() # 延迟读回前释放，无界面测试不访问渲染网格。
	var authored_layouts := {}
	var canvases := {}
	var textures := {}
	for path in ["character_movement","character_attack","character_flight","character_bounce"]:
		var frames := load("res://data/combat/scenes/world/player/"+path+".tres") as SpriteFrames
		for animation in frames.get_animation_names():
			for index in frames.get_frame_count(animation):
				sprite.texture = frames.get_frame_texture(animation,index)
				canvases[sprite.texture.get_size()] = true
				textures[sprite.texture] = true
				for flipped in [false,true]:
					sprite.flip_h = flipped
					authored_layouts[LAYOUT.key_for(sprite)] = true
	check(authored_layouts.size() == canvases.size()*2 and authored_layouts.size() < textures.size()*2,"World 全部动作按真实画布及两种朝向复用，不为每张贴图重复取样")
	sprite.free()
	print("BODY_LAYOUT_REUSE ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
