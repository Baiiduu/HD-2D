class_name CombatEffectLayer
extends RefCounted

## 原有材质照常绘制；补画通道只接收可见怪物遮住的像素，建筑仍参与遮挡。
## 遮罩使用 stencil 1，由 CharacterLighting 的透明覆盖材质在技能之前写入。
static var _overlay_shaders: Dictionary[Shader, Shader] = {}

static func material(shader: Shader) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = shader
	if not _overlay_shaders.has(shader):
		var overlay_shader := Shader.new()
		overlay_shader.code = shader.code.replace("render_mode ", "stencil_mode read, compare_equal, 1;\nrender_mode depth_test_inverted, ")
		_overlay_shaders[shader] = overlay_shader
	var overlay := ShaderMaterial.new()
	overlay.shader = _overlay_shaders[shader]
	overlay.render_priority = 8
	result.next_pass = overlay
	return result

static func set_parameter(target: ShaderMaterial, name: StringName, value: Variant) -> void:
	target.set_shader_parameter(name, value)
	if target.next_pass is ShaderMaterial:
		(target.next_pass as ShaderMaterial).set_shader_parameter(name, value)

static func duplicate_material(source: ShaderMaterial) -> ShaderMaterial:
	var result := source.duplicate() as ShaderMaterial
	if source.next_pass: result.next_pass = source.next_pass.duplicate()
	return result
