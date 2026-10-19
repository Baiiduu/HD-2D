@tool
class_name SwordRibbonVisual
extends Resource

## 原生剑光的独立外观资源；不保存伤害、攻速或攻击距离。
@export_group("形状")
@export_range(0.05, 0.65, 0.01, "suffix:m") var ribbon_width := 0.22
@export_range(20.0, 150.0, 1.0, "suffix:°") var ribbon_degrees := 78.0
@export_range(0.2, 0.9, 0.05) var ribbon_inner_ratio := 0.56
@export_range(0.005, 0.04, 0.001, "suffix:m") var ribbon_pixel_size := 0.016
@export_group("颜色与层次")
@export var ribbon_blade_color := Color(1.0, 0.95, 0.80, 1.0)
@export var ribbon_middle_color := Color(1.0, 0.55, 0.18, 0.88)
@export var ribbon_tail_color := Color(0.88, 0.10, 0.23, 0.72)
@export_range(0.0, 2.0, 0.05) var ribbon_emission := 0.65
@export var ribbon_blade_enabled := true
@export var ribbon_trail_enabled := true
@export_group("消散")
## 独立视觉时长，不拖慢下一刀。
@export_range(0.08, 0.5, 0.01, "suffix:s") var ribbon_tail_seconds := 0.24
@export_group("分层流动笔触")
## 关闭可对照原来的程序窄弧；开启后使用独立笔触与流动材质。
@export var ribbon_layered_enabled := false
@export var ribbon_brush: Texture2D
@export var ribbon_noise: Texture2D
@export_range(0.0, 4.0, 0.05) var ribbon_flow_speed := 1.6
@export_range(0.0, 0.3, 0.01) var ribbon_distortion := 0.07
@export_range(0.0, 1.0, 0.05) var ribbon_wake_strength := 0.45
@export_range(0.0, 1.0, 0.05) var ribbon_spark_strength := 0.65
## 补偿正式俯视投影，只改变显示高度，XZ 判定和裁切保持。
@export_range(0.0, 35.0, 1.0, "suffix:°") var ribbon_view_tilt := 20.0

## 弧长、宽度和亮刃保留。使用显式进度，冻结时不会继续播放。
func profile(progress: float, release: float) -> Vector3:
	progress = clampf(progress, 0.0, 1.0)
	release = clampf(release, 0.0, 1.0)
	if ribbon_layered_enabled:
		return Vector3(
			lerpf(0.22, 1.10, smoothstep(0.02, 0.78, progress)),
			lerpf(0.20, 1.0, smoothstep(0.0, 0.32, progress)) * lerpf(1.0, 0.55, release),
			1.0 - smoothstep(0.02, 0.42, release))
	return Vector3(
		lerpf(0.30, 1.0, smoothstep(0.02, 0.70, progress)) * lerpf(1.0, 0.82, release),
		lerpf(0.45, 1.0, smoothstep(0.0, 0.32, progress)) * lerpf(1.0, 0.12, release),
		1.0 - smoothstep(0.02, 0.48, release))

func validation_error() -> String:
	if ribbon_layered_enabled:
		if not ribbon_brush or not ribbon_noise: return "分层剑光需要笔触遮罩与流动噪声贴图"
		for value in [ribbon_flow_speed, ribbon_distortion, ribbon_wake_strength, ribbon_spark_strength, ribbon_view_tilt]:
			if not is_finite(value) or value < 0.0: return "分层剑光的流动、扰动、尾迹、亮点和倾角须为有限非负数"
	for value in [ribbon_width, ribbon_degrees, ribbon_pixel_size, ribbon_tail_seconds]:
		if not is_finite(value) or value <= 0.0: return "原生剑光的宽度、弧长、像素尺寸和消散时长须为有限正数"
	if not is_finite(ribbon_inner_ratio) or ribbon_inner_ratio < 0.2 or ribbon_inner_ratio > 0.9: return "原生剑光内端比例须在 0.2～0.9 之间"
	if not is_finite(ribbon_emission) or ribbon_emission < 0.0: return "原生剑光发光须为有限非负数"
	for color in [ribbon_blade_color, ribbon_middle_color, ribbon_tail_color]:
		if not (is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and is_finite(color.a)): return "原生剑光颜色须为有限值"
	return ""
