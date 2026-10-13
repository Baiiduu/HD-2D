class_name RunGrowthState
extends Resource

signal levels_gained(count: int)

var rules: ExperienceRules
var level := 1
var experience := 0
var total_experience := 0
var pending_choices := 0

func reset() -> void:
	level = 1
	experience = 0
	total_experience = 0
	pending_choices = 0
	emit_changed()

func required_experience() -> int:
	return rules.required_for(level) if rules and level < rules.level_cap else 0

## 大额拾取可以连续升级；余量保留，每级产生一次独立的选择机会。
func add_experience(amount: int) -> int:
	if not rules or amount <= 0: return 0
	total_experience += amount
	if level >= rules.level_cap:
		emit_changed()
		return 0
	experience += amount
	var gained := 0
	while level < rules.level_cap and experience >= required_experience():
		experience -= required_experience()
		level += 1
		pending_choices += 1
		gained += 1
	if level >= rules.level_cap: experience = 0
	emit_changed()
	if gained > 0: levels_gained.emit(gained)
	return gained

func next_choice_level() -> int:
	return level - pending_choices + 1

func complete_choice() -> bool:
	if pending_choices <= 0: return false
	pending_choices -= 1
	emit_changed()
	return true

func discard_pending_choices() -> void:
	pending_choices = 0
	emit_changed()
