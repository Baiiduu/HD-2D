class_name WaveEnemyDefinition
extends Resource

## 替换怪物场景即可换行为；场景根节点须继承 WaveEnemy。
@export_group("怪物资源")
## 登记到 WaveEnemyCatalog 的稳定标识；留空兼容直接引用资源的旧编排。
@export var enemy_id: StringName
@export var scene: PackedScene
@export var display_name := "史莱姆"
enum Role { COMMON, SPECIAL, ELITE, BOSS }
@export var role: Role = Role.COMMON
@export_group("自动混合怪潮")
## 新怪登记到目录后默认参与混合怪潮；0 排除仅分裂／召唤产生的怪物。
@export_range(0.0, 20.0, 0.1) var horde_weight := 1.0
@export_group("战斗数值与经验")
@export_range(1.0, 10000.0, 1.0) var health := 20.0
@export_range(0.0, 10.0, 0.05) var move_speed := 1.35
## 传给怪物自身的招式，不由波次控制器判断命中。
@export_range(0.0, 1000.0, 1.0) var attack_damage := 8.0
## 真正击败后掉落的本局经验；召唤体等可设为 0。
@export_range(0, 10000, 1) var experience_reward := 3
## 刷新时给怪物保留的半径，米；避免嵌进墙或与其他出场怪物重叠。
@export_range(0.1, 2.0, 0.05, "suffix:m") var spawn_clearance := 0.35
## 相同通行半径共用导航图；大型怪物须覆盖实际碰撞体半径。
@export_range(0.1, 2.0, 0.01, "suffix:m") var navigation_radius := 0.32
@export_group("容量预算")
## 一只怪物占用的容量点；普通怪建议 1，复杂招式怪建议 4～8。
@export_range(1, 128, 1) var population_cost := 1
## 同种资源同时在场上限，包含出场预告；0 表示只受全局预算约束。
@export_range(0, 4096, 1) var max_alive := 0
@export_group("无尽生命成长")
## 允许召唤体或固定生命机制单独关闭成长；基础生命仍取 Health。
@export var health_growth_enabled := true
@export_group("控制抗性")
## 乘以来源的基础眩晕秒数；1 为普通，0.5 为重型，0 免疫。独立于血量成长与击退倍率。
@export_range(0.0, 3.0, 0.05) var stun_duration_multiplier := 1.0

## 子类追加专属数值校验，控制器在开局建立快照前调用。
func validation_error() -> String:
	if not scene: return "缺少怪物场景"
	for value in [health, spawn_clearance, navigation_radius]:
		if not is_finite(value) or value <= 0.0: return "生命和刷新半径必须为正数"
	for value in [move_speed, attack_damage, stun_duration_multiplier, horde_weight]:
		if not is_finite(value) or value < 0.0: return "移动速度、伤害、眩晕倍率和怪潮权重须为有限非负数"
	if experience_reward < 0 or population_cost < 1 or max_alive < 0 or role < Role.COMMON or role > Role.BOSS:
		return "经验、容量成本、同种上限或怪物分类无效"
	return ""

## 子类检查召唤依赖，控制器仍只依赖通用目录接口。
func catalog_error(_registered: Dictionary) -> String:
	return ""
