@tool
extends "res://scripts/buildings/spawn_home.gd"

const HUT_ART := "res://assets/meowa/training/"
const HUT_MATERIALS := ["plaster", "brick", "roof", "wood", "stone", "glass", "canvas", "metal", "leather"]

@export_group("训练雨棚")
## 雨棚从正面墙向前伸出的距离；两侧柱子不占据中间通路。
@export_range(1.5, 3.0, 0.1) var canopy_depth := 2.0:
	set(value): canopy_depth = value; _queue_build()
## 门前石地坪高于地形的高度（米）；避免共面闪烁，碰撞同步抬高。
@export_range(0.015, 0.1, 0.005) var floor_height := 0.03:
	set(value): floor_height = value; _queue_build()

func build() -> void:
	_queued = false
	var old := get_node_or_null("Geometry")
	if old:
		old.free()
	_streams.clear()
	_triangle_count = 0
	for key: String in HUT_MATERIALS:
		var stream := SurfaceTool.new()
		stream.begin(Mesh.PRIMITIVE_TRIANGLES)
		_streams[key] = stream
	var x := width * 0.5
	var z := depth * 0.5
	_box(Vector3(0, 0.125, 0), Vector3(width, 0.25, depth), "brick")
	_box(Vector3(0, (eave_height + 0.25) * 0.5, 0), Vector3(width, eave_height - 0.25, depth), "plaster")
	_gable_roof(x + 0.3, -z - 0.25, z + 0.25, eave_height, roof_rise)
	for back: bool in [false, true]:
		var side := -1.0 if back else 1.0
		_gable_face(Vector3(side*x,eave_height,side*z),Vector3(-side*x,eave_height,side*z),Vector3(0,eave_height+roof_rise,side*z),x+0.3,"plaster" if back else "wood")
	for side: float in [-1.0, 1.0]:
		for front: float in [-1.0, 1.0]:
			_box(Vector3(side*(x-0.07), eave_height*0.5, front*(z-0.07)), Vector3(0.16,eave_height,0.16), "wood")
		_box(Vector3(side*x,eave_height-0.06,0), Vector3(0.18,0.18,depth), "wood")
		_window(Vector3(side*(x+0.06),1.6,0), side*PI*0.5, side < 0)
	_box(Vector3(0,eave_height-0.06,-z), Vector3(width,0.18,0.18), "wood")
	_box(Vector3(0,eave_height+roof_rise*0.6,-z-0.05), Vector3(0.42,0.45,0.1), "wood")
	# 双木门偏左，训练沙袋与矮凳位于雨棚右侧。
	var door_x := -width * 0.21
	_box(Vector3(door_x,1.15,z+0.06), Vector3(1.85,2.1,0.12), "wood")
	for side: float in [-1.0, 1.0]:
		_box(Vector3(door_x+side*1.0,1.17,z+0.14), Vector3(0.14,2.25,0.21), "wood")
		_box(Vector3(door_x+side*0.13,1.0,z+0.16), Vector3(0.08,0.2,0.08), "metal")
		for height: float in [0.42,1.87]:
			_box(Vector3(door_x+side*0.7,height,z+0.14), Vector3(0.26,0.055,0.06), "metal")
	_box(Vector3(door_x,2.24,z+0.14), Vector3(2.15,0.18,0.22), "wood")
	_box(Vector3(door_x,1.15,z+0.13), Vector3(0.035,2.1,0.03), "metal")
	var canopy_eave := eave_height - 0.3
	var front_z := z + canopy_depth
	_box(Vector3(0,floor_height-0.06,z+canopy_depth*0.5), Vector3(width,0.12,canopy_depth+0.15), "stone")
	_gable_roof(x-0.08,z-0.08,front_z+0.18,canopy_eave,roof_rise*0.85)
	_gable_face(Vector3(x-0.17,canopy_eave,front_z),Vector3(-x+0.17,canopy_eave,front_z),Vector3(0,canopy_eave+roof_rise*0.85,front_z),x-0.08,"wood")
	for side: float in [-1.0, 1.0]:
		var post_x := side*(x-0.28)
		_box(Vector3(post_x,canopy_eave*0.5,front_z-0.12), Vector3(0.18,canopy_eave,0.18), "wood")
		_box(Vector3(post_x,0.16,front_z-0.12), Vector3(0.38,0.32,0.38), "stone")
		_box(Vector3(post_x,canopy_eave-0.09,z+canopy_depth*0.5), Vector3(0.18,0.2,canopy_depth), "wood")
	_box(Vector3(0,canopy_eave-0.07,front_z-0.12), Vector3(width-0.3,0.18,0.18), "wood")
	var bag_x := width * 0.23
	var bag_z := z + canopy_depth * 0.55
	_cylinder(Vector3(bag_x,1.34,bag_z),0.28,1.1,"canvas")
	for height: float in [0.83,1.85]:
		_cylinder(Vector3(bag_x,height,bag_z),0.29,0.12,"leather")
	_box(Vector3(0,canopy_eave-0.12,bag_z),Vector3(width-0.3,0.18,0.16),"wood")
	var chain_top := canopy_eave-0.21
	_box(Vector3(bag_x,(chain_top+1.89)*0.5,bag_z), Vector3(0.035,chain_top-1.89,0.035), "metal")
	_box(Vector3(bag_x,0.46,z+0.4), Vector3(1.45,0.12,0.48), "wood")
	for side: float in [-1.0,1.0]:
		_box(Vector3(bag_x+side*0.54,0.21,z+0.4), Vector3(0.12,0.42,0.38), "wood")
	var chimney := Vector3(x*0.48,eave_height+roof_rise-0.25,-z*0.6)
	_box(chimney,Vector3(0.5,1.3,0.5),"brick")
	_box(chimney+Vector3(0,0.7,0),Vector3(0.65,0.15,0.65),"stone")
	var sign_center := Vector3(0,canopy_eave+roof_rise*0.35,front_z+0.04)
	_box(sign_center,Vector3(1.0,0.7,0.09),"wood")
	var geometry := Node3D.new()
	geometry.name = "Geometry"
	add_child(geometry)
	geometry.owner = self
	for key: String in HUT_MATERIALS:
		var stream: SurfaceTool = _streams[key]
		stream.index()
		var mesh := stream.commit()
		var material := StandardMaterial3D.new()
		material.resource_name = key
		material.albedo_texture = _surface_texture(key, ART if key in MATERIALS else HUT_ART)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS if pixel_filter else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if key == "roof":
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC if pixel_filter else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		material.texture_repeat = true
		material.roughness = 0.35 if key in ["glass","metal"] else roughness
		material.metallic = 0.65 if key == "metal" else 0.0
		mesh.surface_set_material(0,_lumina_material(material,key))
		var instance := MeshInstance3D.new()
		instance.name = key.capitalize()
		instance.mesh = mesh
		geometry.add_child(instance)
		instance.owner = self
	_add_sign(geometry, sign_center)
	var body := StaticBody3D.new()
	body.name = "Collision"
	geometry.add_child(body)
	body.owner = self
	_collision(body,"House",Vector3(0,eave_height*0.5,0),Vector3(width,eave_height,depth))
	_collision(body,"CanopyFloor",Vector3(0,floor_height-0.06,z+canopy_depth*0.5),Vector3(width,0.12,canopy_depth+0.15), &"wood")
	for side: float in [-1.0,1.0]:
		_collision(body,"PostLeft" if side < 0 else "PostRight",Vector3(side*(x-0.28),canopy_eave*0.5,front_z-0.12),Vector3(0.38,canopy_eave,0.38), &"wood")
	_collision(body,"Bag",Vector3(bag_x,1.34,bag_z),Vector3(0.58,1.22,0.58), &"fabric")
	_collision(body,"Bench",Vector3(bag_x,0.26,z+0.4),Vector3(1.45,0.52,0.48), &"wood")
	if has_node("InteractionPoint"):
		$InteractionPoint.position = Vector3(bag_x,0.75,bag_z+0.8)
	set_meta("triangle_count",_triangle_count+2)

func _gable_roof(x: float, back: float, front: float, y: float, rise: float) -> void:
	# 第一条 UV 边沿坡面，瓦片横排沿屋脊，不再旋转 90°。
	_roof_slab([Vector3(x,y,front),Vector3(0,y+rise,front),Vector3(0,y+rise,back),Vector3(x,y,back)])
	_roof_slab([Vector3(-x,y,back),Vector3(0,y+rise,back),Vector3(0,y+rise,front),Vector3(-x,y,front)])
	_box(Vector3(0,y+rise+0.04,(back+front)*0.5),Vector3(0.16,0.15,front-back),"roof")

func _cylinder(center: Vector3, radius: float, height: float, key: String) -> void:
	for i in 16:
		var a := Vector3(cos(TAU*i/16.0)*radius,0,sin(TAU*i/16.0)*radius)
		var b := Vector3(cos(TAU*(i+1)/16.0)*radius,0,sin(TAU*(i+1)/16.0)*radius)
		var up := Vector3.UP*height*0.5
		_face([center+a+up,center+a-up,center+b-up,center+b+up],key)
		_face([center+up,center+a+up,center+b+up],key)
		_face([center-up,center+b-up,center+a-up],key)

func _add_sign(parent: Node3D, center: Vector3) -> void:
	# 完整标识使用独立 0..1 UV，避免重复铺贴拳头图案。
	var stream := SurfaceTool.new()
	stream.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [Vector3(-0.5,0.35,0),Vector3(0.5,0.35,0),Vector3(0.5,-0.35,0),Vector3(-0.5,-0.35,0)]
	var uv := [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]
	for index in [0,1,2,0,2,3]:
		stream.set_normal(Vector3.BACK)
		stream.set_uv(uv[index])
		stream.add_vertex(center+points[index]+Vector3(0,0,0.05))
	var sign_mesh := stream.commit()
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(HUT_ART+"sign.png")
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.roughness = roughness
	sign_mesh.surface_set_material(0,material)
	var sign := MeshInstance3D.new()
	sign.name = "TrainingSign"
	sign.mesh = sign_mesh
	parent.add_child(sign)
	sign.owner = self

func export_glb() -> void:
	var model := Node3D.new()
	model.name = "TrainingHut"
	for child in $Geometry.get_children():
		if child is MeshInstance3D:
			var mesh := MeshInstance3D.new()
			mesh.name = child.name
			mesh.mesh = child.mesh
			model.add_child(mesh)
			mesh.owner = model
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_scene(model,state)
	if error == OK:
		error = document.write_to_filesystem(state,HUT_ART+"training.glb")
	model.free()
	if error != OK:
		push_error("Training hut export failed: "+error_string(error))
