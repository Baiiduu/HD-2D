extends SceneTree
## Data-only release check. Never instantiates World or opens a rendering window.

const MANIFESTS := [
	"res://assets/surface_normals/manifest.json",
	"res://assets/meowa/dressing/assets.json",
	"res://assets/meowa/dressing/forest/assets.json",
]
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_check_pack")

func _check_pack() -> void:
	_expect(ProjectSettings.get_setting("application/config/name") == "回弹", "Wrong game name")
	var legacy_user_dir := OS.get_data_dir().path_join("Godot/app_userdata/四境 · HD-2D").simplify_path()
	_expect(OS.get_user_data_dir().simplify_path() == legacy_user_dir, "Renaming must preserve existing Windows saves and leaderboard identity")
	_expect(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/world/world.tscn", "Wrong main scene")
	_expect(ResourceLoader.load("res://scenes/world/world.tscn") is PackedScene, "World cannot be loaded from the pack")
	_expect(ResourceLoader.load("res://data/world/world_surface.res") != null, "Painted terrain is missing")
	_expect(ResourceLoader.load("res://data/combat/scenes/world/configuration.tres") != null, "World combat configuration is missing")
	var privacy_model = load("res://scripts/network/leaderboard_state.gd").new()
	_expect(not privacy_model.upload_authorized() and privacy_model.device_id.is_empty(), "Release leaderboard must default to no upload and no generated identity")
	for path in MANIFESTS:
		var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_expect(document is Dictionary, "Missing or invalid manifest: " + path)
		if document is Dictionary:
			_check_references(document)
	for excluded in ["res://tests/test_wave_core.gd", "res://tools/benchmark_combat_fps.gd", "res://scenes/previews/four_realms.tscn"]:
		_expect(not ResourceLoader.exists(excluded), "Development resource included: " + excluded)
	for excluded in ["res://docs/README.md", "res://services/leaderboard/leaderboard/app.py", "res://native/swarm/hd2d_swarm.gdextension", "res://.env", "res://.codex/config.toml", "res://mcp.json", "res://addons/godot-mcp/plugin.gd", "res://scripts/ui/privacy_policy_dialog.gd", "res://data/legal/privacy_policy.txt"]:
		_expect(not FileAccess.file_exists(excluded), "Non-game file included: " + excluded)
	for excluded in ["res://AGENTS.override.md", "res://CLAUDE.local.md", "res://.agents/skills/agent-logger/routes.json", "res://.cursor/rules/agent-logger.mdc"]:
		_expect(not FileAccess.file_exists(excluded), "Local agent setting included: " + excluded)
	var output := OS.get_cmdline_user_args()
	if output.size() == 1 and failures.is_empty():
		var directory := output[0]
		DirAccess.make_dir_recursive_absolute(directory)
		var notice := FileAccess.open(directory.path_join("Godot.txt"), FileAccess.WRITE)
		_expect(notice != null, "Cannot write Godot license")
		if notice:
			notice.store_string(Engine.get_license_text())
			notice.close()
		var dependencies := FileAccess.open(directory.path_join("Godot-third-party.json"), FileAccess.WRITE)
		_expect(dependencies != null, "Cannot write engine dependency notices")
		if dependencies:
			dependencies.store_string(JSON.stringify({"copyright": Engine.get_copyright_info(), "licenses": Engine.get_license_info()}, "\t"))
			dependencies.close()
	print("WINDOWS_PACK_CHECK " + JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _check_references(value: Variant) -> void:
	if value is Dictionary:
		for key in value:
			if key is String and key.begins_with("res://"):
				_expect(ResourceLoader.exists(key), "Manifest source missing: " + key)
			_check_references(value[key])
	elif value is Array:
		for item in value:
			_check_references(item)
	elif value is String and value.begins_with("res://"):
		_expect(ResourceLoader.load(value) != null, "Manifest resource missing: " + value)

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)
