extends Node3D
## 独立人工检查台：相机沿用正式实现，只改变此场景的预设取景。

const LABEL_FONT := preload("res://assets/fonts/maoken_assorted_sans/MaokenAssortedSans.ttf")

@onready var camera: FollowCamera = $Camera3D
@onready var actor: Player = $Player
@onready var focus: Node3D = $Focus
var status: Label
var guides: Node3D
var panel: PanelContainer
var comparison_material := StandardMaterial3D.new()

func _ready() -> void:
	actor.bounds = Rect2(-13, -11, 26, 22)
	comparison_material.albedo_color = Color(0.79, 0.8, 0.81)
	comparison_material.roughness = 0.85
	_build_ui()
	_build_guides()
	show_view("overview")

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ReviewUI"
	add_child(layer)
	panel = PanelContainer.new()
	panel.position = Vector2(18, 18)
	layer.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.065, 0.93)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)
	var title := Label.new()
	title.text = "袖珍宇宙培育馆 · 材质与比例检查"
	title.add_theme_font_size_override("font_size", 21)
	rows.add_child(title)
	var description := Label.new()
	description.text = "医院 / 培育馆 / 原便利店：同地面、正式缩放\nWASD 行走 · 空格跳跃 · Q/E 转向 · H 隐藏面板\n占地 3.60 × 3.20m · 总高 3.80m\n主门净宽 0.80m / 净高 1.30m"
	rows.add_child(description)
	status = Label.new()
	rows.add_child(status)
	var distances := HBoxContainer.new()
	rows.add_child(distances)
	for item in [["三栋对照", "overview"], ["近看白模", "close"], ["跟随人物", "follow"]]:
		add_button(distances, item[0], show_view.bind(item[1]))
	var elevations := HBoxContainer.new()
	rows.add_child(elevations)
	for item in [["正面", "front"], ["左侧", "west"], ["右侧", "east"], ["背面", "back"], ["顶面", "top"]]:
		add_button(elevations, item[0], show_view.bind(item[1]))
	var options := HBoxContainer.new()
	rows.add_child(options)
	var ruler := CheckBox.new()
	ruler.text = "尺寸与人物碰撞尺"
	ruler.focus_mode = Control.FOCUS_NONE
	ruler.toggled.connect(func(value: bool): guides.visible = value)
	options.add_child(ruler)
	var white := CheckBox.new()
	white.text = "对照建筑灰模"
	white.focus_mode = Control.FOCUS_NONE
	white.toggled.connect(_set_comparison_white)
	options.add_child(white)
	var own_white := CheckBox.new()
	own_white.text = "培育馆白模"
	own_white.focus_mode = Control.FOCUS_NONE
	own_white.toggled.connect(_set_nursery_white)
	rows.add_child(own_white)
	add_button(rows, "人物回到主入口", _reset_actor)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_H:
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()

func add_button(parent: Node, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)

func show_view(view: String) -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.target = focus
	focus.position = Vector3.ZERO
	camera.focus_height = 0.75
	camera.distance = 30.0
	camera.pitch_degrees = 30.627
	camera.yaw_degrees = 135.0
	match view:
		"overview": status.text = "正式镜头：FOV 28° · 30m · 俯角 30.627°"
		"follow":
			camera.target = actor
			status.text = "跟随真实人物 · 正式镜头参数"
		"close":
			camera.distance = 12.0
			camera.focus_height = 1.9
			status.text = "近看白模：12m · Q/E 检查转角与开口"
		_:
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 6.2
			camera.distance = 12.0
			camera.focus_height = 1.9
			camera.pitch_degrees = 0.0
			camera.yaw_degrees = {"front": 90.0, "west": 0.0, "east": 180.0, "back": -90.0, "top": 90.0}[view]
			if view == "top":
				camera.pitch_degrees = 89.9
				camera.focus_height = 0.0
			status.text = "正交结构检查 · %s" % {"front": "正面", "west": "左侧", "east": "右侧", "back": "背面", "top": "顶面"}[view]
	camera.reset_horizontal_rotation()
	camera.snap_to_target()

func _reset_actor() -> void:
	actor.position = Vector3(2.1, 0, 0.55)
	actor.velocity = Vector3.ZERO
	actor.reset_physics_interpolation()
	if camera.target == actor: camera.snap_to_target()

func _set_comparison_white(enabled: bool) -> void:
	for name in [&"Hospital", &"ConvenienceStore"]:
		for mesh: MeshInstance3D in get_node("Samples/" + String(name) + "/Model").find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = comparison_material if enabled else null

func _set_nursery_white(enabled: bool) -> void:
	var material: Material = load("res://assets/models/pocket_universe_nursery/pocket_universe_material.tres")
	for mesh: MeshInstance3D in $Samples/Nursery/Model.get_children():
		mesh.material_override = mesh.get_meta("blockout_material") if enabled else mesh.get_meta("production_material", material)

func _build_guides() -> void:
	guides = Node3D.new()
	guides.name = "ScaleGuides"
	guides.transform = $Samples/Nursery.transform
	guides.visible = false
	add_child(guides)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	line(mesh, Vector3(-1.8, 0.015, 1.6), Vector3(1.8, 0.015, 1.6))
	line(mesh, Vector3(-1.8, 0.015, -1.6), Vector3(-1.8, 0.015, 1.6))
	line(mesh, Vector3(-2.05, 0, 1.6), Vector3(-2.05, 3.8, 1.6))
	for height in [0.0, 1.3, 1.45, 2.05, 3.18, 3.6, 3.8]:
		line(mesh, Vector3(-2.11, height, 1.6), Vector3(-1.99, height, 1.6))
	line(mesh, Vector3(-0.4, 0, 1.62), Vector3(-0.4, 1.3, 1.62))
	line(mesh, Vector3(-0.4, 1.3, 1.62), Vector3(0.4, 1.3, 1.62))
	line(mesh, Vector3(0.4, 1.3, 1.62), Vector3(0.4, 0, 1.62))
	mesh.surface_end()
	var lines := MeshInstance3D.new()
	lines.mesh = mesh
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color(0.96, 0.87, 0.65)
	lines.material_override = ink
	guides.add_child(lines)
	guide_label("总高 3.80m", Vector3(-2.05, 4.03, 1.6))
	guide_label("净宽 0.80m / 净高 1.30m", Vector3(0, 1.64, 1.84))
	guide_label("宽 3.60m", Vector3(0, 0.08, 2.0))
	guide_label("深 3.20m", Vector3(-2.15, 0.08, 0))
	var capsule := MeshInstance3D.new()
	var shape := CapsuleMesh.new()
	shape.radius = 0.24
	shape.height = 1.06592
	capsule.mesh = shape
	capsule.position = Vector3(-0.75, 0.53296, 2.0)
	var ghost := StandardMaterial3D.new()
	ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost.albedo_color = Color(0.65, 0.86, 0.94, 0.22)
	capsule.material_override = ghost
	guides.add_child(capsule)
	guide_label("人物胶囊 1.066m", Vector3(-0.75, 1.2, 2.0))

func line(mesh: ImmediateMesh, a: Vector3, b: Vector3) -> void:
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)

func guide_label(text: String, point: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = LABEL_FONT
	label.font_size = 32
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = point
	guides.add_child(label)
