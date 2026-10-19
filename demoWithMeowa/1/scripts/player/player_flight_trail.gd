class_name PlayerFlightTrail
extends Node3D

## 保留飞行拖尾入口，显示内容改为实际人物帧的世界坐标残影。
const CAPACITY := 8
const MAX_PENDING := 64
const SPRITE_PROPERTIES := [&"pixel_size", &"offset", &"centered", &"axis", &"billboard", &"flip_h", &"flip_v",
	&"hframes", &"vframes", &"frame", &"region_enabled", &"region_rect", &"layers", &"transparency"]
var _player: Player
var _body: PlayerRicochet
var _settings: PlayerFlightTrailSettings
var _echoes: Array[Dictionary] = []
var _pending: Array[Dictionary] = []
var _motion: Array[Vector2] = []
var _cursor := 0
var _clock := 0.0
var _piece_seconds := 0.0
var _last_step := 0.0
var _frozen_clock := 0.0
var _distance := 0.0
var _spacing_left := 0.0
var _emitting := false
var _mask_sync_queued := false
var _body_layouts: Dictionary = {}
var _bounce_generation := 0
var _rhythm_events: Array[Dictionary] = []

func _ready() -> void:
	_player = get_parent() as Player
	_body = _player.body_ricochet
	_settings = _player.flight_trail_settings
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_physics_priority = _player.process_physics_priority + 1
	# 人物与受光组件选好实际画面后再取样，残影不自行推断动画或朝向。
	process_priority = 3
	for index in CAPACITY:
		var echo := Sprite3D.new()
		echo.name = "FlightEcho%d" % index
		echo.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		echo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		echo.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		echo.add_to_group(&"flight_echoes")
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/combat/player_flight_trail.gdshader")
		material.render_priority = -1
		echo.material_override = material
		add_child(echo)
		_echoes.append({"sprite": echo, "material": material, "active": false, "born": 0.0, "distance": 0.0})
	_body.launched.connect(_on_launched)
	_body.flight_segment_travelled.connect(_on_segment)
	_body.impact_recorded.connect(_on_impact)
	_body.finished.connect(_on_finished)
	if is_instance_valid(_body._session):
		_body._session.phase_changed.connect(_on_phase)
		_body._session.combat_frozen_changed.connect(_on_freeze)
	clear()

func clear() -> void:
	_pending.clear()
	_motion.clear()
	_rhythm_events.clear()
	_bounce_generation = 0
	_piece_seconds = 0.0
	_emitting = false
	for echo in _echoes:
		echo.active = false
		echo.sprite.hide()
		echo.material.set_shader_parameter("body_mask_enabled", false)
	hide()
	set_process(false)
	set_physics_process(false)

func _on_launched(_heading: Vector3, _speed: float, _charge: float) -> void:
	clear()
	_settings = _player.flight_trail_settings
	if not _settings or not _settings.enabled or not _settings.validation_error().is_empty(): return
	_clock = 0.0
	_last_step = 0.0
	_distance = 0.0
	_spacing_left = 0.0
	_cursor = 0
	_motion.append(Vector2.ZERO)
	_emitting = true
	show()
	set_physics_process(true)
	set_process(true)

func _on_impact(impact: RicochetImpact) -> void:
	if not _emitting or not _settings.bounce_rhythm_enabled: return
	_bounce_generation += 1
	_rhythm_events.append({"time": _clock + _piece_seconds, "generation": _bounce_generation, "strength": impact.strength()})

func _on_segment(start: Vector3, end: Vector3, heading: Vector3, seconds: float) -> void:
	if not _emitting: return
	if not _settings.enabled:
		clear()
		return
	var length := start.distance_to(end)
	var timing := _body.motion_timing(seconds)
	if length > 0.00001:
		# 在每一段真实折线上按距离取样，不把墙前与墙后位置直线插值。
		while _spacing_left <= length:
			var weight := _spacing_left / length
			if _pending.size() == MAX_PENDING: _pending.pop_front()
			var sample_time := PlayerRicochetRules.segment_time(weight, seconds, timing.x, timing.y)
			var sample := {"point": start.lerp(end, weight), "time": _clock + _piece_seconds + sample_time,
				"distance": _distance + _spacing_left, "generation": _bounce_generation}
			if _settings.bounce_rhythm_enabled and _player.sprite.texture:
				var source := _player.sprite
				var properties: Array = []
				for property in SPRITE_PROPERTIES: properties.append(source.get(property))
				var pose := _player.motion_feedback.pose_for_segment(heading, _body.flight_elapsed - seconds + sample_time) if _player.motion_feedback else Vector3.ZERO
				sample.snapshot = {"texture": source.texture, "tint": source.modulate, "properties": properties,
					"lean": pose, "pivot": _player.motion_feedback.foot_pivot(sample.point) if _player.motion_feedback else sample.point}
			_pending.append(sample)
			_spacing_left += _settings.flight_echo_spacing
		_spacing_left -= length
		_distance += length
	_piece_seconds += seconds
	_motion.append(Vector2(_clock + _piece_seconds, _distance))

func _on_finished(reason: StringName) -> void:
	_emitting = false
	if reason == &"cancelled": clear()

func _on_phase(phase: WavePrototype.Phase) -> void:
	if phase != WavePrototype.Phase.BATTLE: clear()

func _on_freeze(frozen: bool) -> void:
	if frozen: _frozen_clock = _interpolated_clock()

func _physics_process(delta: float) -> void:
	if not _settings or not _settings.enabled or _player.current_health <= 0.0:
		clear()
		return
	if _body.is_frozen(): return
	_clock += delta
	_last_step = delta
	_piece_seconds = 0.0
	# 只保留渲染插值所需的最近运动段，停止飞行后仍可查到最终路程。
	while _motion.size() > 2 and _motion[1].x < _clock - delta * 2.0: _motion.pop_front()

func _render_clock() -> float:
	return _frozen_clock if _body.is_frozen() else _interpolated_clock()

func _interpolated_clock() -> float:
	if get_tree().physics_interpolation and _last_step > 0.0:
		return maxf(0.0, _clock - _last_step + Engine.get_physics_interpolation_fraction() * _last_step)
	return _clock

func _render_distance(time: float) -> float:
	if _motion.is_empty(): return _distance
	for index in range(1, _motion.size()):
		var a := _motion[index - 1]
		var b := _motion[index]
		if b.x >= time:
			return lerpf(a.y, b.y, clampf((time - a.x) / maxf(0.000001, b.x - a.x), 0.0, 1.0))
	return _distance

func _process(_delta: float) -> void:
	if not _settings or not _settings.enabled or _player.current_health <= 0.0:
		clear()
		return
	_display_at(_render_clock())
	if visible and not _mask_sync_queued:
		# Sprite3D 的原生网格延迟更新；等本帧贴图、翻转和裁切生效后取布局。
		_mask_sync_queued = true
		_sync_body_mask.call_deferred()

func _sync_body_mask() -> void:
	_mask_sync_queued = false
	if not visible: return
	var source := _player.sprite
	var enabled := source.texture != null and source.is_visible_in_tree() and source.modulate.a > 0.01 and DisplayServer.get_name() != "headless"
	var layout: Array = []
	if enabled:
		var key: Array = [source.texture, source.texture.get_rid(), source.texture.get_size(), source.get_item_rect(), source.pixel_size,
			source.axis, source.hframes, source.vframes, source.frame, source.region_enabled, source.region_rect, source.flip_h, source.flip_v]
		var texture := source.texture
		while texture is AtlasTexture:
			var atlas := texture as AtlasTexture
			key.append_array([atlas.region, atlas.margin, atlas.atlas, atlas.atlas.get_size() if atlas.atlas else Vector2.ZERO])
			texture = atlas.atlas
		if not _body_layouts.has(key):
			# 直接使用引擎生成的顶点与 UV，兼容图集留白、区域裁切和不同 Sprite 轴。
			var arrays := RenderingServer.mesh_surface_get_arrays(source.get_base(), 0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			if _body_layouts.size() >= 64: _body_layouts.clear()
			_body_layouts[key] = [vertices[0], vertices[1] - vertices[0], vertices[3] - vertices[0],
				uvs[0], uvs[1] - uvs[0], uvs[3] - uvs[0]]
		layout = _body_layouts[key]
	for echo in _echoes:
		if not echo.active: continue
		var material: ShaderMaterial = echo.material
		material.set_shader_parameter("body_mask_enabled", enabled)
		if not enabled: continue
		material.set_shader_parameter("body_texture", source.texture)
		material.set_shader_parameter("body_transform", source.get_global_transform_interpolated())
		material.set_shader_parameter("body_motion_lean", source.get_meta("motion_lean", Vector3.ZERO))
		material.set_shader_parameter("body_motion_pivot", source.get_meta("motion_pivot", Vector3.ZERO))
		material.set_shader_parameter("body_billboard_mode", source.billboard)
		material.set_shader_parameter("body_origin", layout[0])
		material.set_shader_parameter("body_edge_u", layout[1])
		material.set_shader_parameter("body_edge_v", layout[2])
		material.set_shader_parameter("body_uv_origin", layout[3])
		material.set_shader_parameter("body_uv_u", layout[4])
		material.set_shader_parameter("body_uv_v", layout[5])

func _display_at(time: float) -> void:
	var travelled := _render_distance(time)
	var rhythm: Dictionary = {}
	if _settings.bounce_rhythm_enabled:
		while _rhythm_events.size() > 2 and _rhythm_events[1].time < time - _settings.flight_trail_lifetime: _rhythm_events.pop_front()
		for event in _rhythm_events:
			if event.time <= time: rhythm = event
	if not _body.is_frozen():
		while not _pending.is_empty() and _pending[0].time <= time:
			var sample: Dictionary = _pending.pop_front()
			if time - sample.time < _settings.flight_trail_lifetime and travelled - sample.distance < _settings.flight_trail_max_length:
				_spawn_echo(sample)
	var active := 0
	for index in _echoes.size():
		var echo := _echoes[index]
		if not echo.active: continue
		var age: float = time - echo.born
		var behind: float = travelled - echo.distance
		if index >= _settings.flight_echo_count or age >= _settings.flight_trail_lifetime or behind >= _settings.flight_trail_max_length:
			echo.active = false
			echo.sprite.hide()
			continue
		var fade := clampf(minf(1.0 - age / _settings.flight_trail_lifetime, 1.0 - behind / _settings.flight_trail_max_length), 0.0, 1.0)
		if not rhythm.is_empty():
			if echo.generation < rhythm.generation:
				var fade_seconds := lerpf(_settings.flight_trail_lifetime, _settings.bounce_echo_fade_seconds, rhythm.strength)
				fade *= 1.0 - smoothstep(rhythm.time, rhythm.time + fade_seconds, time)
			else:
				var rebuild := lerpf(0.35, 1.0, smoothstep(0.0, _settings.bounce_echo_rebuild_seconds, maxf(0.0, echo.born - rhythm.time)))
				fade *= lerpf(1.0, rebuild, rhythm.strength)
		echo.material.set_shader_parameter("opacity", _settings.flight_trail_opacity * pow(fade, 1.25))
		echo.material.set_shader_parameter("echo_color", _settings.flight_trail_color)
		echo.material.set_shader_parameter("saturation", _settings.flight_echo_saturation)
		echo.material.set_shader_parameter("brightness", _settings.flight_echo_brightness)
		echo.material.set_shader_parameter("energy", _settings.flight_trail_energy)
		active += 1
	if not _emitting and _pending.is_empty() and active == 0: clear()

func _spawn_echo(sample: Dictionary) -> void:
	var source := _player.sprite
	if not source.texture or not source.is_visible_in_tree(): return
	_cursor %= _settings.flight_echo_count
	var echo := _echoes[_cursor]
	_cursor = (_cursor + 1) % _settings.flight_echo_count
	var sprite: Sprite3D = echo.sprite
	# Sprite3D 沿用引擎原生 UV：图集、分帧、裁切、翻转和透明留白保持一致。
	sprite.texture = source.texture
	for property in SPRITE_PROPERTIES: sprite.set(property, source.get(property))
	var snapshot: Dictionary = sample.get("snapshot", {})
	if not snapshot.is_empty():
		sprite.texture = snapshot.texture
		for index in SPRITE_PROPERTIES.size(): sprite.set(SPRITE_PROPERTIES[index], snapshot.properties[index])
	var transform := source.get_global_transform_interpolated()
	transform.origin += sample.point - _player.get_global_transform_interpolated().origin
	sprite.global_transform = transform
	echo.material.set_shader_parameter("sprite_texture", sprite.texture)
	echo.material.set_shader_parameter("source_tint", snapshot.get("tint", source.modulate))
	echo.material.set_shader_parameter("billboard_mode", sprite.billboard)
	echo.material.set_shader_parameter("echo_lean", snapshot.get("lean", source.get_meta("motion_lean", Vector3.ZERO)))
	echo.material.set_shader_parameter("echo_pivot", snapshot.get("pivot", source.get_meta("motion_pivot", Vector3.ZERO) + sample.point - _player.get_global_transform_interpolated().origin))
	echo.born = sample.time
	echo.distance = sample.distance
	echo.generation = sample.get("generation", 0)
	echo.active = true
	sprite.show()
