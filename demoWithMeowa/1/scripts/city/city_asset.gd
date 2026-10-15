@tool
extends Node3D
## 图集与材质在城市组件间共享；生成的网格按材质合并，导入不重采样像素。

const WIND_SHADER := preload("res://shaders/city_foliage.gdshader")
static var _materials: Dictionary = {}

func _ready() -> void:
	_bind($Model)

func _bind(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh:
			for surface in mesh_node.mesh.get_surface_count():
				var original := mesh_node.mesh.surface_get_material(surface) as StandardMaterial3D
				if original:
					mesh_node.set_surface_override_material(surface, _material(original))
	for child in node.get_children():
		_bind(child)

func _material(original: StandardMaterial3D) -> Material:
	var label := original.resource_name
	if _materials.has(label):
		return _materials[label]
	var group := label.get_slice("_", 0)
	var atlas: Texture2D
	if group in ["street", "props", "foliage", "structure"]:
		atlas = load("res://assets/models/city_pack/textures/" + group + ".png") as Texture2D
	if label in ["foliage_Base", "props_Flag"]:
		var leaves := ShaderMaterial.new()
		leaves.shader = WIND_SHADER
		leaves.set_shader_parameter("atlas", atlas)
		leaves.set_shader_parameter("wind_amount", 0.045 if group == "foliage" else 0.025)
		_materials[label] = leaves
		return leaves
	var material := original.duplicate() as StandardMaterial3D
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.95
	material.metallic = 0.0
	if atlas:
		material.albedo_texture = atlas
	if label.ends_with("_Window") or label.ends_with("_Display"):
		material.emission_enabled = true
		material.emission_texture = atlas
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission = Color(0.86, 0.91, 0.94)
		material.emission_energy_multiplier = 0.35 if label.ends_with("_Display") else 0.16
	elif label.begins_with("Glow"):
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = 0.85
	_materials[label] = material
	return material
