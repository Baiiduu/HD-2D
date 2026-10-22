class_name CombatAudioBalance
extends Resource

## 地图默认平衡，与玩家保存的单条／分组音量叠加。
@export var gains_db: Dictionary[StringName, float] = {}
## 只覆盖需要调整的事件；未登记事件保留原优先级与预算。
@export var priorities: Dictionary[StringName, int] = {}
## 按事件跨来源合并密集声音，真实时间仍服从战斗冻结。
@export var intervals: Dictionary[StringName, float] = {}
@export var voice_limits: Dictionary[StringName, int] = {}

func gain_db(cue: StringName) -> float:
	return clampf(gains_db.get(cue, 0.0), -24.0, 24.0)

func priority_for(cue: StringName, fallback: int) -> int:
	return clampi(priorities.get(cue, fallback), 0, 100)

func interval_for(cue: StringName) -> float:
	return clampf(intervals.get(cue, 0.0), 0.0, 1.0)
