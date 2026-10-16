class_name WaveMeleeEnemyDefinition
extends WaveEnemyDefinition

## 身体、移动、接触与动画的共用数据；特殊招式可继承追加独立参数。
@export_group("身体与移动")
@export_range(0.1, 2.0, 0.01, "suffix:m") var body_radius := 0.28
@export_range(0.2, 6.0, 0.05, "suffix:m") var body_height := 0.7
@export_range(0.0, 60.0, 0.1) var gravity := 20.0
## 1 保留原击退距离，0 免疫；实际移动仍检查地形和碰撞。
@export_range(0.0, 2.0, 0.05) var knockback_multiplier := 1.0
@export_range(0.1, 2.0, 0.05, "suffix:s") var route_interval := 0.45
## 同体型怪物的聚群目标中心间距；越大越疏，混合体型取双方平均，实际身体半径仍作下限。
@export_range(0.0, 3.0, 0.05, "suffix:m") var separation_radius := 1.0
## 拥挤时的让位强度；保留速度大小，前方挤满时减速，停止追击后仍整理站位。
@export_range(0.0, 4.0, 0.05) var separation_strength := 1.5
## 绕障时跳过可直达的近处格心；两倍此距离内可直接靠近目标。0 使用原网格路线。
@export_range(0.0, 6.0, 0.1, "suffix:m") var pursuit_lookahead := 4.0
## 前排拥堵时从侧边让行，近身渐弱；不改变聚群目标间距，0 关闭。
@export_range(0.0, 1.0, 0.05) var pursuit_flank_strength := 0.35
@export_group("接触招式")
@export_range(0.0, 6.0, 0.05, "suffix:m") var combat_stop_distance := 0.65
@export_range(0.0, 6.0, 0.05, "suffix:m") var contact_distance := 0.85
@export_range(0.0, 6.0, 0.05, "suffix:m") var contact_height := 0.8
@export_group("动画与反馈")
@export_range(0.25, 4.0, 0.05) var animation_speed := 1.0
## 旧资源兼容字段；不再使用出生缩放或半透明预警。
@export_storage var warning_scale := 0.35
@export_range(0.0, 1.0, 0.01, "suffix:s") var hit_flash_seconds := 0.15

func validation_error() -> String:
	var error := super.validation_error()
	if not error.is_empty(): return error
	for value in [body_radius, body_height, route_interval, animation_speed, warning_scale]:
		if not is_finite(value) or value <= 0.0: return "身体尺寸、路线间隔和动画参数必须为正数"
	for value in [gravity, knockback_multiplier, separation_radius, separation_strength, pursuit_lookahead, pursuit_flank_strength, combat_stop_distance, contact_distance, contact_height, hit_flash_seconds]:
		if not is_finite(value) or value < 0.0: return "移动和接触招式参数不能为负数"
	if body_height < body_radius * 2.0 or spawn_clearance < body_radius or navigation_radius < body_radius:
		return "身体高度须覆盖直径，刷新和导航半径须覆盖身体半径"
	if attack_damage > 0.0 and combat_stop_distance >= contact_distance:
		return "攻击停止距离必须小于接触距离"
	return ""
