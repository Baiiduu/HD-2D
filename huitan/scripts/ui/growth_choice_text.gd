@tool
extends RefCounted
## 空行分隔效果说明与数值区，避免界面再猜测一行数字属于哪个标签。

static func compose(summary: String, rows: PackedStringArray) -> String:
	return summary.strip_edges() + ("\n\n" + "\n".join(rows) if not rows.is_empty() else "")

static func number(value: float, decimals := 2) -> String:
	var result := ("%." + str(decimals) + "f") % value
	if result.contains("."):
		while result.ends_with("0"): result = result.trim_suffix("0")
		result = result.trim_suffix(".")
	return result

## 字段为 [数值键, 玩家标签, 小数位, 单位]；升级只显示真正改变的数值。
static func skill(summary: String, initial: bool, before: Dictionary, after: Dictionary, fields: Array) -> String:
	var rows := PackedStringArray()
	for field in fields:
		var key: String = field[0]
		if not initial and before.has(key) and is_equal_approx(float(before[key]), float(after[key])): continue
		var value := number(float(after[key]), field[2])
		if not initial and before.has(key): value = number(float(before[key]), field[2]) + " → " + value
		rows.append("%s %s%s" % [field[1], value, field[3]])
	return compose(summary, rows)
