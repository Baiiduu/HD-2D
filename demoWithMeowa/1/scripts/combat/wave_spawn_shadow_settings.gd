@tool
class_name WaveSpawnShadowSettings
extends Resource
## 生成前的贴地剪影；怪物实例本身始终完整尺寸、立即参战。
@export var enabled := false
@export_range(0.15, 1.5, 0.05, "suffix:s") var warning_seconds := 0.55
@export_range(0.0, 0.4, 0.01, "suffix:s") var fade_seconds := 0.12
@export_group("剪影外观")
@export var shadow_color := Color(0.055, 0.065, 0.14)
@export var rim_color := Color(0.92, 0.65, 0.32)
@export_range(0.0, 1.0, 0.01) var shadow_opacity := 0.48
@export_range(0.0, 1.0, 0.01) var rim_opacity := 0.62
@export_range(0.5, 1.5, 0.05) var footprint_scale := 1.0
@export_range(0.3, 1.0, 0.05) var footprint_depth_ratio := 0.72
@export_range(0.0, 0.4, 0.01) var contraction := 0.18

func validation_error() -> String:
	if not is_finite(warning_seconds) or warning_seconds <= 0.0: return "剪影预告时长须为有限正数"
	if not is_finite(fade_seconds) or fade_seconds < 0.0: return "剪影消散时长须为有限非负数"
	for value in [shadow_opacity, rim_opacity, contraction]:
		if not is_finite(value) or value < 0.0 or value > 1.0: return "剪影透明度与收束比例须在 0～1 之间"
	for value in [footprint_scale, footprint_depth_ratio]:
		if not is_finite(value) or value <= 0.0: return "剪影尺寸须为有限正数"
	for color in [shadow_color, rim_color]:
		for value in [color.r, color.g, color.b, color.a]:
			if not is_finite(value): return "剪影颜色须为有限数值"
	return ""
