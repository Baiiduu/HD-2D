@tool
class_name GameSystemSettings
extends RefCounted
## 编辑器 Game Manager 与运行系统共用的项目开关；不创建场景节点或全局运行单例。
const UPGRADES: StringName = &"upgrades"
const DRAFT: StringName = &"draft"
const RUN_SKILLS: StringName = &"run_skills"
const SYSTEMS := [
	{"id": UPGRADES, "label": "升级系统", "description": "关闭后停止经验掉落、吸收与等级成长，隐藏经验 HUD。"},
	{"id": DRAFT, "label": "抽卡系统", "description": "关闭后跳过开局选卡，不弹出升级卡片；本局待选奖励保留至重新开启或本局结束。"},
	{"id": RUN_SKILLS, "label": "局内技能管理器", "description": "关闭后停止可选技能学习与执行；不影响角色固有弹射、Dash 和基础普攻。"},
]

static func key(system: StringName) -> String:
	return "game_manager/systems/" + String(system)

static func is_enabled(system: StringName) -> bool:
	return bool(ProjectSettings.get_setting(key(system), true))

static func ensure_defaults() -> void:
	for system in SYSTEMS:
		var property := key(system.id)
		if not ProjectSettings.has_setting(property): ProjectSettings.set_setting(property, true)
		ProjectSettings.set_initial_value(property, true)
		ProjectSettings.add_property_info({"name":property, "type":TYPE_BOOL})
