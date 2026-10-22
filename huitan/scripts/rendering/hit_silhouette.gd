extends RefCounted
## 存活贴图与死亡快照共用的短脉冲；调用者传入未缩放时间，战斗冻结时不推进。
var remaining := 0.0
var cooldown := 0.0
var rim_color := Color.WHITE
var amount: float:
	get: return _strength * (1.0 - smoothstep(0.45, 1.0, 1.0 - remaining / _seconds)) if remaining > 0.0 else 0.0
var _seconds := 0.08
var _strength := 0.0
var _settings: PlayerActionVisuals

static func accepts(settings: PlayerActionVisuals, source: StringName) -> bool:
	return settings != null and settings.enemy_hit_silhouette_enabled and settings.enemy_hit_silhouette_strength > 0.0 and (source == &"flight_sword" or source == &"ricochet_storm")

func strike(settings: PlayerActionVisuals, source: StringName) -> bool:
	if not accepts(settings, source) or cooldown > 0.0: return false
	_settings = settings
	_seconds = clampf(settings.enemy_hit_silhouette_seconds, 0.03, 0.3)
	remaining = _seconds
	cooldown = maxf(_seconds, settings.enemy_hit_silhouette_interval)
	_strength = clampf(settings.enemy_hit_silhouette_strength, 0.0, 1.0)
	rim_color = settings.enemy_hit_silhouette_color
	return true

func advance(real_delta: float) -> void:
	if not _settings: return
	if not _settings.enemy_hit_silhouette_enabled:
		clear()
		return
	remaining = maxf(0.0, remaining - maxf(real_delta, 0.0))
	cooldown = maxf(0.0, cooldown - maxf(real_delta, 0.0))
	if remaining == 0.0 and cooldown == 0.0: _settings = null

func clear() -> void:
	remaining = 0.0
	cooldown = 0.0
	_strength = 0.0
	_settings = null
