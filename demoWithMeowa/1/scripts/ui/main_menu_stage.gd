extends Node2D
## Decorative title performance only: no combat simulation or gameplay mutations.
signal cue(cue_name: StringName)

const Timeline = preload("res://scripts/ui/main_menu_timeline.gd")
const FireTrail = preload("res://scripts/ui/main_menu_fire_trail.gd")
const BASE := Vector2(1440, 900)
const CENTER := BASE * 0.5
const ACTOR_SHADER = preload("res://shaders/ui/main_menu_actor.gdshader")
const PLAZA_SHADER = preload("res://shaders/ui/main_menu_plaza.gdshader")
const TEXTURES := {
	&"slime": preload("res://assets/meowa/ui/main_menu/slime.png"),
	&"hero": preload("res://assets/meowa/ui/main_menu/hero_battle.png"),
	&"leaf": preload("res://assets/meowa/ui/main_menu/leaf.png"),
	&"lantern": preload("res://assets/meowa/ui/main_menu/lantern_spitter.tres"),
	&"pot": preload("res://assets/meowa/ui/main_menu/pot.png"),
	&"frog": preload("res://assets/meowa/ui/main_menu/frog.png")}

@export_group("演出")
@export_range(9.0, 20.0, 0.5, "suffix:s") var cycle_seconds := 11.0
@export_range(0.0, 1.5, 0.05) var motion_strength := 1.0
@export_range(0.0, 24.0, 1.0, "suffix:px") var mouse_parallax := 10.0
@export_range(0.0, 10.0, 0.5, "suffix:px") var impact_shake := 4.0
@export var reduced_motion := false
@export_group("环境")
@export_range(0, 180, 1) var rain_count := 90
@export_range(0.0, 1.0, 0.05) var fire_strength := 1.0
@export_range(0.0, 1.0, 0.05) var ambience_strength := 0.75

var timeline := Timeline.new()
var _ambient_time := 0.0
var _background: Sprite2D
var _hero: Sprite2D
var _slime: Sprite2D
var _fire_trail: Node2D
var _crowd: Array[Dictionary] = []
var _mouse := Vector2.ZERO
var _view_size := BASE
var _fit := 1.0
var _origin := Vector2.ZERO

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_background = Sprite2D.new()
	_background.texture = preload("res://assets/meowa/ui/main_menu/plaza.png")
	_background.position = CENTER
	_background.scale = Vector2.ONE * maxf(BASE.x / _background.texture.get_width(), BASE.y / _background.texture.get_height()) * 1.05
	_background.z_index = -30
	var material_instance := ShaderMaterial.new()
	material_instance.shader = PLAZA_SHADER
	_background.material = material_instance
	add_child(_background)
	_fire_trail = FireTrail.new()
	_fire_trail.name = "GroundFire"
	_fire_trail.z_index = -20
	add_child(_fire_trail)
	# Shared silhouettes and palette on both sides; larger front actors establish depth.
	var kinds := [&"slime", &"leaf", &"lantern", &"pot", &"frog"]
	for side in 2:
		for index in 13:
			var row := index / 5
			var x := 75.0 + fmod(index * 83.0, 350.0) if side == 0 else 1025.0 + fmod(index * 93.0, 400.0)
			var y := 385.0 + row * 99.0 + fmod(index * 37.0, 70.0)
			var width := 72.0 + row * 28.0
			var actor := _actor(kinds[(index + side * 2) % kinds.size()], width)
			actor.z_index = int(y / 30.0)
			_crowd.append({"node": actor, "home": Vector2(x, y), "scale": actor.scale,
				"phase": index * 1.83 + side, "delay": fmod(index * 0.073, 0.5), "side": side})
	var front := _actor(&"pot", 265.0)
	front.z_index = 29
	_crowd.append({"node":front, "home":Vector2(1320, 775), "scale":front.scale, "phase":1.0, "delay":0.16, "side":1})
	_hero = _actor(&"hero", 180.0)
	_hero.z_index = 30
	_slime = _actor(&"slime", 375.0)
	_slime.z_index = 35
	_sample_actors(0.0)

func _actor(kind: StringName, width: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = TEXTURES[kind]
	sprite.scale = Vector2.ONE * width / sprite.texture.get_width()
	var instance := ShaderMaterial.new()
	instance.shader = ACTOR_SHADER
	sprite.material = instance
	add_child(sprite)
	return sprite

func fit_view(view_size: Vector2) -> void:
	_view_size = view_size
	_fit = maxf(view_size.x / BASE.x, view_size.y / BASE.y)
	_origin = (view_size - BASE * _fit) * 0.5
	scale = Vector2.ONE * _fit
	position = _origin

func celebrate() -> void:
	timeline.reset(0.85)

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	var strength := 0.0 if reduced_motion else motion_strength
	timeline.period = cycle_seconds
	_ambient_time += minf(delta, 0.1)
	# Reduced motion keeps the composition; rain and subtle lamp shimmer remain.
	if not reduced_motion and strength > 0.0:
		for event in timeline.advance(delta): cue.emit(event)
	var pointer := get_viewport().get_mouse_position() / _view_size.max(Vector2.ONE) * 2.0 - Vector2.ONE
	_mouse = _mouse.lerp(pointer.clamp(-Vector2.ONE, Vector2.ONE), 1.0 - exp(-delta * 4.0))
	var kick := exp(-maxf(timeline.time - 1.55, 0.0) * 17.0) if timeline.time >= 1.55 else 0.0
	position = _origin + Vector2(sin(_ambient_time * 53.0), cos(_ambient_time * 39.0) * 0.4) * kick * impact_shake * strength * _fit
	_background.position = CENTER - _mouse * mouse_parallax * 0.35 * strength
	_background.material.set_shader_parameter("clock", _ambient_time)
	_background.material.set_shader_parameter("motion", ambience_strength)
	_sample_actors(strength)
	_fire_trail.position = -_mouse * mouse_parallax * strength
	_fire_trail.sample(timeline.time if strength > 0.0 else 2.3, fire_strength)
	queue_redraw()

func _sample_actors(strength: float) -> void:
	var t: float = timeline.time if strength > 0.0 else 0.0
	for actor: Dictionary in _crowd:
		var node: Sprite2D = actor.node
		var phase: float = actor.phase
		var home: Vector2 = actor.home
		var hit_time: float = t - 1.94 - float(actor.delay)
		var travel := clampf(hit_time / 1.15, 0.0, 1.0)
		var kick := sin(travel * PI)
		var spread := Vector2(-48.0 if actor.side == 0 else 83.0, -105.0 - fmod(phase * 17.0, 70.0)) * kick
		node.position = home + (spread + Vector2(sin(_ambient_time * 1.2 + phase) * 3.0, sin(_ambient_time * 2.2 + phase) * 5.0) - _mouse * mouse_parallax) * strength
		node.rotation = (sin(_ambient_time * 1.4 + phase) * 0.035 + kick * (0.34 if actor.side == 1 else -0.32)) * strength
		var squash := sin(_ambient_time * 2.2 + phase) * 0.025 * strength
		node.scale = actor.scale * Vector2(1.0 + squash + kick * 0.13 * strength, 1.0 - squash)
		node.material.set_shader_parameter("hit", clampf(1.0 - hit_time * 8.0, 0.0, 1.0) if hit_time > 0.0 else 0.0)
	var turn := -0.10
	var stretch := Vector2.ONE
	if t < 1.05:
		var charge := smoothstep(0.15, 1.05, t)
		stretch = Vector2(1.0 + charge * 0.08, 1.0 - charge * 0.08)
	elif t < 1.55:
		stretch = Vector2(1.18, 0.87)
	elif t < 1.94:
		turn = -0.55
		stretch = Vector2(1.12, 0.9)
	elif t < 2.65:
		turn = -0.25
	_hero.position = Timeline.hero_position(t) - _mouse * mouse_parallax * strength
	_hero.rotation = turn * strength
	_hero.scale = Vector2.ONE * 180.0 / _hero.texture.get_width() * stretch
	_hero.material.set_shader_parameter("charge", smoothstep(0.2, 1.05, t) if t < 1.05 else 0.0)
	# The near slime grows toward the camera, squashes at impact, then crosses the edge.
	var near_point := Vector2(190, 640)
	var near_scale := 1.0
	var near_turn := -0.14
	if t >= 1.94 and t < 3.55:
		var p := clampf((t - 1.94) / 1.61, 0.0, 1.0)
		near_point = Vector2(340, 520).lerp(Vector2(-470, 910), p * p)
		near_scale = lerpf(0.72, 1.95, p)
		near_turn = -0.14 - p * 0.7
	elif t >= 3.55 and t < 6.7:
		near_point = Vector2(-470, 910)
	elif t >= 6.7 and t < 8.4:
		var p := smoothstep(6.7, 8.4, t)
		near_point = Vector2(-470, 740).lerp(Vector2(190, 640), p)
		near_scale = lerpf(0.6, 1.0, p)
	var breath := sin(_ambient_time * 2.0) * 0.025 * strength
	_slime.position = near_point - _mouse * mouse_parallax * 2.3 * strength
	_slime.rotation = near_turn + breath
	_slime.scale = Vector2(1.0 + breath, 1.0 - breath) * near_scale * 375.0 / _slime.texture.get_width()

func _draw() -> void:
	var t: float = timeline.time
	var strength := 0.0 if reduced_motion else motion_strength
	# Rain stays delicate; warm dust uses a separate, lower density rhythm.
	for i in rain_count:
		var x := fposmod(i * 137.41 + _ambient_time * 33.0, 1520.0) - 40.0
		var y := fposmod(i * 91.73 + _ambient_time * (240.0 + fmod(i * 17.0, 140.0)), 980.0) - 40.0
		draw_line(Vector2(x, y), Vector2(x - 4.0, y + 17.0), Color(0.67, 0.82, 1.0, 0.09 * ambience_strength), 1.0)
	for i in 22:
		var p := Vector2(fposmod(i * 193.0, 1440.0), 350.0 + fposmod(i * 87.0 - _ambient_time * 11.0, 470.0))
		var a := (sin(_ambient_time * 1.7 + i) * 0.5 + 0.5) * 0.5 * ambience_strength
		draw_rect(Rect2(p, Vector2.ONE * (2.0 if i % 3 else 3.0)), Color(1.0, 0.72, 0.30, a))
	for i in 14:
		var progress := fposmod(_ambient_time * 0.65 + i * 0.39, 1.0)
		var p := Vector2(fmod(i * 231.0 + 73.0, 1400.0), 470.0 + fmod(i * 139.0, 400.0))
		draw_set_transform(p, 0.0, Vector2(1.0, 0.35))
		draw_arc(Vector2.ZERO, 4.0 + progress * 15.0, 0.0, TAU, 16, Color(0.5, 0.72, 0.88, (1.0 - progress) * 0.13 * ambience_strength), 1.0)
	draw_set_transform(Vector2.ZERO)
	if strength > 0.0:
		_draw_impact(Vector2(1040, 683), t - 1.55, strength)
		_draw_impact(Vector2(1175, 493), t - 1.94, strength * 0.8)
		if t < 1.05:
			var charge := smoothstep(0.0, 1.05, t)
			for i in 11:
				var angle := i * TAU / 11.0 + t * 1.9
				var radius := 75.0 * (1.0 - fposmod(t * 1.2 + i * 0.1, 1.0))
				draw_rect(Rect2(_hero.position + Vector2(cos(angle), sin(angle) * 0.52) * radius, Vector2.ONE * 3.0), Color(1.0, 0.72, 0.3, charge * 0.7))

func _draw_impact(point: Vector2, age: float, strength: float) -> void:
	if age < 0.0 or age > 0.6: return
	var fade := (1.0 - age / 0.6) * strength
	for i in 18:
		var direction := Vector2(cos(i * 2.4), sin(i * 2.4) * 0.7)
		var distance := age * (100.0 + fmod(i * 31.0, 140.0))
		var tail := point + direction * distance + Vector2(0, age * age * 130.0)
		draw_line(tail, tail - direction * 7.0, Color(1.0, 0.58 + fade * 0.35, 0.18, fade), 2.5)
	if age < 0.13:
		var flash := 1.0 - age / 0.13
		draw_line(point - Vector2(17, 0) * flash, point + Vector2(17, 0) * flash, Color(1, 0.95, 0.72, flash), 3.0)
		draw_line(point - Vector2(0, 23) * flash, point + Vector2(0, 23) * flash, Color(1, 0.95, 0.72, flash), 3.0)
