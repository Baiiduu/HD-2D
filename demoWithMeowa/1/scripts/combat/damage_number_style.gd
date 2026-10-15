@tool
class_name DamageNumberStyle
extends Resource

## 一个标签对应一套外观和运动；新增表现不必改伤害结算。
@export var style_id: StringName = &"normal"
@export_group("字形与颜色")
## 空槽用 Godot 默认字体验证框架；可替换为定稿像素 Font／位图字体。
@export var number_font: Font
@export_range(10, 64, 1) var number_font_size := 24
@export var number_color := Color("fff0c8")
@export var number_outline_color := Color("11162c")
@export_range(0, 8, 1) var number_outline_size := 4
@export var number_shadow_color := Color(0.04, 0.025, 0.09, 0.75)
@export var number_shadow_offset := Vector2(2.0, 3.0)
@export var number_suffix := ""
## 只控制显示精度，真实伤害始终保存在事件中；小额伤害不会显示为 0。
@export_range(0, 2, 1) var decimal_places := 0

@export_group("弹跳节奏")
@export_range(0.2, 2.0, 0.01, "suffix:s") var number_lifetime := 0.8
@export_range(0.0, 0.12, 0.005, "suffix:s") var squash_seconds := 0.045
@export_range(0.04, 0.4, 0.01, "suffix:s") var rise_seconds := 0.16
@export_range(0.0, 0.3, 0.01, "suffix:s") var apex_seconds := 0.07
@export_range(0.0, 100.0, 1.0, "suffix:px") var rise_pixels := 30.0
@export_range(0.0, 100.0, 1.0, "suffix:px") var fall_pixels := 20.0
@export_range(0.0, 100.0, 1.0, "suffix:px") var drift_pixels := 24.0
@export_range(1.0, 1.8, 0.05) var pop_scale := 1.2
@export_range(0.0, 20.0, 0.5, "suffix:°") var tilt_degrees := 6.0
@export_range(0.3, 0.95, 0.01) var fade_start := 0.65

@export_group("收尾碎光")
@export_range(0, 6, 1) var number_spark_count := 2
@export var number_spark_color := Color("ffc873")

func format_amount(value: float) -> String:
	var places := clampi(decimal_places, 0, 2)
	# 保留到百分位以下的有效小伤害，不伪装成一次未命中。
	var text := String.num(value, places) if value >= pow(10.0, -places) else String.num(value, 4)
	if text.to_float() <= 0.0 and value > 0.0: text = "<0.0001"
	return text + number_suffix
