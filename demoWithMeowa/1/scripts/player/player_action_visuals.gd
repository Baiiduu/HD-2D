class_name PlayerActionVisuals
extends Resource

## 每槽可单独替换。clip 使用 side/front/back；侧向左右镜像，空槽沿用原人物动画。
## 保留原生像素、统一脚底锚点和画布；动画不缩放 Sprite、不驱动根节点移动。
@export_group("人物动作槽位")
@export var normal_attack: SpriteFrames
@export var charge: SpriteFrames
@export var flight: SpriteFrames
@export var flight_attack: SpriteFrames
@export var recovery: SpriteFrames
## 缺少攻击美术时，接口占用的占位时间；有素材时读取完整原生帧时长。
@export_range(0.05, 2.0, 0.05, "suffix:s") var placeholder_attack_seconds := 0.3
@export_group("蓄力特效")
@export var show_charge_effect := true
## 按人物实际缩放后的原生像素计量；不改变人物或真实拨怪半径。
@export_range(24.0, 64.0, 1.0) var charge_radius_pixels := 42.0
@export_range(0.0, 1.0, 0.05) var charge_effect_opacity := 0.95
@export_range(0.0, 1.0, 0.05) var charge_effect_energy := 0.35
@export_group("碰撞路线预览")
@export var show_aim_guide := true
@export var preview_show_target := true
@export_range(0, 8, 1) var preview_bounces := 1
@export_range(1.0, 20.0, 0.5, "suffix:m") var preview_distance := 12.0
@export var preview_color := Color(0.9, 0.82, 0.66)
@export_range(0.0, 1.0, 0.05) var preview_opacity := 0.45
@export_range(0.5, 2.0, 0.25) var preview_line_width_pixels := 1.0
@export_group("框架观察")
## 仅用于观察拨怪圆周，不改变真实范围。
@export var show_push_ring := false

func frames_for(action: StringName) -> SpriteFrames:
	match action:
		&"normal_attack": return normal_attack
		&"charge": return charge
		&"flight": return flight
		&"flight_attack": return flight_attack
		&"recovery": return recovery
	return null
