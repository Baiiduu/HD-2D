extends RefCounted
## 仅贴图与绘制层级属于材质；动画、乘色和浓淡由每个网格的实例参数保存。
const SHADER := preload("res://shaders/combat/enemy_remains.gdshader")
static var _cache: Dictionary = {}
static var _users := 0

static func retain() -> void:
	_users += 1

static func release() -> void:
	_users -= 1
	if _users == 0: _cache.clear()

static func material(texture: Texture2D, foreground := true, ghost := false) -> ShaderMaterial:
	if not _cache.has(texture): _cache[texture] = {}
	var variants: Dictionary = _cache[texture]
	var key := int(foreground) + int(ghost) * 2
	if not variants.has(key):
		var value := CombatEffectLayer.material(SHADER) if foreground else ShaderMaterial.new()
		value.shader = SHADER
		CombatEffectLayer.set_parameter(value, &"effect_texture", texture)
		if ghost:
			value.render_priority = -1
			value.next_pass.render_priority = 7
		variants[key] = value
	return variants[key]

static func prepare_frames(frames: SpriteFrames) -> void:
	if not frames or not frames.has_animation(&"bounce"): return
	for index in frames.get_frame_count(&"bounce"):
		var image := frames.get_frame_texture(&"bounce", index)
		if image: material(image.atlas if image is AtlasTexture else image)
