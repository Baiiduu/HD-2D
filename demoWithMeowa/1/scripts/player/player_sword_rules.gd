class_name PlayerSwordRules
extends Resource

enum SlashVisual { FRAME_ANIMATION, THIN_ARC, MEOWA_ARC }

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
## 攻速同步缩放完整起手、扫刃与收尾；达到此间隔后不再增加剑术出手频率。
@export_range(0.08, 0.3, 0.01, "suffix:s") var minimum_attack_interval := 0.12
@export_range(0.0, 0.3, 0.005, "suffix:s") var windup_seconds := 0.05
@export_range(0.03, 0.5, 0.005, "suffix:s") var sweep_seconds := 0.10
@export_range(0.02, 0.5, 0.005, "suffix:s") var fade_seconds := 0.10
@export_group("斩击素材")
@export_enum("旧帧动画:0", "程序短弧:1", "Meowa 动画短弧:2") var effect_mode: int = SlashVisual.FRAME_ANIMATION
@export var frames: SpriteFrames
## 美术圆心与外缘的原生像素距离；基础半径 / 此值应匹配人物实际像素尺寸。
@export var art_radius_pixels := 95.0
@export_range(0.01, 1.5, 0.01, "suffix:m") var effect_height := 0.72
## 朝镜头倾斜并叠加左右斜切；只改高度，地面投影保持真实命中扇区。
@export_range(0.0, 35.0, 1.0, "suffix:°") var effect_tilt_degrees := 8.0
@export_range(0.0, 1.0, 0.05) var effect_opacity := 0.9
@export_range(0.0, 2.0, 0.05) var effect_energy := 0.0
@export_group("窄弧刀痕试玩")
## 厚度独立于命中半径；范围成长只温和增厚，最多为此值的 1.6 倍。
@export_range(0.03, 0.25, 0.005, "suffix:m") var arc_width := 0.10
@export_range(15.0, 100.0, 1.0, "suffix:°") var arc_trail_degrees := 62.0
@export_subgroup("Meowa 拖尾与破碎")
## 仅压低原帧中低饱和度的白刃，不替换原图的红色笔触和碎屑。
@export_range(0.0, 1.0, 0.01) var meowa_body_opacity := 0.08
## 拖尾独立于白刃宽度展开，仍限制在真实攻击半径内。
@export_range(1.0, 4.0, 0.1) var meowa_tail_spread := 2.5
## 后缘回到人物腰侧附近，前端仍到真实攻击外沿；无需绑定精细手部动作。
@export_range(0.2, 1.0, 0.05) var meowa_tail_inner_ratio := 0.3
## 扫击完成后播放原后半帧；独立于攻速和下一刀，不延后实际攻击。
@export_range(0.08, 0.4, 0.01, "suffix:s") var meowa_tail_seconds := 0.24
@export_subgroup("程序短弧专用")
## 仅程序短弧使用；Meowa 动画短弧直接保留原帧颜色。
@export var arc_blade_color := Color(1.0, 0.88, 0.64, 1.0)
@export var arc_tail_color := Color(0.82, 0.18, 0.12, 0.65)
## 仅程序短弧使用；Meowa 动画短弧按原图集最近邻采样，不再次像素化。
@export_range(0.005, 0.05, 0.001, "suffix:m") var arc_pixel_size := 0.016
@export_group("共用战斗声音")
@export var audio_enabled := true
@export var sweep_sounds: Array[AudioStream] = []
@export var hit_sounds: Array[AudioStream] = []
@export_range(-40.0, 6.0, 0.5) var audio_volume_db := -13.0

func duration() -> float:
	return windup_seconds + sweep_seconds + fade_seconds

func validation_error() -> String:
	for value in [normal_interval, flight_interval, minimum_attack_interval, normal_range, flight_range, sweep_seconds, fade_seconds, height_tolerance, art_radius_pixels]:
		if not is_finite(value) or value <= 0.0: return "基础剑术的间隔、范围和动作时长须为有限正数"
	if not is_finite(damage) or damage < 0.0 or not is_finite(windup_seconds) or windup_seconds < 0.0: return "基础伤害和起手时间不能为负数"
	for angle in [normal_angle, flight_angle]:
		if not is_finite(angle) or angle < 1.0 or angle > 180.0: return "基础剑术扇角须在 1～180 度之间"
	if effect_mode != SlashVisual.FRAME_ANIMATION:
		for value in [arc_width, arc_trail_degrees, arc_pixel_size]:
			if not is_finite(value) or value <= 0.0: return "窄弧刀痕的厚度、尾长和像素尺寸须为有限正数"
	if effect_mode == SlashVisual.MEOWA_ARC:
		if not is_finite(meowa_body_opacity) or meowa_body_opacity < 0.0 or meowa_body_opacity > 1.0: return "Meowa 白刃透明度须在 0～1 之间"
		if not is_finite(meowa_tail_inner_ratio) or meowa_tail_inner_ratio < 0.2 or meowa_tail_inner_ratio > 1.0: return "Meowa 拖尾内端半径比例须在 0.2～1 之间"
		for value in [meowa_tail_spread, meowa_tail_seconds]:
			if not is_finite(value) or value <= 0.0: return "Meowa 拖尾展开和破碎时长须为有限正数"
	return ""
