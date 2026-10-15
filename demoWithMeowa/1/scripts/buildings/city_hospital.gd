@tool
extends Node3D
## 两段实体组成 L 形医院，入口庭院与碰撞均保留内凹转角。

const ATLAS := preload("res://assets/models/city_hospital/textures/hospital_atlas.png")

@export_range(0.0, 4.0, 0.05) var sign_energy := 0.55:
	set(value):
		sign_energy = value
		_update_emission()
@export_range(0.0, 4.0, 0.05) var window_energy := 0.12:
	set(value):
		window_energy = value
		_update_emission()

var _signs: Array[StandardMaterial3D] = []
var _windows: Array[StandardMaterial3D] = []

func _ready() -> void:
	_signs.clear()
	_windows.clear()
	_prepare_materials($Model, {})
	_update_emission()

func _prepare_materials(node: Node, shared: Dictionary) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if instance.mesh:
			for i in instance.mesh.get_surface_count():
				var original := instance.mesh.surface_get_material(i) as StandardMaterial3D
				if original == null:
					continue
				if not shared.has(original):
					var material := original.duplicate() as StandardMaterial3D
					material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					material.roughness = 1.0
					material.metallic = 0.0
					if original.resource_name in ["HospitalFacade", "WindowGlow"]:
						material.albedo_texture = ATLAS
					if original.resource_name == "MedicalGlow":
						material.emission_enabled = true
						material.emission = Color(0.32, 0.77, 0.69)
						_signs.append(material)
					elif original.resource_name == "WindowGlow":
						material.emission_enabled = true
						material.emission_texture = material.albedo_texture
						material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
						material.emission = Color(0.65, 0.8, 0.82)
						_windows.append(material)
					shared[original] = material
				instance.set_surface_override_material(i, shared[original])
	for child in node.get_children():
		_prepare_materials(child, shared)

func _update_emission() -> void:
	for material in _signs:
		material.emission_energy_multiplier = sign_energy
	for material in _windows:
		material.emission_energy_multiplier = window_energy
