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
@export_group("滑行速度镜头")
## 各地图独立开启；实际余速驱动距离、俯角与前视，停止后再回到日常构图。
@export var flight_speed_camera_enabled := false
## 延续满蓄的推近、低视角和方向聚焦，随实际余速减弱。
@export var flight_charge_focus_enabled := false
@export_range(0.0, 1.0, 0.05) var flight_charge_focus_ratio := 0.90
@export_range(0.1, 60.0, 0.1, "suffix:m/s") var flight_reference_speed := 12.0
@export_range(0.0, 0.15, 0.005) var flight_pullback_ratio := 0.07
@export_range(0.0, 6.0, 0.25, "suffix:°") var flight_pitch_drop := 2.0
@export_range(0.03, 1.0, 0.01, "suffix:s") var flight_speed_smoothing := 0.18
@export_group("持续环绕取景")
@export var orbit_focus_enabled := false
@export_range(0.0, 1.0, 0.05) var orbit_lead_retention := 0.25
@export_range(0.0, 0.5, 0.01) var orbit_focus_weight := 0.28
@export_range(0.2, 2.0, 0.1, "suffix:m") var orbit_focus_max_distance := 1.2
@export_range(0.08, 0.6, 0.01, "suffix:s") var orbit_settle_seconds := 0.22
@export_range(0.0, 0.08, 0.005) var orbit_pullback_ratio := 0.035
@export_group("连续攻击与清群重音")
@export var combat_beat_enabled := false
@export_range(0.0, 5.0, 0.25, "suffix:px") var combat_beat_pixels := 3.0
@export_range(0.08, 0.3, 0.01, "suffix:s") var combat_beat_seconds := 0.18
@export_range(0.12, 0.6, 0.01, "suffix:s") var combat_beat_interval := 0.2
@export_range(0.0, 0.025, 0.001) var combat_pullback_ratio := 0.008
@export_group("蓄力聚焦镜头")
## 由各地图独立开启；仅改变运行时取景，不改写相机的基础距离与 FOV。
@export var charge_focus_enabled := false
@export_range(0.0, 0.25, 0.005) var charge_zoom_ratio := 0.07
## 按下时立即追向这部分推近量，其余随真实蓄力进度增长。
@export_range(0.0, 1.0, 0.05) var charge_onset_ratio := 0.35
@export_range(0.01, 1.0, 0.01, "suffix:s") var charge_focus_seconds := 0.10
@export_range(0.0, 1.0, 0.01, "suffix:s") var charge_release_seconds := 0.18
@export_range(0.01, 1.0, 0.01, "suffix:s") var charge_cancel_seconds := 0.20
@export_subgroup("蓄力分段运镜")
@export var charge_staging_enabled := false
@export_range(0.0, 8.0, 0.25, "suffix:°") var charge_pitch_drop := 3.5
## 相对画面短边；中段划弧，满蓄时回到中心。
@export_range(0.0, 0.025, 0.001) var charge_arc_ratio := 0.012
@export_range(0.0, 0.03, 0.001) var charge_full_punch_ratio := 0.012
@export_subgroup("蓄力混合波颤动")
## 在现有轨迹上叠加屏幕平面位移；不旋转画面或改变人物瞄准。
@export var charge_tremor_enabled := false
## 以当前视口像素计量横纵合成的最大幅度，随真实蓄力增强。
@export_range(0.0, 6.0, 0.25, "suffix:px") var charge_tremor_pixels := 2.25
@export_range(1.0, 12.0, 0.25, "suffix:Hz") var charge_tremor_start_hz := 4.0
@export_range(1.0, 12.0, 0.25, "suffix:Hz") var charge_tremor_full_hz := 7.0
@export_range(0.02, 0.4, 0.01, "suffix:s") var charge_tremor_release_seconds := 0.12
@export_subgroup("蓄力到发射交接")
@export var charge_release_handoff_enabled := false
## 0 沿用平滑舒展，1 在前段完成主要拉开并保留柔和收尾。
@export_range(0.0, 1.0, 0.05) var charge_release_burst := 0.0
@export_range(0.1, 0.8, 0.01, "suffix:s") var charge_release_pitch_seconds := 0.34
@export_range(0.1, 0.6, 0.01, "suffix:s") var charge_release_framing_seconds := 0.28
## 相对画面短边；临近满蓄渐入前方留白，保持基础构图和鼠标投地补偿。
@export_range(0.0, 0.035, 0.001) var charge_direction_bias_ratio := 0.0
@export_subgroup("满蓄单次定向轻震")
@export var charge_full_shake_enabled := false
@export_range(0.0, 12.0, 0.25, "suffix:px") var charge_full_shake_pixels := 4.0
@export_range(0.05, 0.4, 0.01, "suffix:s") var charge_full_shake_seconds := 0.16
@export_group("碰撞曲线与惯性反馈")
## 独立开关保留原轻震与各地图现有蓄力镜头。
@export var impact_shot_enabled := false
## 分层关闭时使用：首尾为 0，正值沿碰撞法向轻压，少量负值作反向回弹；为空沿用原弧形机位。
@export var impact_shot_curve: Curve
@export_range(0.15, 0.5, 0.01, "suffix:s") var impact_shot_seconds := 0.32
@export_range(0.0, 0.09, 0.001) var impact_shot_offset_ratio := 0.065
@export_range(0.0, 8.0, 0.25, "suffix:°") var impact_shot_yaw_degrees := 4.5
@export_range(0.0, 3.0, 0.1, "suffix:°") var impact_shot_roll_degrees := 1.8
@export_range(0.0, 0.08, 0.001) var impact_shot_pullback_ratio := 0.035
@export_range(1.0, 30.0, 0.5, "suffix:m/s") var impact_reference_speed := 12.0
@export_subgroup("撞击与出射分层")
## 短冲击按屏幕像素计量，转向和拉远沿较慢的出射轨迹；各地图独立开启。
@export var impact_split_enabled := false
@export_range(0.0, 8.0, 0.25, "suffix:px") var impact_punch_pixels := 3.5
@export_range(0.03, 0.1, 0.005, "suffix:s") var impact_punch_seconds := 0.055
@export_group("撞墙定向轻震")
@export_range(0.0, 5.0, 0.25, "suffix:px") var impact_shake_pixels := 2.0
@export_range(0.04, 0.15, 0.01, "suffix:s") var impact_shake_seconds := 0.08
@export_range(0.05, 0.3, 0.01, "suffix:s") var impact_min_interval := 0.1

## 相机距离与场景明暗共用释放曲线；端点零速度且始终单向，不延迟真实发射。
func release_progress(age: float, seconds: float) -> float:
	if seconds <= 0.0: return 1.0
	var t := clampf(age / seconds, 0.0, 1.0)
	var warped := t + 4.0 * clampf(charge_release_burst, 0.0, 1.0) * t * t * (1.0 - t) * (1.0 - t)
	return smoothstep(0.0, 1.0, warped)

func flight_speed_weight(speed: float) -> float:
	return smoothstep(0.0, 1.0, clampf(speed / maxf(flight_reference_speed, 0.1), 0.0, 1.0))
