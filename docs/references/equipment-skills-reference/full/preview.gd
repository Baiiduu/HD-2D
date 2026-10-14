extends SceneTree

const PACK := "D:/Project/HD-2DMap/docs/references/equipment-skills-reference/full/"
const SCRATCH := "D:/.codexfile/work/ui-layer-completion/"
const CANVAS := Vector2(2048, 1152)
const INK := Color("283121")
var stage: Control
var font: SystemFont
var latin: SystemFont
var pack_root := PACK
var output_root := SCRATCH

func _initialize() -> void:
	var folder: String = get_script().resource_path.get_base_dir().replace("\\", "/") + "/"
	if FileAccess.file_exists(folder + "foundation.png"):
		pack_root = folder
		output_root = folder
	run.call_deferred()

func texture(path: String) -> Texture2D:
	var source := Image.load_from_file(pack_root + path)
	assert(source and not source.is_empty(), "Missing layer: " + path)
	return ImageTexture.create_from_image(source)

func picture(path: String, rect: Rect2, fill := false) -> TextureRect:
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.texture = texture(path)
	image.position = rect.position
	image.size = rect.size
	image.stretch_mode = TextureRect.STRETCH_SCALE if fill else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(image)
	return image

func text(words: String, rect: Rect2, size: int, color := INK, centered := false) -> Label:
	var label := Label.new()
	label.text = words
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stage.add_child(label)
	return label

func glyph(name: String, rect: Rect2) -> void:
	picture("symbols/" + name + ".png", rect)

func build() -> void:
	picture("foundation.png", Rect2(Vector2.ZERO, CANVAS), true)
	picture("portrait.png", Rect2(350, 180, 306, 690))
	# The book, scene illustration and fixed ornament are independent of dynamic content.
	var names := ["sword", "staff", "armor", "tunic", "amulet", "ring", "green-potion", "red-potion",
		"scroll", "white-herb", "ore", "feather", "bread", "pouch", "lantern", "purple-herb"]
	for index in names.size():
		var origin := Vector2(1038 + 118 * (index % 4), 328 + 142 * (index / 4))
		if index == 0:
			picture("controls/slot-active.png", Rect2(origin - Vector2(4, 4), Vector2(118, 143)), true)
		picture("items/" + names[index] + ".png", Rect2(origin + Vector2(8, 8), Vector2(94, 120)))
	picture("items/sword.png", Rect2(780, 207, 138, 139))
	picture("items/armor.png", Rect2(791, 422, 137, 130))
	picture("items/amulet.png", Rect2(790, 654, 138, 125))
	picture("items/sword.png", Rect2(1544, 337, 291, 248))
	picture("controls/equip-button.png", Rect2(1552, 832, 313, 75), true)
	text("旅人", Rect2(225, 180, 210, 78), 62)
	text("平凡的脚步\n也能走向远方。", Rect2(225, 277, 250, 72), 25)
	text("更远的风景\n还在前方", Rect2(232, 730, 180, 67), 24)
	text("小小的我，也在书写自己的冒险。", Rect2(420, 989, 475, 38), 22)
	text("背包", Rect2(1090, 180, 170, 71), 56)
	text("16/16", Rect2(1738, 203, 110, 40), 26)
	glyph("backpack", Rect2(1702, 204, 29, 29))
	for index in 3:
		var title: String = ["武器", "防具", "饰品"][index]
		var item: String = ["旅人长剑", "皮革护甲", "绿松石护符"][index]
		text(title, Rect2(805, [318, 561, 793][index], 105, 35), 23, INK, true)
		text(item, Rect2(780, [352, 598, 826][index], 159, 36), 24, INK, true)
	for index in 7:
		var titles := ["全部", "武器", "防具", "饰品", "消耗品", "素材", "其他"]
		var widths := [85, 84, 85, 87, 115, 88, 88]
		var starts := [1048, 1152, 1255, 1364, 1473, 1606, 1718]
		text(titles[index], Rect2(starts[index], 268, widths[index], 33), 24, Color("ece8ce") if index == 0 else INK, true)
	text("旅人长剑", Rect2(1555, 591, 277, 48), 36)
	text("普通的剑，也能守护重要的事。", Rect2(1558, 638, 285, 48), 20)
	glyph("sword", Rect2(1554, 680, 33, 34))
	text("攻击  +18", Rect2(1592, 682, 219, 40), 26)
	text("陪伴无数旅人的可靠长剑。\n剑身虽有使用的痕迹，\n但依然闪耀着前进的意志。", Rect2(1557, 732, 290, 90), 23)
	glyph("backpack", Rect2(1637, 856, 36, 34))
	text("装备", Rect2(1678, 849, 115, 45), 33, Color("e8dcaf"), true)
	text("「出发吧，去见更广阔的世界。」", Rect2(1559, 923, 298, 54), 19)
	text("收集旅途中的小小光芒。", Rect2(1380, 993, 368, 38), 24)
	for index in 5:
		var x := 247 + index * 134
		glyph(["heart", "sword", "shield", "boot", "star"][index], Rect2(x, 899, 35, 40))
		text(["生命", "攻击", "防御", "敏捷", "魔力"][index], Rect2(x + 42, 900, 86, 33), 23)
		text(["120", "28", "22", "18", "16"][index], Rect2(x + 43, 932, 85, 34), 28)
	for index in 3:
		var x: int = [329, 571, 789][index]
		glyph(["character", "backpack", "star"][index], Rect2(x, 53 + index * 14, 48, 49))
		text(["角色", "背包", "技能"][index], Rect2(x + 62, 57 + index * 14, 115, 48), 36, INK if index == 0 else Color("e2d9ba"), true)
	var note := text("前往更宽阔的世界。", Rect2(1316, 74, 360, 42), 29)
	note.rotation = -0.085
	var subnote := text("Still a kinder world.", Rect2(1353, 110, 340, 35), 23)
	subnote.add_theme_font_override("font", latin)
	subnote.rotation = -0.085
	var tag := text("Good\nPeople\nBrighten\nJourneys.", Rect2(1938, 772, 110, 165), 22)
	tag.add_theme_font_override("font", latin)
	tag.rotation = 0.1
	text("关闭", Rect2(1874, 153, 81, 33), 23, Color("e6dbbd"), true)

func run() -> void:
	var scene: Node3D = load("res://scenes/world/world.tscn").instantiate()
	var loadout: LoadoutUI = scene.get_node("LoadoutUI")
	loadout.save_enabled = false
	loadout.hide()
	root.add_child(scene)
	current_scene = scene
	for frame in 60:
		await physics_frame
	var camera: FollowCamera = scene.get_node("MapEffects").get_map_camera()
	camera.reset_horizontal_rotation()
	camera.snap_to_target()
	font = SystemFont.new()
	font.font_names = PackedStringArray(["KaiTi", "STKaiti", "SimSun", "Microsoft YaHei"])
	latin = SystemFont.new()
	latin.font_names = PackedStringArray(["Segoe Print", "Times New Roman"])
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var backplate := ColorRect.new()
	backplate.color = Color("18211c")
	backplate.size = root.get_visible_rect().size
	layer.add_child(backplate)
	stage = Control.new()
	stage.size = CANVAS
	stage.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var scale_factor := minf(root.get_visible_rect().size.x / CANVAS.x, root.get_visible_rect().size.y / CANVAS.y)
	stage.scale = Vector2.ONE * scale_factor
	stage.position = (root.get_visible_rect().size - CANVAS * scale_factor) * 0.5
	layer.add_child(stage)
	build()
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output_root + "assembled.png") == OK)
	var canvas := SubViewport.new()
	canvas.size = Vector2i(CANVAS)
	canvas.disable_3d = true
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var proof := stage.duplicate()
	proof.position = Vector2.ZERO
	proof.scale = Vector2.ONE
	canvas.add_child(proof)
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	assert(canvas.get_texture().get_image().save_png(output_root + "assembled-native.png") == OK)
	canvas.free()
	print("PASS: assembled preview renders actual foundation, portrait, sixteen item textures, symbols and native labels on the current map.")
	layer.free()
	scene.free()
	await process_frame
	quit()
