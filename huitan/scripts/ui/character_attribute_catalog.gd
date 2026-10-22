extends RefCounted
## 属性登记和真实数值读取独立于布局；新增条目不需要修改面板或行组件。
const A = GrowthBuffDefinition.Attribute
const CATEGORIES := [
	{"id": &"overview", "title": "总览", "heading": "人物总览"},
	{"id": &"combat", "title": "战斗", "heading": "战斗属性"},
	{"id": &"ricochet", "title": "弹射", "heading": "弹射属性"},
	{"id": &"survival", "title": "生存", "heading": "生存属性"},
	{"id": &"mobility", "title": "机动", "heading": "机动属性"},
]
var definitions: Array[Dictionary] = []
var _player: Player
var _session: WavePrototype

func _init() -> void:
	_stat(&"health", [&"overview", &"survival"], "基础状态", "生命", [&"health_current", &"health_max"], ["number", "number"], "heart", "人物实际生命；上限包含当前地图允许的训练与成长。", ["当前", "上限"])
	_stat(&"damage_multiplier", [&"overview", &"combat"], "共有增益", "伤害系数", [&"damage_multiplier"], ["multiplier"], "sword", "共有伤害与重击系数相乘；条件动能增伤及暴击另列。")
	_stat(&"attack_frequency", [&"combat"], "共有增益", "攻击频率", [&"attack_frequency"], ["multiplier"], "star", "由真实攻击间隔系数换算，包含重击减频；基础剑术仍受完整动作及最短间隔约束。")
	_stat(&"attack_range", [&"combat"], "共有增益", "攻击范围", [&"attack_range"], ["multiplier"], "sword", "适用于支持范围成长的攻击；剑术真实半径见下方。")
	_stat(&"critical", [&"combat"], "暴击", "暴击", [&"crit_chance", &"crit_multiplier"], ["percent", "multiplier"], "star", "读取当前地图伤害结算的暴击率与暴击倍率。", ["暴击率", "伤害"])
	_stat(&"normal_sword", [&"overview", &"combat"], "基础剑术", "普通攻击", [&"normal_damage", &"normal_interval", &"normal_range"], ["number", "seconds", "meters"], "sword", "基础资源经共有成长后的非暴击伤害、完整攻击间隔与判定半径；不包含飞行限定增伤。", ["伤害", "间隔", "范围"])
	_stat(&"flight_sword", [&"combat"], "基础剑术", "弹射挥剑", [&"flight_damage", &"flight_interval", &"flight_range"], ["number", "seconds", "meters"], "sword", "飞行剑术经共有成长后的非暴击伤害、间隔与半径；动能增伤和追加刀数独立列出。", ["伤害", "间隔", "范围"])
	_stat(&"sword_angles", [&"combat"], "基础剑术", "判定角度", [&"normal_angle", &"flight_angle"], ["degrees", "degrees"], "sword", "沿用实际剑术扇区；范围成长不改变角度。", ["普攻", "弹射"])
	_stat(&"speed_damage", [&"combat"], "条件属性", "动能增伤", [&"speed_damage"], ["multiplier"], "star", "仅飞行中生效，逐次出手按剩余动能快照；环绕实际移动速度不参与计算。")
	_stat(&"multistrike", [&"combat"], "条件属性", "弹射刀数", [&"strikes"], ["strikes"], "sword", "获得追加挥剑后，按当前剩余动能档位计算每次刀数；逐刀真实命中。")
	_stat(&"extra_strike", [&"combat"], "条件属性", "追加刀伤害", [&"extra_strike"], ["percent"], "sword", "追加每刀相对根出手的伤害比例，独立判定；基础命中恢复每根出手一次。")
	_stat(&"launch", [&"overview", &"ricochet"], "蓄力发射", "发射初速", [&"launch_min", &"launch_max"], ["speed", "speed"], "boot", "进行中的弹射读取本次蓄力快照，闲置读取下一次成长后的发射参数；击杀加速另作用于实际移动。", ["起步", "满蓄"])
	_stat(&"charge", [&"ricochet"], "蓄力发射", "满蓄时间", [&"charge"], ["seconds"], "star", "真实战斗时间中的满蓄时长；蓄力慢镜头不改写该参数。")
	_stat(&"launch_cooldown", [&"ricochet"], "蓄力发射", "发射冷却", [&"launch_cooldown"], ["seconds"], "star", "发射时开始计时；冷却结束且结束飞行、收势后才能再次蓄力。")
	_stat(&"recovery", [&"ricochet"], "蓄力发射", "结束收势", [&"recovery"], ["seconds"], "boot", "自然结束后的收势时长；新按移动键接管沿用原有即时取消规则。")
	_stat(&"deceleration", [&"ricochet"], "动能维持", "持续耗速", [&"deceleration"], ["speed_loss"], "boot", "飞行每战斗秒消耗的剩余动能，已计入动能维持等成长。")
	_stat(&"collision_cost", [&"ricochet"], "动能维持", "碰撞固定耗速", [&"collision_cost"], ["speed"], "shield", "碰撞时额外扣除；设为零仍有持续耗速、墙面比例损失与最低续行速度。")
	_stat(&"wall_retention", [&"ricochet"], "动能维持", "墙面动能保留", [&"wall_retention"], ["percent"], "shield", "真实墙面反弹的动能保留比例，之后仍遵守固定耗速和最低速度。")
	_stat(&"minimum_speed", [&"ricochet"], "动能维持", "最低续行速度", [&"minimum_speed"], ["speed"], "boot", "剩余动能降至此门槛时结束；反弹后的余速也须超过此值。")
	_stat(&"energy", [&"ricochet"], "当前状态", "剩余动能", [&"energy"], ["speed"], "star", "用于耗速、续航、动能增伤与追加刀数的余速；与实际移动速度分开。")
	_stat(&"motion_speed", [&"ricochet"], "当前状态", "实际移动速度", [&"motion_speed"], ["speed"], "boot", "读取人物弹射当前速度，包含环绕运动比例与实时击杀加速。")
	_stat(&"orbit_reduction", [&"survival"], "基础续航", "环绕减伤", [&"orbit_reduction"], ["percent"], "shield", "仅持续飞行环绕时按地图成长规则减免受到的伤害；不是永久防御或无敌。")
	_stat(&"sword_heal", [&"survival"], "基础续航", "剑术命中恢复", [&"sword_heal", &"sword_heal_cap"], ["health", "health_rate"], "heart", "普通与弹射剑术每根真实命中恢复一次；比例按实际最大生命换算，受独立滚动一秒上限约束。", ["每次", "上限"])
	_stat(&"vamp", [&"survival"], "条件属性", "全能吸血", [&"vamp"], ["percent"], "heart", "按怪物实际损血恢复，不包含溢出伤害；无每秒恢复上限，最多补满生命。", ["比例"])
	_stat(&"move_speed", [&"overview", &"mobility"], "移动", "行走速度", [&"move_speed"], ["speed"], "boot", "当前基础移速经允许的成长与实时击杀加速计算，不使用旧装备字段。")
	_stat(&"haste", [&"mobility"], "临时状态", "击杀加速", [&"haste_stacks", &"haste_bonus"], ["stacks", "percent"], "boot", "每次有效击杀独立计时，提高行走和弹射实际移动速度；不增加剩余动能，暂停时不流逝。", ["层数", "双速加成"])
	_stat(&"haste_expiry", [&"mobility"], "临时状态", "下一层到期", [&"haste_expiry"], ["seconds"], "star", "当前最先到期的一层剩余战斗时间；没有生效层时显示空值。")
	_stat(&"pickup_radius", [&"mobility"], "拾取", "经验吸引范围", [&"pickup_radius"], ["meters"], "star", "读取本局经验系统的实际吸引半径，包含适用的拾取范围成长。")
	_stat(&"dash", [&"mobility"], "闪身", "闪身", [&"dash_distance", &"dash_cooldown"], ["meters", "seconds"], "boot", "人物固有闪身的实际距离与冷却，独立于弹射。", ["距离", "冷却"])

func _stat(id: StringName, categories: Array, group: String, label: String, keys: Array, formats: Array, icon: String, source: String, headings: Array = []) -> void:
	register_stat({"id": id, "categories": categories, "group": group, "label": label, "keys": keys, "formats": formats, "icon": icon, "source": source, "headings": headings})

func register_stat(definition: Dictionary) -> bool:
	if not definition.has_all(["id", "categories", "group", "label", "keys", "formats", "source"]): return false
	if String(definition.id).is_empty() or definitions.any(func(item): return item.id == definition.id): return false
	if definition["keys"].is_empty() or definition["keys"].size() != definition.formats.size(): return false
	for category in definition.categories:
		if not CATEGORIES.any(func(item): return item.id == category): return false
	definitions.append(definition.duplicate(true))
	return true

func configure(world: Node) -> void:
	_player = world.get_node_or_null("Player") as Player
	_session = world.get_node_or_null("WavePrototype") as WavePrototype

func capture() -> Dictionary:
	if not is_instance_valid(_player) or not is_instance_valid(_session): return {}
	var mods := _session.combat_modifiers
	var rules := _session.growth_rules
	var body := _player.body_ricochet
	var flying := body != null and body.flying
	var orbiting := body != null and body.orbiting
	var energy := body.flight_speed if flying else 0.0
	var growth := _session.get_node_or_null("RunGrowth") as RunGrowth
	var result := {"health_current": _player.current_health, "health_max": _player.max_health,
		"level": growth.state.level if growth and growth.state else 1,
		"damage_multiplier": mods.damage_multiplier(), "attack_frequency": 1.0 / mods.interval_multiplier(), "attack_range": mods.range_multiplier(),
		"crit_chance": _session.critical_chance, "crit_multiplier": _session.critical_multiplier,
		"speed_damage": mods.speed_damage_multiplier(energy, flying), "strikes": _session.current_sword_strikes(),
		"extra_strike": rules.additional_strike_damage_ratio if rules else 0.0,
		"energy": energy, "motion_speed": body.movement_speed if body else 0.0,
		"orbit_reduction": rules.orbit_damage_reduction if rules else 0.0,
		"sword_heal": rules.sword_heal_fraction * _player.max_health if rules else 0.0,
		"sword_heal_cap": rules.sword_heal_cap * _player.max_health if rules else 0.0,
		"vamp": mods.bonus(A.LIFESTEAL),
		"move_speed": _player.get_movement_speed(), "haste_stacks": mods.haste_stacks(), "haste_bonus": mods.haste_speed_multiplier() - 1.0,
		"haste_expiry": mods.next_haste_expiry(), "pickup_radius": growth.get_attraction_radius() if growth else null,
		"dash_distance": _player.blink_distance, "dash_cooldown": _player.blink_cooldown,
		"ricochet_context": "下次弹射", "state_label": "待机"}
	if _player.sword and _player.sword.enabled:
		for mode in ["normal", "flight"]:
			var stats := _player.sword.get_stats(mode == "flight")
			for key in ["damage", "interval", "range", "angle"]: result[mode + "_" + key] = stats[key]
	if body and body.enabled:
		var readout := body.get_attribute_readout()
		var stats: Dictionary = readout.stats
		var mapping := {"launch_min": &"minimum_launch_speed", "launch_max": &"maximum_launch_speed", "charge": &"full_charge_seconds", "launch_cooldown": &"cooldown_seconds", "recovery": &"recovery_seconds", "deceleration": &"flight_deceleration", "collision_cost": &"bounce_speed_cost", "wall_retention": &"bounce_speed_retention", "minimum_speed": &"minimum_bounce_speed"}
		for key in mapping: result[key] = stats.get(mapping[key])
		result.ricochet_context = "本次弹射" if readout.active_snapshot else "下次弹射"
		result.state_label = "持续环绕" if orbiting else ["待机", "蓄力中", "弹射中", "收势中"][readout.state]
	var conditions := {&"speed_damage": _condition(mods.bonus(A.SPEED_DAMAGE) > 0.0, flying, "飞行中"),
		&"multistrike": _condition(mods.bonus(A.MULTISTRIKE) > 0.0, flying, "飞行中"),
		&"extra_strike": _condition(mods.bonus(A.MULTISTRIKE) > 0.0, flying, "飞行中"),
		&"orbit_reduction": "生效中" if orbiting else "环绕时生效",
		&"vamp": "命中时生效" if mods.bonus(A.LIFESTEAL) > 0.0 else "未获得",
		&"haste": _condition(mods.bonus(A.KILL_HASTE) > 0.0, mods.haste_stacks() > 0, "击杀后"),
		&"energy": result.state_label, &"motion_speed": result.state_label,
		&"launch": result.ricochet_context}
	result["conditions"] = conditions
	result["baselines"] = {}
	if _player.sword and _player.sword.rules:
		var sword := _player.sword.rules
		result.baselines[&"normal_sword"] = "基础：伤害 %.2f；间隔 %.2f 秒；半径 %.2f 米。" % [sword.damage, sword.normal_interval, sword.normal_range]
		result.baselines[&"flight_sword"] = "基础：伤害 %.2f；间隔 %.2f 秒；半径 %.2f 米。" % [sword.damage, sword.flight_interval, sword.flight_range]
	if _player.ricochet_rules:
		var base := _player.ricochet_rules
		result.baselines[&"launch"] = "基础配置：起步 %.2f、满蓄 %.2f 米/秒。当前显示%s的数值。" % [base.minimum_launch_speed, base.maximum_launch_speed, result.ricochet_context]
		var fields := {&"charge": "full_charge_seconds", &"launch_cooldown": "cooldown_seconds", &"recovery": "recovery_seconds", &"deceleration": "flight_deceleration", &"collision_cost": "bounce_speed_cost", &"wall_retention": "bounce_speed_retention", &"minimum_speed": "minimum_bounce_speed"}
		for id in fields:
			var definition: Dictionary = definitions.filter(func(item): return item.id == id)[0]
			result.baselines[id] = "基础配置：%s。当前显示%s的数值。" % [format_value(base.get(fields[id]), definition.formats[0]), result.ricochet_context]
	return result

func _condition(learned: bool, active: bool, when: String) -> String:
	return "未获得" if not learned else "生效中" if active else when + "生效"

func rows(category: StringName, data: Dictionary = {}) -> Array[Dictionary]:
	if data.is_empty(): data = capture()
	var result: Array[Dictionary] = []
	for definition in definitions:
		if category not in definition.categories: continue
		var row: Dictionary = definition.duplicate(true)
		row["values"] = []
		for index in row["keys"].size(): row["values"].append(format_value(data.get(row["keys"][index]), row.formats[index]))
		row["status"] = data.get("conditions", {}).get(row.id, "")
		row["detail"] = data.get("baselines", {}).get(row.id, "") + "\n" + row.source
		result.append(row)
	return result

static func format_value(value: Variant, format: String) -> String:
	if value == null or not is_finite(float(value)): return "—"
	match format:
		"percent": return "%.1f%%" % (float(value) * 100.0)
		"multiplier": return "×%.2f" % value
		"seconds": return "%.2f 秒" % value
		"meters": return "%.2f 米" % value
		"speed": return "%.2f 米/秒" % value
		"speed_loss": return "每秒降低 %s 米/秒" % ("%.2f" % value).rstrip("0").rstrip(".")
		"health": return "%.1f 生命" % value
		"health_rate": return "%.1f /秒" % value
		"strikes": return "%d 刀/次" % value
		"stacks": return "%d 层" % value
		"degrees": return "%.0f°" % value
	return "%.0f" % value if is_equal_approx(float(value), roundf(float(value))) else "%.2f" % value
