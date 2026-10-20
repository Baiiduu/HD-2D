extends VBoxContainer
## 只读局内属性，复用设置主题；可见时低频刷新，不占用战斗时钟。
var session: WavePrototype
var _values: Label
var _clock := 0.0

func configure(world: Node) -> void:
	session = world.get_node_or_null("WavePrototype") as WavePrototype
	var heading := Label.new()
	heading.text = "本局人物属性"
	heading.add_theme_font_size_override("font_size", 28)
	add_child(heading)
	_values = Label.new()
	_values.add_theme_font_size_override("font_size", 20)
	_values.add_theme_constant_override("line_spacing", 10)
	_values.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_values)
	refresh()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_clock -= delta
	if _clock <= 0.0:
		_clock = 0.15
		refresh()

func refresh() -> void:
	if not _values: return
	_values.text = "进入地图后查看属性。" if not is_instance_valid(session) else ""
	if not is_instance_valid(session) or not is_instance_valid(session.player): return
	var player := session.player
	var mods := session.combat_modifiers
	var body := player.body_ricochet
	var flying := body != null and body.flying
	var speed := body.flight_speed if flying else 0.0
	var rules := session.growth_rules
	var lines := PackedStringArray([
		"生命　%.0f / %.0f" % [player.current_health, player.max_health],
		"伤害　×%.2f　　攻击频率　×%.2f" % [mods.damage_multiplier(), 1.0 / mods.interval_multiplier()],
		"攻击范围　×%.2f" % mods.range_multiplier(),
		"暴击　尚未启用",
	])
	if body and player.ricochet_rules:
		var stats := body.get_stats()
		lines.append("满蓄初速　%.2f 米/秒　　当前余速　%.2f 米/秒" % [stats.maximum_launch_speed, speed])
		lines.append("飞行耗速　%.2f 米/秒²　　碰撞固定耗速　%.2f 米/秒" % [stats.flight_deceleration, stats.bounce_speed_cost])
	if rules:
		var tier := rules.speed_tier(speed, session._strike_speed_tier)
		lines.append("当前动能增伤　×%.2f　　弹射挥剑　%d 刀/次" % [mods.speed_damage_multiplier(speed, flying), mods.strike_count(tier, flying)])
		lines.append("绕行减伤　%.0f%%　　剑术命中恢复　%.1f%% 生命/次" % [rules.orbit_damage_reduction * 100, rules.sword_heal_fraction * 100])
		lines.append("剑术恢复上限　%.1f 生命/秒" % (rules.sword_heal_cap * player.max_health))
	lines.append("全能吸血　%.1f%%　　独立上限　%.1f 生命/秒" % [mods.bonus(GrowthBuffEffect.Attribute.LIFESTEAL) * 100, mods.bonus(GrowthBuffEffect.Attribute.LIFESTEAL_CAP) * player.max_health])
	for attack in session.get_attack_stats():
		if attack.has("interval"): lines.append("%s　%.2f 秒/次" % [attack.get("name", "攻击"), attack.interval])
	var buffs := session.get_node_or_null("RunBuffs") as RunBuffs
	if buffs:
		for definition in buffs.definitions:
			if definition and definition.epic and mods.level_for(definition.id) > 0:
				lines.append("%s　Lv.%d" % [definition.title, mods.level_for(definition.id)])
	_values.text = "\n".join(lines)
