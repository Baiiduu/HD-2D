extends SceneTree
## 只检查表现数据和交互状态，不启动渲染窗口或评价美术观感。
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func run() -> void:
	var ordinary := GrowthChoiceOption.new()
	check(ordinary.has_method("get_card_rarity"), "Card rarity resolves explicit tiers and legacy epic flags")
	if not ordinary.has_method("get_card_rarity"):
		quit(1)
		return
	check(ordinary.call("get_card_rarity") == 0, "Existing ordinary options retain the common appearance")
	var epic := GrowthChoiceOption.new()
	epic.epic = true
	check(epic.call("get_card_rarity") == 1, "Existing epic unlocks and upgrades automatically use epic frames")
	for rarity in range(4):
		epic.set("rarity", rarity)
		check(epic.call("get_card_rarity") == rarity and epic.epic, "Explicit rarity takes priority while preserving the legacy serialized epic flag")
	var ui: GrowthChoiceUI = load("res://scenes/ui/growth_choice_ui.tscn").instantiate()
	ui.set("ink_style", true)
	ui.open_duration = 0.0
	ui.hover_duration = 0.0
	ui.get_node("UIAudio").enabled = false
	root.add_child(ui)
	var a := GrowthChoiceOption.new()
	a.id = &"a"
	a.title = "空间扩张\nLv.1"
	a.epic = true
	var b := GrowthChoiceOption.new()
	b.id = &"b"
	b.title = "伤害提升\nLv.2"
	b.description = "提高攻击造成的伤害\n共有伤害\n×1.00 → ×1.20"
	ui.present_choices([a, b])
	check(ui.selected_index == -1 and ui._cards.all(func(card): return not card.selected), "Ink cards also require explicit choice without favoring a direction")
	var first: GrowthChoiceCard = ui._cards[0]
	var second: GrowthChoiceCard = ui._cards[1]
	var material_a: ShaderMaterial = first.get_node("Frame").material
	var material_b: ShaderMaterial = second.get_node("Frame").material
	var gain := second.get_node_or_null("Gain") as Label
	check(gain != null, "The base card has a separate numerical benefit field")
	if not gain:
		ui.free()
		await process_frame
		quit(1)
		return
	check(gain.text == "×1.00 → ×1.20" and gain.visible, "A single actual benefit row is emphasized without recalculating it")
	check(not (second.get_node("Description") as Label).text.contains("×1.00") and b.description.contains("×1.00"), "Presentation separates the value while retaining the original complete description")
	var combined := GrowthChoiceOption.new()
	combined.id = &"combined"
	combined.description = "伤害增幅\n1% → 3%\n攻速增幅\n3% → 5%"
	second.configure(combined, 0.96, 1.0, 0.0, 20, Color.WHITE, true)
	check(not gain.visible and (second.get_node("Description") as Label).text.contains("1% → 3%") and (second.get_node("Description") as Label).text.contains("3% → 5%"), "Cards with multiple values retain all actual benefits")
	second.configure(b, 0.96, 1.0, 0.0, 20, Color.WHITE, true)
	var structured := GrowthChoiceOption.new()
	structured.id = &"structured"
	structured.title = "组合增益\nLv.1"
	structured.description = "同时提高伤害与攻击速度\n\n伤害增幅 0% → 3%\n攻速增幅 0% → 5%"
	second.configure(structured, 0.96, 1.0, 0.0, 20, Color.WHITE, true)
	check(gain.visible and gain.text.contains("伤害增幅 0% → 3%") and gain.text.contains("攻速增幅 0% → 5%"), "Structured numerical rows keep every benefit with its corresponding label")
	check((second.get_node("Description") as Label).text == structured.description.split("\n\n")[0], "Effect prose and numerical changes have separate presentation fields")
	structured.description = "\n\n伤害 10 → 12\n间隔 1 → 0.9 秒"
	second.configure(structured, 0.96, 1.0, 0.0, 20, Color.WHITE, true)
	check(not second.get_node("Description").visible and gain.visible and gain.text.contains("间隔"), "Upgrade-only rows need no repeated mechanics paragraph")
	check(structured.description.begins_with("\n\n"), "Presenting a card does not rewrite its caller-owned text")
	second.configure(b, 0.96, 1.0, 0.0, 20, Color.WHITE, true)
	check(material_a != material_b, "Highlight material is isolated per card")
	check(first.get_node("Frame").texture.get_size() == material_a.get_shader_parameter("selected_texture").get_size(), "Normal and selected assets share the same native canvas")
	check(first.get_node("Title").get_theme_font("font").resource_path.ends_with("MaokenAssortedSans.ttf"), "Ink cards use the actual shared Chinese font")
	check(is_zero_approx(float(material_a.get_shader_parameter("selected_mix"))), "An unselected fresh card has no selection glow")
	ui.select_option(&"b")
	check(is_zero_approx(float(material_a.get_shader_parameter("selected_mix"))) and is_equal_approx(float(material_b.get_shader_parameter("selected_mix")), 1.0), "Explicit choice highlights only the selected edge")
	ui.present_choices([a, b])
	check(ui.selected_index == -1 and ui._confirm.disabled, "Redraw clears the selected state")
	first = ui._cards[0]
	first.set_revealed(false)
	first.set_selected(true)
	check(is_zero_approx(float(first.get_node("Frame").material.get_shader_parameter("selected_mix"))), "Concealed cards do not leak a selected glow")
	# 同屏卡片共用正文字号；文案较长不能单独改变其中一张的字体层级。
	var storm_card := GrowthChoiceOption.new()
	storm_card.id = &"storm_typography"
	storm_card.title = "奔雷涌潮\nLv.1"
	storm_card.description = "弹射近敌时释放雷潮\n每轮每怪一次\n下一轮可再次命中\n\n伤害 20 · 间隔 0.9 秒\n每轮最多 6 只\n扩散最远 3.6 米"
	var haste_card := GrowthChoiceOption.new()
	haste_card.id = &"haste_typography"
	haste_card.title = "杀怪加速\nLv.1/5"
	haste_card.description = "击杀叠加移速与弹射速度\n每层独立计时\n\n每层加速 0% → 5%\n每层 4 秒 · 最多 10 层\n满层加速 0% → 50%"
	ui.card_width = 340.0
	ui.present_choices([storm_card, haste_card])
	var dense_body := ui._cards[0].get_node("Description") as Label
	var short_body := ui._cards[1].get_node("Description") as Label
	var shared_size := dense_body.get_theme_font_size("font_size")
	check(shared_size == short_body.get_theme_font_size("font_size"), "Dense and short cards on the same screen share their body font size")
	check(ui._cards.all(func(card): return card.get_node("Gain").get_theme_font_size("font_size") == shared_size), "Numerical rows use the same shared body size on every card")
	check(ui._cards.all(func(card): return card.get_node("Description").get_theme_font("font") == card.get_node("Title").get_theme_font("font")), "Body and title retain the actual shared font family")
	check(ui._cards.all(func(card): return card.get_node("Title").get_theme_font_size("font_size") == ui.content_font_size + 7), "Fitting dense body text preserves the title hierarchy")
	ui.card_width = 420.0
	check(ui._cards[0].get_node("Description").get_theme_font_size("font_size") == ui._cards[1].get_node("Description").get_theme_font_size("font_size"), "Changing card width recalculates one body size for the whole row")
	ui.present_choices([haste_card])
	check(ui._cards[0].get_node("Description").get_theme_font_size("font_size") == ui.content_font_size, "A shorter new draw restores the preferred size rather than keeping an old reduction")
	ui.free()
	await process_frame
	# Inspect serialized overrides without constructing unrelated map/UI components.
	for map_name in ["world", "city"]:
		var packed: PackedScene = load("res://scenes/%s/%s.tscn" % [map_name, map_name])
		var expected: bool = map_name == "world"
		check(authored_ink_style(packed, "WavePrototype/RunGrowth/GrowthChoiceUI") == expected, "Only World enables ink upgrade cards")
		check(authored_ink_style(packed, "WavePrototype/SkillDraft/InitialSkillChoice") == expected, "Only World enables ink initial cards")
	await process_frame
	print("Growth card presentation: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func authored_ink_style(packed: PackedScene, path: String) -> bool:
	var state := packed.get_state()
	for index in state.get_node_count():
		if String(state.get_node_path(index)).trim_prefix("./") != path: continue
		for property in state.get_node_property_count(index):
			if state.get_node_property_name(index, property) == &"ink_style":
				return state.get_node_property_value(index, property)
	return false
