extends RefCounted
## 只保存画面提示的局部时间线；时间、人物运动和攻击规则由原系统拥有。
var red_amount := 0.0
var color := Color(0.9, 0.04, 0.07)
var shake := Vector2.ZERO
var active: bool:
	get: return red_amount > 0.0 or _shake_age < _shake_seconds or _cooldown > 0.0
var _red_age := 0.0
var _red_seconds := 0.2
var _red_gain := 0.0
var _shake_age := 0.0
var _shake_seconds := 0.0
var _shake_pixels := 0.0
var _cooldown := 0.0
var _side := 1.0

func begin(settings: PlayerActionVisuals, orbiting: bool, blocked: bool) -> void:
	if settings.hurt_screen_enabled:
		_red_age = 0.0
		_red_seconds = maxf(settings.hurt_screen_seconds, 0.01)
		_red_gain = clampf(settings.hurt_screen_opacity, 0.0, 0.15)
		red_amount = _red_gain
		color = settings.hurt_screen_color
	if blocked:
		cancel_shake()
	elif settings.hurt_camera_enabled and _cooldown <= 0.0:
		_shake_age = 0.0
		_shake_seconds = maxf(settings.hurt_orbit_shake_seconds if orbiting else settings.hurt_shake_seconds, 0.01)
		_shake_pixels = clampf(settings.hurt_orbit_shake_pixels if orbiting else settings.hurt_shake_pixels, 0.0, 3.0)
		_cooldown = maxf(settings.hurt_shake_interval, _shake_seconds)
		_side = -_side
		shake = Vector2.ZERO

func advance(real_delta: float, settings: PlayerActionVisuals, orbiting: bool, blocked: bool) -> void:
	var step := maxf(real_delta, 0.0)
	_cooldown = maxf(0.0, _cooldown - step)
	_red_age += step
	if not settings.hurt_screen_enabled: _red_gain = 0.0
	red_amount = _red_gain * pow(maxf(0.0, 1.0 - _red_age / _red_seconds), 1.6)
	if blocked or not settings.hurt_camera_enabled:
		cancel_shake()
		return
	_shake_age += step
	if orbiting:
		_shake_pixels = minf(_shake_pixels, settings.hurt_orbit_shake_pixels)
		_shake_seconds = minf(_shake_seconds, maxf(settings.hurt_orbit_shake_seconds, 0.01))
	var p := clampf(_shake_age / maxf(_shake_seconds, 0.01), 0.0, 1.0)
	shake = Vector2(1.0, 0.25).normalized() * _side * _shake_pixels * sin(TAU * p) * sin(PI * p) if p < 1.0 else Vector2.ZERO

func cancel_shake() -> void:
	_shake_age = _shake_seconds
	shake = Vector2.ZERO

func clear() -> void:
	red_amount = 0.0
	_red_gain = 0.0
	_cooldown = 0.0
	cancel_shake()
