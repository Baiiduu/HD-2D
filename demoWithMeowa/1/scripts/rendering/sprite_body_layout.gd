extends RefCounted
## 仅缓存原生顶点和 UV，不保存人物位置、姿态或当前帧。四种遮罩共用一次读取。
const META := &"prepared_body_layouts"
const CAPACITY := 256

static func sample(source: Sprite3D, cache_owner: Sprite3D = null) -> Array:
	if not cache_owner: cache_owner = source
	var cache: Dictionary = cache_owner.get_meta(META, {})
	var key := key_for(source)
	if not cache.has(key):
		var arrays := RenderingServer.mesh_surface_get_arrays(source.get_base(), 0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		if cache.size() >= CAPACITY: cache.clear()
		cache[key] = [vertices[0], vertices[1]-vertices[0], vertices[3]-vertices[0], uvs[0], uvs[1]-uvs[0], uvs[3]-uvs[0]]
		cache_owner.set_meta(META, cache)
	return cache[key]

static func key_for(source: Sprite3D) -> Array:
	var key: Array = [source.texture.get_size(), source.get_item_rect(), source.pixel_size,
		source.axis, source.hframes, source.vframes, source.frame, source.region_enabled, source.region_rect, source.flip_h, source.flip_v]
	var texture := source.texture
	# 普通贴图的原生四边形只依赖尺寸和裁切，换同画布帧不必重复向渲染线程读回。
	# 图集及其它纹理类型继续保留资源身份，避免把特殊的区域映射合并。
	if not (texture is CompressedTexture2D or texture is ImageTexture):
		key.append_array([texture, texture.get_rid()])
	while texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		key.append_array([atlas.region, atlas.margin, atlas.atlas, atlas.atlas.get_size() if atlas.atlas else Vector2.ZERO])
		texture = atlas.atlas
	return key
