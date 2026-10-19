class_name ChargePresentation
extends Node
## 地图独立的蓄力场景反馈与环绕慢动作；不查询怪物或改写战斗数值。

const TIME_SCALE := preload("res://scripts/player/ricochet_time_scale.gd")

@export_group("场景连接")
@export var player: Player
@export var weather: Node3D
@export var audio: GameAudio
@export_group("蓄力场景聚焦")
@export var enabled := false:
	set(value):
		enabled = value
		if not is_node_ready(): return
		if not value: reset()
		if is_instance_valid(_body) and (enabled or orbit_slow_enabled) and (_body.charging or _body.flying): set_process(true)
@export_range(0.0, 0.4, 0.01) var edge_darken := 0.06
@export_range(0.0, 0.4, 0.01) var edge_desaturation := 0.03
## 以画面高度计量的清晰中心半径，保持人物与身边怪物可读。
@export_range(0.15, 0.5, 0.01) var clear_radius := 0.25
@export_range(0.02, 0.3, 0.01, "suffix:s") var gather_seconds := 0.06
@export_range(0.05, 0.6, 0.01, "suffix:s") var release_seconds := 0.16
@export_group("满蓄方向聚焦")
@export var direction_focus_enabled := false
@export_range(1.0, 8.0, 0.25, "suffix:m") var direction_focus_length := 4.0
@export_range(0.3, 2.0, 0.05, "suffix:m") var direction_focus_half_width := 0.75
@export_range(0.0, 3.0, 0.05, "suffix:px") var direction_focus_blur_pixels := 0.40
@export_range(0.1, 0.6, 0.01, "suffix:s") var direction_focus_release_seconds := 0.26
## 轻微提升原有场景亮度，不叠加有色光束或改变真实照明。
@export_range(0.0, 0.12, 0.005) var direction_focus_lift := 0.06
@export_group("发射释放编排")
@export var launch_release_enabled := false
@export_range(0.0, 0.15, 0.005, "suffix:s") var launch_audio_hold_seconds := 0.055
@export_range(0.05, 0.5, 0.01, "suffix:s") var launch_audio_return_seconds := 0.20
@export_group("局部聚拢气流")
@export_range(0.5, 5.0, 0.1, "suffix:m") var airflow_radius := 2.5
@export_range(0.0, 0.3, 0.01, "suffix:m") var plant_pull := 0.14
@export_range(0.0, 0.5, 0.01, "suffix:m") var rain_pull := 0.28
@export_group("蓄力声音退让")
@export_range(-12.0, 0.0, 0.5) var music_duck_db := -2.5
@export_range(-12.0, 0.0, 0.5) var ambience_duck_db := -3.0
@export_group("满蓄慢动作对照")
## 默认关闭。开启后仅刚满蓄一次，按真实时间恢复；输入采样与 UI 不暂停。
@export var full_slow_enabled := false
@export_range(0.5, 1.0, 0.05) var full_slow_scale := 0.75
@export_range(0.04, 0.2, 0.01, "suffix:s") var full_slow_seconds := 0.10
@export_group("蓄力持续慢放")
@export var charge_drama_enabled := false
@export_range(0.3, 0.9, 0.05) var charge_drama_start_fraction := 0.55
@export_range(0.5, 1.0, 0.05) var charge_drama_slow_scale := 0.65
## 按真实时间平滑进入，达到目标速度后保持到发射或取消。
@export_range(0.02, 0.3, 0.01, "suffix:s") var charge_drama_enter_seconds := 0.08
@export_range(0.04, 0.25, 0.01, "suffix:s") var charge_drama_fade_seconds := 0.10
@export_group("持续环绕慢动作")
## 仅真实持续环绕时轻微延展世界时间；不以命中、出剑或轮廓续段重新触发。
@export var orbit_slow_enabled := false:
	set(value):
		orbit_slow_enabled = value
		if is_node_ready() and is_instance_valid(_body) and _body.flying: set_process(true)
@export_range(0.5, 1.0, 0.01) var orbit_slow_scale := 0.82
@export_range(0.02, 0.4, 0.01, "suffix:s") var orbit_slow_enter_seconds := 0.12
@export_range(0.02, 0.2, 0.01, "suffix:s") var orbit_slow_exit_seconds := 0.06

var level := 0.0
var direction_level := 0.0
var _focus_direction := Vector3.RIGHT
var _direction_return := false
var _direction_return_age := 0.0
var _direction_return_seconds := 0.0
var _direction_return_from := 0.0
var _scene_return_from := 0.0
var _audio_return_from := 0.0
var _duck_level := 0.0
var _airflow_level := 0.0
var _airflow_return_from := 0.0
var _launch_release := false
var _body: PlayerRicochet
var _session: WavePrototype
var _post: ShaderMaterial
var _full_seen := false
var _slow_remaining := 0.0
var _time_scale := TIME_SCALE.new()
var _slow_camera: FollowCamera
var _wave_finish_override := false
var _drama_age := 0.0
var _drama_ratio := 1.0
var _drama_level := 0.0

## 清波特写临时接管时间；先释放本段基准，避免结束后残留环绕时间比例。
func set_wave_finish_override(value: bool) -> void:
	_wave_finish_override = value
	if value:
		_restore_time()
		_clear_drama()
	elif is_instance_valid(_body) and (enabled or orbit_slow_enabled) and (_body.charging or _body.flying): set_process(true)

func _ready() -> void:
	process_priority = 4 # 在相机及跟随特效之后投影人物中心。
	set_process(false)
	_bind.call_deferred()

func _bind() -> void:
	if not is_instance_valid(player): return
	_body = player.body_ricochet
	if not is_instance_valid(_body): return
	_session = _body._session
	_body.state_changed.connect(_state_changed)
	_body.launched.connect(_launched)
	if is_instance_valid(_session):
		_session.phase_changed.connect(_phase_changed)
		_session.combat_frozen_changed.connect(_combat_frozen_changed)
	if (enabled or orbit_slow_enabled) and (_body.charging or _body.flying): set_process(true)

func _state_changed(state: PlayerRicochet.State) -> void:
	if state == PlayerRicochet.State.CHARGING:
		_clear_drama()
		_full_seen = false
		_direction_return = false
		_launch_release = false
	else:
		if state == PlayerRicochet.State.FLYING: _focus_direction = _body.direction
		_launch_release = launch_release_enabled and state == PlayerRicochet.State.FLYING
		_direction_return = true
		_direction_return_age = 0.0
		_direction_return_seconds = direction_focus_release_seconds if state == PlayerRicochet.State.FLYING else release_seconds
		_direction_return_from = direction_level
		_scene_return_from = level
		_audio_return_from = _duck_level
		_airflow_return_from = _airflow_level
		if state != PlayerRicochet.State.FLYING: _restore_time()
		elif charge_drama_enabled:
			_drama_ratio = 1.0
			_advance_time(0.0)
	if enabled or orbit_slow_enabled: set_process(true)

func _launched(_direction: Vector3, _speed: float, fraction: float) -> void:
	if enabled and fraction >= 1.0: _full_charge()

func _full_charge() -> void:
	if _full_seen: return
	_full_seen = true
	if not full_slow_enabled: return
	_slow_remaining = full_slow_seconds
	_advance_time(0.0)

func _advance_time(real_delta: float) -> void:
	if is_instance_valid(_body): _body.charge_time_scale = 1.0
	if _wave_finish_override: return
	var movement_camera := player.movement_camera as FollowCamera
	if movement_camera and movement_camera.hit_stop_active: return
	if not orbit_slow_enabled and _slow_remaining <= 0.0 and _drama_ratio >= 1.0 and not _time_scale.active: return
	if _slow_remaining > 0.0: _slow_remaining = maxf(0.0, _slow_remaining - real_delta)
	var full_ratio := full_slow_scale if enabled and full_slow_enabled and _slow_remaining > 0.0 else 1.0
	full_ratio = minf(full_ratio, _drama_ratio)
	_time_scale.advance(real_delta, orbit_slow_enabled and _body.orbiting, orbit_slow_scale, orbit_slow_enter_seconds, orbit_slow_exit_seconds, full_ratio)
	_body.charge_time_scale = _time_scale.ratio if _body.charging and charge_drama_enabled and _time_scale.active else 1.0
	var camera := player.movement_camera as FollowCamera
	if _slow_camera != camera and is_instance_valid(_slow_camera): _slow_camera.charge_unscaled_time = false
	_slow_camera = camera
	if is_instance_valid(_slow_camera): _slow_camera.charge_unscaled_time = _time_scale.active

func _restore_time() -> void:
	if is_instance_valid(_body): _body.charge_time_scale = 1.0
	_time_scale.reset()
	_slow_remaining = 0.0
	if is_instance_valid(_slow_camera): _slow_camera.charge_unscaled_time = false
	_slow_camera = null

func _phase_changed(phase: WavePrototype.Phase) -> void:
	if phase != WavePrototype.Phase.BATTLE: reset()

func _combat_frozen_changed(frozen: bool) -> void:
	if frozen:
		_restore_time()
		_clear_drama()

func _process(delta: float) -> void:
	advance(delta, delta / maxf(Engine.time_scale, 0.001))

func advance(delta: float, real_delta: float) -> void:
	if not is_instance_valid(_body) or not is_instance_valid(player) or player.current_health <= 0.0:
		reset()
		return
	if _body.is_frozen():
		_restore_time()
		_clear_drama()
		return
	if enabled and _body.charging and _body.charge_fraction >= 1.0: _full_charge()
	_advance_drama(real_delta)
	_advance_time(real_delta)
	if not enabled:
		if not _time_scale.active and not (orbit_slow_enabled and _body.flying): set_process(false)
		return
	var target := lerpf(0.2, 1.0, smoothstep(0.0, 1.0, _body.charge_fraction)) if _body.charging else 0.0
	var seconds := gather_seconds if target > level else release_seconds
	var previous_level := level
	var previous_direction := direction_level
	if _direction_return and (direction_focus_enabled or launch_release_enabled):
		_direction_return_age += delta
		var remaining := 1.0 - smoothstep(0.0, maxf(_direction_return_seconds, 0.001), _direction_return_age)
		var clear_remaining := remaining
		var audio_remaining := remaining
		if _launch_release:
			var camera := player.movement_camera as FollowCamera
			var settings := camera.ricochet_camera_settings if is_instance_valid(camera) else null
			if settings and settings.enabled and settings.charge_release_handoff_enabled:
				remaining = 1.0 - settings.release_progress(_direction_return_age, settings.charge_release_seconds)
			clear_remaining = 1.0 - smoothstep(0.0, maxf(direction_focus_release_seconds, 0.001), _direction_return_age)
			audio_remaining = 1.0 - smoothstep(launch_audio_hold_seconds, launch_audio_hold_seconds + maxf(launch_audio_return_seconds, 0.001), _direction_return_age)
		level = _scene_return_from * remaining
		direction_level = _direction_return_from * clear_remaining
		_duck_level = _audio_return_from * audio_remaining
		_airflow_level = _airflow_return_from * remaining
	else:
		level = lerpf(level, target, 1.0 - exp(-4.0 * delta / maxf(seconds, 0.001)))
		var direction_target := 1.0 if direction_focus_enabled and _body.charging and _body.charge_fraction >= 1.0 else 0.0
		direction_level = lerpf(direction_level, direction_target, 1.0 - exp(-4.0 * delta / maxf(seconds, 0.001)))
		_duck_level = lerpf(_duck_level, level, 1.0 - exp(-4.0 * delta / maxf(seconds, 0.001)))
		_airflow_level = lerpf(_airflow_level, target, 1.0 - exp(-4.0 * delta / maxf(seconds, 0.001)))
	var camera := player.movement_camera as FollowCamera
	var settings := camera.ricochet_camera_settings if is_instance_valid(camera) else null
	var flight_focus := _body.flying and settings != null and settings.enabled and settings.flight_speed_camera_enabled and settings.flight_charge_focus_enabled
	if flight_focus:
		var focus := camera.get_flight_focus_weight()
		var weight := 1.0 - exp(-delta / maxf(settings.flight_speed_smoothing, 0.001))
		level = lerpf(previous_level, focus, weight)
		direction_level = lerpf(previous_direction, focus if direction_focus_enabled else 0.0, weight)
		_focus_direction = _body.direction
	if _body.charging: _focus_direction = _body.direction
	if target == 0.0 and level < 0.001: level = 0.0
	if not _body.charging and direction_level < 0.001: direction_level = 0.0
	if not _body.charging and _duck_level < 0.001: _duck_level = 0.0
	if not _body.charging and _airflow_level < 0.001: _airflow_level = 0.0
	_write_feedback()
	if level == 0.0 and direction_level == 0.0 and _duck_level == 0.0 and _airflow_level == 0.0 and _drama_level == 0.0 and not _body.charging and not flight_focus and _slow_remaining <= 0.0 and not _time_scale.active and not (orbit_slow_enabled and _body.flying): set_process(false)

func _advance_drama(real_delta: float) -> void:
	var eligible := enabled and charge_drama_enabled and _body.charging and not _wave_finish_override
	if eligible: eligible = get_tree().get_first_node_in_group(&"gameplay_input_blockers") == null
	var fraction := _body.charge_fraction
	if eligible and fraction >= charge_drama_start_fraction:
		_drama_age = minf(charge_drama_enter_seconds, _drama_age + maxf(real_delta, 0.0))
	else: _drama_age = 0.0
	_drama_ratio = 1.0
	if _drama_age > 0.0:
		_drama_ratio = lerpf(1.0, charge_drama_slow_scale, smoothstep(0.0, maxf(charge_drama_enter_seconds, 0.001), _drama_age))
	var target := smoothstep(charge_drama_start_fraction, 1.0, fraction) if eligible else 0.0
	_drama_level = move_toward(_drama_level, target, maxf(real_delta, 0.0) / maxf(charge_drama_fade_seconds, 0.001))

func _clear_drama() -> void:
	_drama_ratio = 1.0
	_drama_level = 0.0
	_drama_age = 0.0
	if _post:
		_post.set_shader_parameter("charge_focus_darken", edge_darken)
		_post.set_shader_parameter("charge_focus_desaturation", edge_desaturation)

func _write_feedback() -> void:
	var camera := player.movement_camera as FollowCamera if is_instance_valid(player) else null
	var material: ShaderMaterial = camera.post_process.material as ShaderMaterial if is_instance_valid(camera) and is_instance_valid(camera.post_process) else null
	if material != _post:
		if _post:
			_post.set_shader_parameter("charge_focus_amount", 0.0)
			_post.set_shader_parameter("charge_direction_amount", 0.0)
		_post = material
	if _post:
		var center := camera.unproject_position(player.get_global_transform_interpolated().origin + Vector3.UP * camera.focus_height)
		_post.set_shader_parameter("charge_focus_center", center / get_viewport().get_visible_rect().size.max(Vector2.ONE))
		_post.set_shader_parameter("charge_focus_amount", level)
		_post.set_shader_parameter("charge_focus_darken", edge_darken + _drama_level * 0.08)
		_post.set_shader_parameter("charge_focus_desaturation", edge_desaturation + _drama_level * 0.16)
		_post.set_shader_parameter("charge_focus_radius", clear_radius)
		_write_direction(camera)
	if is_instance_valid(weather):
		weather.set_charge_airflow(player.global_position, airflow_radius, plant_pull * _airflow_level, rain_pull * _airflow_level)
	if is_instance_valid(audio): audio.set_charge_duck(music_duck_db * _duck_level, ambience_duck_db * _duck_level)

func _write_direction(camera: FollowCamera) -> void:
	_post.set_shader_parameter("charge_direction_amount", direction_level if direction_focus_enabled else 0.0)
	if direction_level <= 0.0: return
	var size := get_viewport().get_visible_rect().size.max(Vector2.ONE)
	var start := player.get_global_transform_interpolated().origin + Vector3.UP * 0.05
	var route_start := camera.unproject_position(start) / size
	var route_end := camera.unproject_position(start + _focus_direction * direction_focus_length) / size
	var aspect := Vector2(size.x / size.y, 1.0)
	var axis := ((route_end - route_start) * aspect).normalized()
	var side := camera.unproject_position(start + Vector3.UP.cross(_focus_direction) * direction_focus_half_width) / size
	var width := absf(((side - route_start) * aspect).dot(Vector2(-axis.y, axis.x)))
	_post.set_shader_parameter("charge_route_start", route_start)
	_post.set_shader_parameter("charge_route_end", route_end)
	_post.set_shader_parameter("charge_route_half_width", maxf(0.035, width))
	_post.set_shader_parameter("charge_direction_blur_pixels", direction_focus_blur_pixels)
	_post.set_shader_parameter("charge_direction_lift", direction_focus_lift)

func reset() -> void:
	_restore_time()
	_clear_drama()
	level = 0.0
	direction_level = 0.0
	_duck_level = 0.0
	_airflow_level = 0.0
	_launch_release = false
	_direction_return = false
	if _post:
		_post.set_shader_parameter("charge_focus_amount", 0.0)
		_post.set_shader_parameter("charge_direction_amount", 0.0)
	if is_instance_valid(weather): weather.set_charge_airflow(Vector3.ZERO, 0.0, 0.0, 0.0)
	if is_instance_valid(audio): audio.set_charge_duck(0.0, 0.0)
	set_process(false)

func _exit_tree() -> void:
	reset()
	if is_instance_valid(_body):
		_body.state_changed.disconnect(_state_changed)
		_body.launched.disconnect(_launched)
	if is_instance_valid(_session):
		_session.phase_changed.disconnect(_phase_changed)
		_session.combat_frozen_changed.disconnect(_combat_frozen_changed)
