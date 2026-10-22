extends RefCounted
## Prototype lives outside res://, so a missing optional DLL never breaks maps
## or exports. Only the explicit simulation switch requests this extension.
static func create() -> RefCounted:
	if not ClassDB.class_exists(&"HDSwarmKernel"):
		var manifest := ProjectSettings.globalize_path("res://native/swarm/hd2d_swarm.gdextension").simplify_path()
		if OS.get_name() != "Windows" or not FileAccess.file_exists(manifest.get_base_dir().path_join("bin/hd2d_swarm.dll")): return null
		var status := GDExtensionManager.load_extension(manifest)
		if status not in [GDExtensionManager.LOAD_STATUS_OK, GDExtensionManager.LOAD_STATUS_ALREADY_LOADED]: return null
	if not ClassDB.class_exists(&"HDSwarmKernel"): return null
	return ClassDB.instantiate(&"HDSwarmKernel") as RefCounted
