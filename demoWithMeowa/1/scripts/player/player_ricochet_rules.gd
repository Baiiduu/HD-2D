class_name PlayerRicochetRules
extends Resource

## 本轮只控制运动与拨怪；没有碰撞伤害、无敌或减伤。
@export var enabled := true
@export_group("蓄力与飞行（试玩值）")
@export_range(0.1, 3.0, 0.05, "suffix:s") var full_charge_seconds := 0.8
@export_range(1.0, 30.0, 0.5, "suffix:m/s") var minimum_launch_speed := 8.0
@export_range(1.0, 40.0, 0.5, "suffix:m/s") var maximum_launch_speed := 16.0
@export_range(0.0, 2.0, 0.05, "suffix:s") var recovery_seconds := 0.18
@export_range(0.0, 3.0, 0.05, "suffix:s") var cooldown_seconds := 0.6
@export_group("弹射速度与续弹")
## 飞行及碰撞后的剩余速度须高于此值；达到下限就收势，不限制总反弹次数。
@export_range(0.1, 10.0, 0.1, "suffix:m/s") var minimum_bounce_speed := 2.0
@export_range(0.05, 20.0, 0.05, "or_greater", "suffix:m/s²") var flight_deceleration := 2.5
## 怪群、墙体、镜面共用的每次固定耗速；先应用各自保速，再扣此值。
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:m/s") var bounce_speed_cost := 0.5
@export_group("墙面与地形")
@export_range(0.2, 1.0, 0.05) var bounce_speed_retention := 0.9
## 地表变化超过此值或进入水面、地图外时停止；不会把断层当作弹墙。
@export_range(0.02, 0.3, 0.01, "suffix:m") var ground_height_tolerance := 0.2
@export_group("人物沿怪群划弧")
## 人物沿怪群外沿划弧后脱离，不给怪物施加位移。
@export var crowd_deflection_enabled := false
## 人物中心与前排怪物中心的接触距离，独立于拨怪和剑术范围。
@export_range(0.4, 2.0, 0.05, "suffix:m") var crowd_contact_radius := 0.95
## 接入外沿及脱离切线时的过渡长度；沿途照常耗速。
@export_range(0.15, 1.2, 0.05, "suffix:m") var crowd_turn_distance := 0.6
## 沿局部怪群轮廓绕行的角度，到达后沿侧外方脱离，不持续绕圈。
@export_range(30.0, 180.0, 5.0, "suffix:°") var crowd_arc_degrees := 120.0
## 大怪群限制贴边路程，避免围绕整团兜长弯；不改变飞行耗速。
@export_range(0.5, 12.0, 0.1, "suffix:m") var crowd_arc_distance := 4.0
## 出射方向朝怪群外侧的分量；其余沿切线，正撞按已有旋向选择侧方。
@export_range(0.1, 0.8, 0.05) var crowd_exit_outward := 0.35
@export_range(0.5, 1.0, 0.01) var crowd_speed_retention := 1.0
## 离开本次接触区域多远才允许再次受同一片怪群转向。
@export_range(0.05, 1.0, 0.05, "suffix:m") var crowd_release_clearance := 0.35
@export_group("旧拨怪（正式关闭）")
## 保留旧拨怪接口与参数供独立原型使用；正式地图关闭。
@export var enemy_push_enabled := true
@export_range(0.3, 3.0, 0.05, "suffix:m") var push_radius := 1.05
@export_range(0.0, 60.0, 0.5, "or_greater", "suffix:m/s") var push_initial_speed := 8.0
## 绕行的附加收势缓冲；实际时长还包括按半圈路程和初速计算的运动时间。
@export_range(0.05, 3.0, 0.01, "or_greater", "suffix:s") var push_seconds := 0.22
## 从拨中瞬间计时，包含滑行；再乘以怪物的眩晕时长倍率。
@export_range(0.0, 3.0, 0.05, "suffix:s") var push_stun_seconds := 1.0
@export_group("怪群轮廓（人物与旧拨怪共用）")
## 从上方看，世界 +X 向 +Z 为顺时针；Q/E 不改变这一世界方向。
@export var clockwise := true
@export_range(0.05, 1.0, 0.05, "suffix:m") var push_height_tolerance := 0.35
## 相邻怪物中心在此距离内视为相连；只在首次命中建立区域。
@export_range(0.4, 4.0, 0.05, "suffix:m") var push_group_link_distance := 1.5
## 以首次受击怪为中心寻找附近怪群，避免串入远处整张地图。
@export_range(1.0, 30.0, 0.5, "suffix:m") var push_group_search_radius := 12.0
@export_range(0.0, 1.0, 0.05, "suffix:m") var push_group_edge_margin := 0.15
@export_group("旧拨怪落点")
## 同次接力集中在最初受击侧对面的这段边沿，并按身体间距错开成排。
@export_range(30.0, 140.0, 5.0, "suffix:°") var push_arrival_arc_degrees := 90.0

@export_group("旧拨怪连锁碰撞")
## 0 关闭接力；只在实际滑行接触同伴时传递，每次发射每怪最多一次。
@export_range(0, 16, 1) var push_chain_layers := 4
@export_range(0.0, 1.0, 0.01) var push_chain_speed_retention := 0.78
@export_range(0.0, 1.0, 0.01) var push_chain_stun_retention := 0.85
## 传递后的速度不足时停止；不限制一层能带动的怪物数量。
@export_range(0.0, 10.0, 0.1, "suffix:m/s") var push_chain_min_speed := 1.5

@export_group("性能（等效实现对照）")
## 仅本次同步预览读取已提交索引；未知索引或输入变更回原查询。
@export var preview_spatial_queries_enabled := false
## 预览和本体飞行复用同高无水地表证明；实际身体／墙体扫掠不变。
@export var flat_ground_certificate_enabled := false

@export_group("旧版兼容（不参与当前人物弹射）")
## 仅保留旧资源字段，当前运动不再读取倒计时或次数上限。
@export var flight_seconds := 0.9
@export var wall_bounce_limit := 4

func coast_seconds(speed: float) -> float:
	return maxf(0.0, speed - minimum_bounce_speed) / flight_deceleration

func coast_distance(speed: float, seconds: float) -> float:
	var step := clampf(seconds, 0.0, coast_seconds(speed))
	return maxf(0.0, speed * step - 0.5 * flight_deceleration * step * step)

func coast_time_for_distance(speed: float, distance: float) -> float:
	var reach := clampf(distance, 0.0, coast_distance(speed, coast_seconds(speed)))
	var end_speed := sqrt(maxf(minimum_bounce_speed * minimum_bounce_speed, speed * speed - 2.0 * flight_deceleration * reach))
	# 二次式的等价形式，避免短位移时两个接近的速度相减丢失精度。
	return 2.0 * reach / maxf(speed + end_speed, 0.000001)

func speed_after_coast(speed: float, seconds: float) -> float:
	return maxf(minimum_bounce_speed, speed - flight_deceleration * maxf(0.0, seconds))

func rebound_speed(speed: float, retention: float) -> float:
	return maxf(0.0, speed * retention - bounce_speed_cost)

func can_rebound(speed: float, retention: float) -> bool:
	return speed > minimum_bounce_speed and rebound_speed(speed, retention) > minimum_bounce_speed

## 运动事件的时间／距离换算；普通匀速片段没有元数据时保持线性。
static func segment_fraction(time: float, seconds: float, initial_speed: float, deceleration: float) -> float:
	var t := clampf(time, 0.0, seconds)
	var length := initial_speed * seconds - 0.5 * deceleration * seconds * seconds
	return clampf((initial_speed * t - 0.5 * deceleration * t * t) / length, 0.0, 1.0) if length > 0.000001 else t / maxf(seconds, 0.000001)

static func segment_time(fraction: float, seconds: float, initial_speed: float, deceleration: float) -> float:
	var weight := clampf(fraction, 0.0, 1.0)
	if initial_speed <= 0.0 or deceleration <= 0.0: return seconds * weight
	var distance := (initial_speed * seconds - 0.5 * deceleration * seconds * seconds) * weight
	return 2.0 * distance / maxf(initial_speed + sqrt(maxf(0.0, initial_speed * initial_speed - 2.0 * deceleration * distance)), 0.000001)

func validation_error() -> String:
	for value in [full_charge_seconds, minimum_launch_speed, maximum_launch_speed, minimum_bounce_speed, flight_deceleration, ground_height_tolerance, push_radius, push_seconds, push_height_tolerance, push_group_link_distance, push_group_search_radius]:
		if not is_finite(value) or value <= 0.0: return "蓄力、飞行、地形与拨怪参数须为有限正数"
	for value in [recovery_seconds, cooldown_seconds, push_initial_speed, push_stun_seconds, push_chain_min_speed, push_group_edge_margin, bounce_speed_cost]:
		if not is_finite(value) or value < 0.0: return "恢复、冷却、推力与眩晕时间须为有限非负数"
	if maximum_launch_speed < minimum_launch_speed: return "满蓄力速度不能低于起步速度"
	if maximum_launch_speed <= minimum_bounce_speed: return "满蓄力速度须高于续弹最低速度"
	if not is_finite(bounce_speed_retention) or bounce_speed_retention <= 0.0 or bounce_speed_retention > 1.0: return "反弹速度保留比例无效"
	if push_chain_layers < 0 or push_chain_layers > 16: return "绕行接力层数须在 0～16 之间"
	if not is_finite(push_arrival_arc_degrees) or push_arrival_arc_degrees < 30.0 or push_arrival_arc_degrees > 140.0: return "绕行落点扇区须在 30～140 度之间"
	if crowd_deflection_enabled:
		if not is_finite(crowd_arc_degrees) or crowd_arc_degrees < 30.0 or crowd_arc_degrees > 180.0: return "人物绕群角度须在 30～180 度之间"
		for value in [crowd_contact_radius, crowd_turn_distance, crowd_release_clearance, crowd_arc_distance]:
			if not is_finite(value) or value <= 0.0: return "接群距离、短弧长度和脱离间距须为有限正数"
		if not is_finite(crowd_exit_outward) or crowd_exit_outward <= 0.0 or crowd_exit_outward >= 1.0: return "接群出射外向分量须在 0～1 之间"
		if not is_finite(crowd_speed_retention) or crowd_speed_retention <= 0.0 or crowd_speed_retention > 1.0: return "接群保速须在 0～1 之间"
	for value in [push_chain_speed_retention, push_chain_stun_retention]:
		if not is_finite(value) or value < 0.0 or value > 1.0: return "绕行接力的速度与眩晕保留比例须在 0～1 之间"
	return ""
