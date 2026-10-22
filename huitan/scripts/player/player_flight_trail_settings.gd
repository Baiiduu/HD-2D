class_name PlayerFlightTrailSettings
extends Resource

## 从实际 Sprite 采样，不依赖专用人物素材；入口沿用飞行拖尾配置。
@export_group("弹射人物残影")
@export var enabled := true
@export_range(1, 8, 1) var flight_echo_count := 4
@export_range(0.08, 1.0, 0.01, "suffix:m") var flight_echo_spacing := 0.32
## 从实际人物配色取样，再独立降低饱和度与亮度；不改人物本身。
@export var flight_trail_color := Color.WHITE
@export_range(0.0, 1.0, 0.05) var flight_echo_saturation := 0.25
@export_range(0.0, 1.0, 0.05) var flight_echo_brightness := 0.65
@export_range(0.1, 6.0, 0.05, "suffix:m") var flight_trail_max_length := 1.35
@export_range(0.05, 0.6, 0.01, "suffix:s") var flight_trail_lifetime := 0.22
@export_range(0.0, 1.0, 0.01) var flight_trail_opacity := 0.16
## 不产生额外光源，默认不额外发光。
@export_range(0.0, 1.0, 0.01) var flight_trail_energy := 0.0
@export_group("反弹残影节奏")
@export var bounce_rhythm_enabled := false
@export_range(0.06, 0.3, 0.01, "suffix:s") var bounce_echo_rebuild_seconds := 0.12
@export_range(0.03, 0.2, 0.01, "suffix:s") var bounce_echo_fade_seconds := 0.09

func validation_error() -> String:
	if flight_echo_count < 1 or flight_echo_count > 8: return "人物残影数量须为 1～8"
	for value in [flight_echo_spacing, flight_trail_max_length, flight_trail_lifetime]:
		if not is_finite(value) or value <= 0.0: return "残影间距、长度和时间须为有限正数"
	for value in [flight_trail_opacity, flight_trail_energy, flight_echo_saturation, flight_echo_brightness]:
		if not is_finite(value) or value < 0.0: return "残影透明度、自发光与色彩参数须为有限非负数"
	for channel in [flight_trail_color.r, flight_trail_color.g, flight_trail_color.b, flight_trail_color.a]:
		if not is_finite(channel): return "残影乘色须为有限数值"
	return ""
