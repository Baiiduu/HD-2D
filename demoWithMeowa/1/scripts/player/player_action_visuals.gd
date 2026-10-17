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
## Merge invisible intermediate physics previews into the next render update.
## Only display work changes; release, damage and real collisions stay physical.
@export var coalesce_charge_preview := false
## Coalesce empty-space ray checks inside one synchronous prediction only.
## Dynamic walls/mirrors are queried again on every prediction.
@export var deduplicate_charge_preview := false
@export var preview_show_target := true
## 仅首次碰墙可显示一次反射；后续接触只截断短尾段。
@export_range(0, 1, 1) var preview_bounces := 1
@export_range(1.0, 20.0, 0.5, "suffix:m") var preview_distance := 8.0
## 首次响应后的短方向提示，不推演完整怪群绕行；0 在接触点结束。
@export_range(0.0, 2.0, 0.1, "suffix:m") var preview_followup_distance := 1.0
@export var preview_color := Color(0.9, 0.82, 0.66)
@export_range(0.0, 1.0, 0.05) var preview_opacity := 0.45
@export_range(0.5, 2.0, 0.25) var preview_line_width_pixels := 1.0
@export_group("碰墙反弹特效")
@export var show_bounce_effect := true
@export var bounce_frames: SpriteFrames
## 同一画布内的碰撞核心像素坐标，旋转时保持该点锚定真实墙面。
@export var bounce_anchor_pixels := Vector2(16, 24)
@export_range(0.08, 0.4, 0.01, "suffix:s") var bounce_duration := 0.18
@export_range(0.0, 1.0, 0.05) var bounce_opacity := 0.95
@export_range(0.0, 2.0, 0.05) var bounce_energy := 0.65
@export_range(0.0, 1.0, 0.01, "suffix:m") var bounce_height := 0.45
@export_group("弹射地面火带")
## 视觉试玩；只记录真实飞行路径，暂不结算伤害或加入成长池。
@export var show_fire_trail := false
@export_range(0.1, 0.8, 0.01, "suffix:m") var fire_trail_width := 0.36
@export_range(0.05, 0.6, 0.01, "suffix:s") var fire_trail_fresh_seconds := 0.18
@export_range(0.1, 1.5, 0.05, "suffix:s") var fire_trail_burn_seconds := 0.65
@export_range(0.1, 3.0, 0.05, "suffix:s") var fire_trail_ember_seconds := 1.35
@export_range(0.0, 3.0, 0.05) var fire_trail_energy := 1.1
## 世界坐标像素密度；不把镜头透视烘焙进素材。
@export_range(20.0, 80.0, 1.0) var fire_trail_pixels_per_meter := 40.0
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
