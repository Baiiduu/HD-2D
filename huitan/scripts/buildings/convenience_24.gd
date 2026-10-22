@tool
extends Node3D
## +Z 为店铺正面；主体 5.2 × 3.5 × 6 米，贴图保持原生 256 像素。
## 窗户、灯牌各有独立材质；0 表示关闭发光，不改变固有色。

const TEXTURES := {
	"front": preload("res://assets/models/convenience_24/textures/front.png"),
	"back": preload("res://assets/models/convenience_24/textures/back.png"),
	"left": preload("res://assets/models/convenience_24/textures/left.png"),
	"right": preload("res://assets/models/convenience_24/textures/right.png"),
	"roof": preload("res://assets/models/convenience_24/textures/roof.png"),
	"front_windows": preload("res://assets/models/convenience_24/textures/front_windows.png"),
	"back_windows": preload("res://assets/models/convenience_24/textures/back_windows.png"),
	"left_windows": preload("res://assets/models/convenience_24/textures/left_windows.png"),
	"right_windows": preload("res://assets/models/convenience_24/textures/right_windows.png"),
	"front_signs": preload("res://assets/models/convenience_24/textures/front_signs.png"),
	"right_signs": preload("res://assets/models/convenience_24/textures/right_signs.png"),
}

@export_group("独立发光控制")
@export_range(0.0, 12.0, 0.05) var window_energy := 0.0:
	set(value):
		window_energy = value
		_update_emission()
@export var window_color := Color.WHITE:
	set(value):
		window_color = value
		_update_emission()
@export_range(0.0, 12.0, 0.05) var sign_energy := 0.0:
	set(value):
		sign_energy = value
		_update_emission()
@export var sign_color := Color.WHITE:
	set(value):
		sign_color = value
		_update_emission()

var _windows: Array[StandardMaterial3D] = []
var _signs: Array[StandardMaterial3D] = []

func _ready() -> void:
	var shared := {}
	_prepare_materials($Model, shared)
	_update_emission()

func _prepare_materials(node: Node, shared: Dictionary) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		for i in instance.mesh.get_surface_count():
			var original := instance.mesh.surface_get_material(i) as StandardMaterial3D
			if original == null:
				continue
			if not shared.has(original):
				var material := original.duplicate() as StandardMaterial3D
				var label := original.resource_name
				var face := label.get_slice("_", 0).to_lower()
				var kind := label.get_slice("_", 1).to_lower()
				var image_name := face
				if label == "Structure":
					image_name = "front"
				elif kind in ["windows", "signs"]:
					image_name += "_" + kind
				material.albedo_texture = TEXTURES[image_name]
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				material.roughness = 1.0
				material.metallic = 0.0
				if kind in ["windows", "signs"]:
					material.emission_texture = material.albedo_texture
					material.emission_enabled = true
					material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
					if kind == "windows":
						_windows.append(material)
					else:
						_signs.append(material)
				shared[original] = material
			instance.set_surface_override_material(i, shared[original])
	for child in node.get_children():
		_prepare_materials(child, shared)

func _update_emission() -> void:
	for material in _windows:
		material.emission = window_color
		material.emission_energy_multiplier = window_energy
	for material in _signs:
		material.emission = sign_color
		material.emission_energy_multiplier = sign_energy
