extends RefCounted
## Executes the selected scalar/vector shader functions as CPU data, without rendering.
## Texture values are deterministic probes, not a GPU sampler/derivative simulation.

static func build(source: String, functions: Array[String]) -> RefCounted:
	var code := "extends RefCounted\n" + PRELUDE
	var uniform := RegEx.new()
	uniform.compile("uniform (float|bool|vec[234]|sampler2D) (\\w+)(?:\\s*:[^=;]*)?(?:\\s*=\\s*([^;]+))?;")
	for match in uniform.search_all(source):
		var value := match.get_string(3)
		if match.get_string(1) == "sampler2D": value = '"' + match.get_string(2) + '"'
		code += "var " + match.get_string(2) + " = " + value + "\n"
	for function in functions:
		var signature := RegEx.new()
		signature.compile("(?:void|float|vec[234]|GroundFireSurface) " + function + "\\(([^)]*)\\)\\s*\\{")
		var match := signature.search(source)
		assert(match != null, "Missing shader function: " + function)
		var begin := match.get_end()
		var end := begin
		var depth := 1
		while depth > 0:
			if source[end] == "{": depth += 1
			if source[end] == "}": depth -= 1
			end += 1
		var parameters := PackedStringArray()
		for parameter in match.get_string(1).split(",", false):
			parameters.append(parameter.strip_edges().get_slice(" ", 1))
		code += "func " + function + "(" + ", ".join(parameters) + "):\n"
		if function == "fire_noise": code += "\tnoise_calls += 1\n"
		var body := source.substr(begin, end - begin - 1)
		var comments := RegEx.new()
		comments.compile("//[^\\n]*")
		body = comments.sub(body, "", true)
		body = body.replace("{", "{\n").replace("}", "\n}\n").replace(";", ";\n")
		depth = 1
		for raw in body.split("\n", false):
			var line := raw.strip_edges().trim_suffix(";")
			if line.is_empty(): continue
			if line == "}":
				depth -= 1
				continue
			var block := line.ends_with("{")
			if block: line = line.trim_suffix("{").strip_edges()
			line = line.replace("GroundFireSurface surface", "var surface = Surface.new()")
			var declaration := RegEx.new()
			declaration.compile("^(?:float|bool|vec[234]) (\\w+)")
			line = declaration.sub(line, "var $1")
			line = line.replace("body_mask_enabled ? 1.0 - body_coverage(VERTEX, PROJECTION_MATRIX[3][3] > 0.5) : 1.0", "(1.0 - body_coverage(VERTEX, PROJECTION_MATRIX[3][3] > 0.5) if body_mask_enabled else 1.0)")
			line = line.replace("brush_region.xy", "vec2(brush_region.x, brush_region.y)").replace("brush_region.zw", "vec2(brush_region.z, brush_region.w)")
			line = line.replace("pixel + 0.5", "pixel + vec2(0.5)")
			line = line.replace("3.0 - 2.0 * f", "vec2(3.0) - 2.0 * f")
			line = line.replace("&&", " and ").replace("||", " or ")
			line = line.replace("mix(", "lerp(").replace("atan(", "atan2(").replace("mod(", "fposmod(")
			if line.contains(".rgb"): line = line.replace("= texture(", "= rgb(texture(").replace(".rgb", ")")
			for channel in {"r": "x", "g": "y", "b": "z", "a": "w"}:
				var component := RegEx.new()
				component.compile("\\." + channel + "\\b")
				line = component.sub(line, "." + {"r": "x", "g": "y", "b": "z", "a": "w"}[channel], true)
			line = line.replace("discard", "return 0.0")
			if line.begins_with("if ("):
				var close := 4
				var parentheses := 1
				while parentheses > 0:
					if line[close] == "(": parentheses += 1
					if line[close] == ")": parentheses -= 1
					close += 1
				close -= 1
				var condition := line.substr(4, close - 4)
				var statement := line.substr(close + 1).strip_edges()
				line = "if " + condition + ":" + (" " + statement if not statement.is_empty() else "")
			assert(not line.contains("?"), "Unsupported shader expression: " + line)
			code += "\t".repeat(depth) + line + "\n"
			if block: depth += 1
		if function == "fragment": code += "\treturn ALPHA\n"
	var script := GDScript.new()
	script.source_code = code
	if script.reload() != OK:
		printerr(code)
		return null
	return script.new()

const PRELUDE := """
class Surface:
	var albedo = Vector3.ZERO
	var emission = Vector3.ZERO
	var coverage = 0.0
var UV = Vector2.ZERO
var UV2 = Vector2.ZERO
var VERTEX = Vector3.ZERO
var PROJECTION_MATRIX = [[0,0,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,1]]
var ALBEDO = Vector3.ZERO
var EMISSION = Vector3.ZERO
var ALPHA = 0.0
var body_mask_enabled = false
var body_cover = 0.0
var mask_calls = 0
var texture_calls = 0
var noise_calls = 0
var ink_mode = 1
func vec2(x, y = null):
	return Vector2(x, x if y == null else y)
func vec3(x, y = null, z = null):
	return Vector3(x, x, x) if y == null else Vector3(x, y, z)
func vec4(x, y, z, w):
	return Vector4(x,y,z,w)
func dot(a, b): return a.dot(b)
func length(value): return value.length()
func fract(value): return value - floor(value)
func step(edge, value): return 0.0 if value < edge else 1.0
func rgb(value): return Vector3(value.x, value.y, value.z)
func texture(sampler, uv):
	texture_calls += 1
	if sampler == "flow_brush" and ink_mode == 0: return Vector4.ZERO
	var v = clamp(0.5 + 0.5 * sin(uv.x * 13.1 + uv.y * 7.7), 0.0, 1.0)
	return Vector4(v, v * 0.7, v * 0.4, 1.0)
func body_coverage(_position, _orthographic):
	mask_calls += 1
	return body_cover
"""
