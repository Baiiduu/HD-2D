@tool
class_name ExperiencePickup
extends Node3D

@export_group("宝石外观与分档")
## 仅决定外观，不改变实际经验值；达到阈值使用紫色／暖金晶体。
@export_range(1, 10000, 1) var medium_threshold := 10:
	set(value): medium_threshold = maxi(value, 1); _refresh_visual()
@export_range(1, 10000, 1) var large_threshold := 30:
	set(value): large_threshold = maxi(value, 1); _refresh_visual()
@export var cyan_texture: Texture2D:
	set(value): cyan_texture = value; _refresh_visual()
@export var violet_texture: Texture2D:
	set(value): violet_texture = value; _refresh_visual()
@export var amber_texture: Texture2D:
	set(value): amber_texture = value; _refresh_visual()
## 青蓝晶体的世界高度；其它档位逐档放大 15%。
@export_range(0.1, 0.8, 0.01, "suffix:m") var gem_height := 0.32:
	set(value): gem_height = maxf(value, 0.01); _refresh_visual()
@export_group("漂浮与拾取反馈")
@export_range(0.0, 0.2, 0.01, "suffix:m") var float_height := 0.06
@export_range(0.0, 0.1, 0.005, "suffix:m") var bob_amplitude := 0.025
@export_range(0.0, 3.0, 0.1) var bob_speed := 1.0
@export_range(0.1, 1.0, 0.05, "suffix:m") var shadow_width := 0.36:
	set(value): shadow_width = maxf(value, 0.01); _refresh_visual()
@export_range(0.0, 1.0, 0.05) var shadow_opacity := 0.6:
	set(value): shadow_opacity = value; _refresh_visual()
@export_range(0.0, 1.0, 0.05) var trail_opacity := 0.7
## 吸引时的短流光长度，随实际移动逐渐展开，不能越过起始位置。
@export_range(0.0, 1.5, 0.05, "suffix:m") var trail_length := 0.65
## 最亮尾迹光点的世界宽度，后面的光点逐渐缩小。
@export_range(0.03, 0.3, 0.01, "suffix:m") var trail_size := 0.19
@export_range(0.0, 3.0, 0.1) var trail_brightness := 2.0
@export var trail_color := Color(0.25, 0.9, 1.0)
@export_range(0.0, 6.0, 0.1) var trail_pulse_speed := 2.5

var amount := 0:
	set(value): amount = maxi(value, 0); _refresh_visual()
var attracting := false
var collected := false
var visual_tier := 0
var _speed := 0.0
var _clock := 0.0
var _travel_distance := 0.0
var _trail_direction := Vector3.ZERO
var _trails: Array[Sprite3D] = []
@onready var _gem: Sprite3D = get_node_or_null("Gem")
@onready var _shadow: Sprite3D = get_node_or_null("Shadow")
@onready var _trail_a: Sprite3D = get_node_or_null("TrailA")
@onready var _trail_b: Sprite3D = get_node_or_null("TrailB")

func _ready() -> void:
	_trails.assign([_trail_a, _trail_b, get_node_or_null("TrailC"), get_node_or_null("TrailD"), get_node_or_null("TrailE")])
	_clock = fmod(float(get_instance_id()), 1000.0) / 1000.0 * TAU
	_refresh_visual()
	advance_visual(0.0)

func _refresh_visual() -> void:
	visual_tier = 2 if amount >= maxi(large_threshold, medium_threshold) else (1 if amount >= medium_threshold else 0)
	if not is_node_ready() or not _gem: return
	_gem.texture = [cyan_texture, violet_texture, amber_texture][visual_tier]
	if _gem.texture: _gem.pixel_size = gem_height * (1.0 + visual_tier * 0.15) / _gem.texture.get_height()
	_gem.visible = _gem.texture != null
	if _shadow and _shadow.texture:
		_shadow.pixel_size = shadow_width / _shadow.texture.get_width()
		_shadow.modulate.a = shadow_opacity
	advance_visual(0.0)

## 与吸取统一推进；成长选择冻结时不推进漂浮或尾迹。
func advance_visual(delta: float) -> void:
	_clock += delta
	if not _gem: return
	_gem.position.y = gem_height * (1.0 + visual_tier * 0.15) * 0.5 + float_height + sin(_clock * TAU * bob_speed) * bob_amplitude
	if _shadow: _shadow.visible = not attracting
	_update_trails()

func _update_trails() -> void:
	for index in _trails.size():
		var trail := _trails[index]
		if not trail: continue
		trail.visible = attracting and not collected and trail_opacity > 0.0 and trail_length > 0.0 and trail_brightness > 0.0
		if not trail.visible or not _gem: continue
		var fraction := float(index + 1) / (_trails.size() + 1)
		trail.position = _gem.position - _trail_direction * minf(trail_length, _travel_distance) * fraction
		trail.pixel_size = trail_size * lerpf(1.0, 0.3, fraction) / trail.texture.get_width()
		var shimmer := 0.85 + 0.15 * sin((_clock * trail_pulse_speed - fraction) * TAU)
		trail.modulate = trail_color * (trail_brightness * shimmer)
		trail.modulate.a = trail_opacity * pow(1.0 - fraction, 1.1)

## 由统一拾取管理器推进，避免每粒宝石各自查询人物和物理空间。
func advance(delta: float, target: Vector3, attraction_radius: float, collection_radius: float, height_tolerance: float, initial_speed: float, acceleration: float, max_speed: float) -> bool:
	if collected: return false
	var offset := target - global_position
	if not attracting:
		var horizontal := Vector2(offset.x, offset.z).length()
		if horizontal > attraction_radius or absf(offset.y) > height_tolerance: return false
		attracting = true
		_speed = initial_speed
	_speed = minf(_speed + acceleration * delta, max_speed)
	var before := global_position
	global_position = global_position.move_toward(target, _speed * delta)
	if _gem:
		var movement := global_position - before
		_travel_distance += movement.length()
		if not movement.is_zero_approx(): _trail_direction = movement.normalized()
		_update_trails()
		if _shadow: _shadow.hide()
	if global_position.distance_to(target) <= collection_radius:
		collected = true
		return true
	return false
