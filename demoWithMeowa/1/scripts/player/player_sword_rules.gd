class_name PlayerSwordRules
extends Resource

## 人物自带基础剑术；不登记为 A01 或技能等级，不改写原武器配置。
@export var enabled := true
@export_group("基础伤害")
@export_range(0.0, 1000.0, 1.0) var damage := 10.0
@export_range(0.05, 1.0, 0.05, "suffix:m") var height_tolerance := 0.55
@export_group("普通攻击")
@export_range(0.1, 3.0, 0.01, "suffix:s") var normal_interval := 0.55
@export_range(0.3, 5.0, 0.01, "suffix:m") var normal_range := 1.52
@export_range(30.0, 180.0, 5.0, "suffix:°") var normal_angle := 120.0
@export_group("弹射挥剑")
@export_range(0.1, 3.0, 0.01, "suffix:s") var flight_interval := 0.30
@export_range(0.3, 5.0, 0.01, "suffix:m") var flight_range := 1.52
@export_range(30.0, 180.0, 5.0, "suffix:°") var flight_angle := 180.0
@export_group("完整动作节奏")
@export_range(0.0, 0.3, 0.005, "suffix:s") var windup_seconds := 0.05
@export_range(0.03, 0.5, 0.005, "suffix:s") var sweep_seconds := 0.10
@export_range(0.02, 0.5, 0.005, "suffix:s") var fade_seconds := 0.10
@export_group("斩击素材")
@export var frames: SpriteFrames
## 美术圆心与外缘的原生像素距离；基础半径 / 此值应匹配人物实际像素尺寸。
@export var art_radius_pixels := 95.0
@export_range(0.01, 1.5, 0.01, "suffix:m") var effect_height := 0.72
## 朝镜头倾斜并叠加左右斜切；只改高度，地面投影保持真实命中扇区。
@export_range(0.0, 35.0, 1.0, "suffix:°") var effect_tilt_degrees := 8.0
@export_range(0.0, 1.0, 0.05) var effect_opacity := 0.9
@export_range(0.0, 2.0, 0.05) var effect_energy := 0.0
@export_group("共用战斗声音")
@export var audio_enabled := true
@export var sweep_sounds: Array[AudioStream] = []
@export var hit_sounds: Array[AudioStream] = []
@export_range(-40.0, 6.0, 0.5) var audio_volume_db := -13.0

func duration() -> float:
	return windup_seconds + sweep_seconds + fade_seconds

func validation_error() -> String:
	for value in [normal_interval, flight_interval, normal_range, flight_range, sweep_seconds, fade_seconds, height_tolerance, art_radius_pixels]:
		if not is_finite(value) or value <= 0.0: return "基础剑术的间隔、范围和动作时长须为有限正数"
	if not is_finite(damage) or damage < 0.0 or not is_finite(windup_seconds) or windup_seconds < 0.0: return "基础伤害和起手时间不能为负数"
	for angle in [normal_angle, flight_angle]:
		if not is_finite(angle) or angle < 1.0 or angle > 180.0: return "基础剑术扇角须在 1～180 度之间"
	return ""
