@tool
class_name SurfaceNormalMaps
extends RefCounted

const MANIFEST := "res://assets/surface_normals/manifest.json"
static var _manifest: Dictionary = {}
static var _loaded := false
static var _textures: Dictionary = {}

static func for_texture(source: Texture2D) -> Texture2D:
	if not source: return null
	var base := (source as AtlasTexture).atlas if source is AtlasTexture else source
	if not base: return null
	if not _loaded:
		_manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		_loaded = true
	var path := base.resource_path
	if not _manifest.has(path): return null
	if not _textures.has(path): _textures[path] = load(_manifest[path].normal)
	return _textures[path]
