class_name DamageNumber
extends Control

## 由 DamageNumbers 集中推进，不创建 Tween、计时器或独立逐帧回调。
var event: CombatDamageEvent
var style: DamageNumberStyle
var age := 0.0
var lane := 0
var active := false
var anchor_screen := Vector2.ZERO
var motion_offset := Vector2.ZERO
var opacity := 1.0
var _text := ""
var _font: Font
var _baseline := Vector2.ZERO
var _travel_sign := 1.0
var _lane_offset := Vector2.ZERO
var _cull_margin := Vector2(100, 100)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)
	set_physics_process(false)
	hide()

func begin(hit: CombatDamageEvent, profile: DamageNumberStyle, slot: int, spacing: Vector2, camera: Camera3D) -> void:
	event = hit
	style = profile
	age = 0.0
	lane = slot
	active = true
	_text = style.format_amount(event.display_amount())
	_font = style.number_font if style.number_font else ThemeDB.fallback_font
	var extent := _font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, style.number_font_size)
	# 大字与多位数字即使锚点移出画面，仍保留可见的字面部分。
	var radius := extent.length() * maxf(style.pop_scale, 1.18) * 0.5 + style.number_outline_size + style.number_shadow_offset.length() + 18.0
	_cull_margin = Vector2.ONE * maxf(100.0, radius)
	_baseline = Vector2(-extent.x * 0.5, (_font.get_ascent(style.number_font_size) - _font.get_descent(style.number_font_size)) * 0.5)
	# 0、右一、左一、右二、左二；不延迟真实命中的首次反馈。
	var column := ceili(slot * 0.5) * (1 if slot % 2 == 1 else -1)
	var column_width := maxf(spacing.x, (extent.x + style.number_outline_size * 2.0) * style.pop_scale + 6.0)
	_lane_offset = Vector2(column * column_width, -absi(column) * spacing.y)
	_travel_sign = -1.0 if slot % 2 == 0 else 1.0
	if is_instance_valid(camera) and hit.direction.length_squared() > 0.00001:
		var horizontal := camera.global_basis.x.dot(hit.direction)
		if absf(horizontal) > 0.05: _travel_sign = signf(horizontal)
	advance(0.0, camera)

func advance(delta: float, camera: Camera3D) -> bool:
	age += delta
	var lifetime := maxf(style.number_lifetime, 0.05)
	if age >= lifetime: return false
	var progress := age / lifetime
	# 参数调大时仍留出收尾阶段；各阶段比例不越过生命周期。
	var squash_end := minf(style.squash_seconds, lifetime * 0.15)
	var rise_end := squash_end + minf(style.rise_seconds, lifetime * 0.4)
	var apex_end := rise_end + minf(style.apex_seconds, lifetime * 0.15)
	var height := 0.0
	var shape := Vector2.ONE
	if age < squash_end:
		var phase := age / maxf(squash_end, 0.001)
		shape = Vector2(lerpf(1.18, 1.0, phase), lerpf(0.62, style.pop_scale, phase))
	elif age < rise_end:
		var phase := (age - squash_end) / maxf(rise_end - squash_end, 0.001)
		height = -style.rise_pixels * sin(phase * PI * 0.5)
		shape = Vector2.ONE * lerpf(style.pop_scale, 1.0, phase)
	elif age < apex_end:
		height = -style.rise_pixels
	else:
		var phase := clampf((age - apex_end) / maxf(lifetime - apex_end, 0.001), 0.0, 1.0)
		height = -style.rise_pixels + style.fall_pixels * phase * phase
		shape = Vector2.ONE * lerpf(1.0, 0.86, phase)
	motion_offset = _lane_offset + Vector2(_travel_sign * style.drift_pixels * progress, height)
	scale = shape
	rotation = deg_to_rad(style.tilt_degrees) * _travel_sign * (progress - 0.25)
	opacity = 1.0 - smoothstep(style.fade_start, 1.0, progress)
	visible = is_instance_valid(camera) and not camera.is_position_behind(event.world_position)
	if visible:
		anchor_screen = camera.unproject_position(event.world_position)
		position = (anchor_screen + motion_offset).round()
		visible = Rect2(-_cull_margin, get_viewport_rect().size + _cull_margin * 2.0).has_point(position)
	queue_redraw()
	return true

func release() -> void:
	active = false
	event = null
	style = null
	_font = null
	hide()

func _draw() -> void:
	if not active or not _font: return
	var tint := Color(1, 1, 1, opacity)
	draw_string_outline(_font, _baseline + style.number_shadow_offset, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, style.number_font_size, style.number_outline_size, style.number_shadow_color * tint)
	if style.number_outline_size > 0:
		draw_string_outline(_font, _baseline, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, style.number_font_size, style.number_outline_size, style.number_outline_color * tint)
	draw_string(_font, _baseline, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, style.number_font_size, style.number_color * tint)
	var phase := age / maxf(style.number_lifetime, 0.05)
	if phase < style.fade_start: return
	var scatter := inverse_lerp(style.fade_start, 1.0, phase)
	for index in style.number_spark_count:
		var angle := (index + 0.35) * TAU / maxi(style.number_spark_count, 1)
		var point := Vector2(cos(angle), sin(angle)) * (5.0 + scatter * 13.0)
		point.y -= scatter * 6.0
		draw_rect(Rect2(point.round(), Vector2(2, 2)), style.number_spark_color * tint)
