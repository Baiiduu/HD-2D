class_name RicochetCameraSettings
extends Resource

@export_group("弹射镜头反馈")
@export var enabled := true
@export_range(0.02, 0.15, 0.01, "suffix:s") var launch_lag_seconds := 0.07
@export_range(0.0, 1.0, 0.05) var launch_follow_fraction := 0.5
## 相对画面短边，0.025 为 2.5%；不改变基础 FOV 或相机角度。
@export_range(0.0, 0.05, 0.005) var lookahead_ratio := 0.025
## 镜头移向飞行前视位置的过渡时间，单位秒；越大越慢。默认 0.12，可先试 0.3～0.5。
@export_range(0.05, 2.0, 0.01, "suffix:s") var lead_settle_seconds := 0.12
@export_range(0.04, 0.3, 0.01, "suffix:s") var bounce_inertia_seconds := 0.1
@export_range(0.05, 0.4, 0.01, "suffix:s") var return_seconds := 0.15
@export_range(0.01, 0.06, 0.005) var max_offset_ratio := 0.035
@export_group("撞墙定向轻震")
@export_range(0.0, 5.0, 0.25, "suffix:px") var impact_shake_pixels := 2.0
@export_range(0.04, 0.15, 0.01, "suffix:s") var impact_shake_seconds := 0.08
@export_range(0.05, 0.3, 0.01, "suffix:s") var impact_min_interval := 0.1
