class_name WavePopulationRules
extends Resource

## 可选数量档位；未设置时保留控制器的已有参数。规则在新挑战／重试时生效。
@export_group("巨量怪潮模拟")
## 单波集中进场，按真实攻击数值飘字，怪物不扣血、人物免伤；按下方数量配置本局容量，保留真实刷新、攻击与碰撞。
@export var simulation_mode := false
## 仅模拟模式使用；新挑战／重试生效，不必同时修改普通容量曲线和无尽参数。
@export_range(1, 4096, 1) var simulation_enemy_count := 512
## 拖入技能定义并配置等级，0 为不携带；空列表仅保留人物基础剑术。模拟开局直接应用，不抽卡。
@export var simulation_skills: Array[SimulationSkillEntry] = []
@export_group("同场容量曲线")
@export_range(1, 4096, 1) var first_active_limit := 24
@export_range(1, 100, 1) var growth_start_wave := 4
@export_range(0, 256, 1) var active_growth_per_wave := 16
@export_range(1, 4096, 1) var max_active := 512
@export_range(1, 32768, 1) var max_population_cost := 768
## 普通／特殊／精英／首领同时在场上限，包含预告；不能用 0 禁用某类已编排怪物。
@export var role_limits := PackedInt32Array([512, 48, 12, 1])
@export_group("单波与无尽节奏")
@export_range(0, 256, 1) var enemies_per_wave_increment := 32
@export_range(1, 16384, 1) var max_wave_enemies := 1536
## 包括召唤、分裂的登记预算；应给衍生怪物留出空间。
@export_range(1, 32768, 1) var max_queued_per_wave := 4096
@export_range(0.0, 0.1, 0.005) var interval_reduction_per_wave := 0.04
@export_range(0.0, 0.99, 0.01) var max_interval_reduction := 0.92
@export_range(0.005, 2.0, 0.005, "suffix:s") var min_spawn_interval := 0.025
@export_group("刷新工作预算")
@export_range(1, 32, 1) var spawns_per_tick := 4
@export_range(1, 64, 1) var checks_per_tick := 8
@export_range(1, 80, 1) var position_attempts := 12
## 仅改变新出场怪物间距；追击避让和实体碰撞独立保留。
@export_range(0.1, 4.0, 0.05, "suffix:m") var spawn_spacing := 0.7

func active_limit(number: int) -> int:
	var steps := mini(maxi(number - growth_start_wave + 1, 0), max_active)
	return mini(max_active, first_active_limit + steps * active_growth_per_wave)

func validation_error() -> String:
	if simulation_mode and (simulation_enemy_count < 1 or simulation_enemy_count > 4096): return "模拟怪潮数量须在 1～4096 之间"
	if simulation_mode:
		var ids := {}
		for entry in simulation_skills:
			if not entry: return "模拟技能列表不能包含空条目"
			var error := entry.validation_error()
			if not error.is_empty(): return error
			var id := entry.skill_definition.id
			if ids.has(id): return "模拟技能重复配置：" + entry.skill_definition.display_name
			ids[id] = true
	if first_active_limit < 1 or max_active < first_active_limit or growth_start_wave < 1 or active_growth_per_wave < 0 or max_population_cost < 1:
		return "同场容量曲线无效"
	if role_limits.size() != 4: return "需要普通、特殊、精英、首领四类容量上限"
	for limit in role_limits:
		if limit < 0: return "分类容量上限不能为负数"
	if enemies_per_wave_increment < 0 or max_wave_enemies < 1 or max_queued_per_wave < max_wave_enemies:
		return "单波总数或登记预算无效"
	if spawns_per_tick < 1 or checks_per_tick < 1 or position_attempts < 1: return "刷新工作预算须为正数"
	for value in [min_spawn_interval, spawn_spacing]:
		if not is_finite(value) or value <= 0.0: return "刷新间隔和间距须为正数"
	if not is_finite(interval_reduction_per_wave) or interval_reduction_per_wave < 0.0 or interval_reduction_per_wave > 0.1 or not is_finite(max_interval_reduction) or max_interval_reduction < 0.0 or max_interval_reduction >= 1.0:
		return "无尽间隔减幅无效"
	return ""
