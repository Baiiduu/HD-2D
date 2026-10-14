@tool
extends Node3D

## 固定铺设数据按素材和空间小块批量显示；不添加碰撞体，不改变原生像素尺度。
const ASSETS := "res://assets/meowa/dressing/assets.json"
const LAYOUT := "res://data/dressing_layout.json"
const CHUNK_SIZE := 8.0

@export_group("铺设密度")
@export_range(0.0, 1.0, 0.05) var grass_density := 1.0:
	set(value):
		grass_density = value
		_queue_rebuild()
@export_range(0.0, 1.0, 0.05) var flower_density := 1.0:
	set(value):
		flower_density = value
		_queue_rebuild()
@export_range(0.0, 1.0, 0.05) var pebble_density := 1.0:
	set(value):
		pebble_density = value
		_queue_rebuild()

var instance_count := 0
var _generated: Node3D
var _rebuild_queued := false

func _ready() -> void:
	_rebuild()

func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_rebuild_queued = false
	if _generated:
		_generated.free()
	_generated = Node3D.new()
	_generated.name = "Layers"
	add_child(_generated)
	instance_count = 0
	var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS))
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var assets: Dictionary = {}
	var groups: Dictionary = {}
	var densities := {"grass": grass_density, "flowers": flower_density, "pebbles": pebble_density}
	for category in densities:
		var layer := Node3D.new()
		layer.name = category
		_generated.add_child(layer)
		groups[category] = layer
	for item: Dictionary in pack["assets"]:
		assets[item["id"]] = item
	var batches: Dictionary = {}
	for placement: Dictionary in layout["instances"]:
		var asset_id: String = placement["asset"]
		var category := asset_id.get_slice("_", 0)
		if float(placement["density_rank"]) >= float(densities[category]):
			continue
		var coords: Array = placement["position"]
		var point := Vector3(coords[0], coords[1], coords[2])
		var chunk := Vector2i(floori(point.x / CHUNK_SIZE), floori(point.z / CHUNK_SIZE))
		var key := "%s_%d_%d" % [asset_id, chunk.x, chunk.y]
		if not batches.has(key):
			batches[key] = {"asset": asset_id, "category": category, "points": []}
		batches[key]["points"].append(point)
		instance_count += 1
	for key in batches:
		var batch: Dictionary = batches[key]
		var item: Dictionary = assets[batch["asset"]]
		var mesh := QuadMesh.new()
		mesh.size = Vector2(item["canvas"][0], item["canvas"][1]) * float(item["pixel_size"])
		var material := StandardMaterial3D.new()
		material.albedo_texture = load(item["texture"])
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.roughness = 1.0
		mesh.material = material
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		var points: Array = batch["points"]
		multimesh.instance_count = points.size()
		var anchor_height: float = (float(item["anchor"][1]) - float(item["canvas"][1]) * 0.5) * float(item["pixel_size"])
		for index in points.size():
			multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, points[index] + Vector3.UP * anchor_height))
		var instance := MultiMeshInstance3D.new()
		instance.name = key
		instance.multimesh = multimesh
		groups[batch["category"]].add_child(instance)
