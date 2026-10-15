class_name ImportedTextureImage
extends RefCounted

## Exact CPU facts from the imported texture, including exported PCK files.
## Verified against Godot 4.7.2 ed1daf0bf GST2 v1. Unknown engines, encodings,
## pixel formats, dimensions or buffers retain native texture.get_image().
## No source PNG access, resizing, alpha threshold or GPU texture mutation.
const VERIFIED_ENGINE_HASH := "ed1daf0bf"

static func supports_engine() -> bool:
	return str(Engine.get_version_info().get("hash", "")).begins_with(VERIFIED_ENGINE_HASH)

static func read(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var image := decode(texture)
	return image if image else texture.get_image()

static func decode(texture: Texture2D) -> Image:
	if not supports_engine():
		return null
	var imported := texture as CompressedTexture2D
	if imported == null:
		return null
	var path := imported.get_load_path()
	return decode_file(path, Vector2i(texture.get_size()))

static func decode_file(path: String, expected_size: Vector2i) -> Image:
	if not supports_engine():
		return null
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 56:
		return null
	if file.get_buffer(4).get_string_from_ascii() != "GST2" or file.get_32() != 1:
		return null
	var logical_width := file.get_32()
	var logical_height := file.get_32()
	if Vector2i(logical_width, logical_height) != expected_size:
		return null
	var flags := file.get_32()
	var known_flags := (1 << 22) | (1 << 23) | (1 << 24) | (1 << 26) | (1 << 27)
	# Streamed and unknown imports have not been proven by this prototype.
	if (flags & ~known_flags) != 0 or (flags & (1 << 22)) != 0:
		return null
	file.get_32() # mipmap limit; only the full original base image is consumed.
	for reserved in 3:
		if file.get_32() != 0:
			return null
	var encoding := file.get_32()
	var width := file.get_16()
	var height := file.get_16()
	var mipmaps := file.get_32()
	var format := file.get_32()
	if encoding not in [0, 1, 2] or width <= 0 or height <= 0:
		return null
	if Vector2i(width, height) != expected_size:
		return null
	var max_mipmaps := 0
	var smallest_width := width
	var smallest_height := height
	while smallest_width > 1 or smallest_height > 1:
		smallest_width = maxi(1, smallest_width >> 1)
		smallest_height = maxi(1, smallest_height >> 1)
		max_mipmaps += 1
	if mipmaps > max_mipmaps or ((flags & (1 << 23)) != 0) != (mipmaps > 0):
		return null
	if encoding == 0:
		# Only this project's proven raw VRAM format is supported. Let Image
		# perform exactly the same DXT5 decode as the native get_image caller.
		if format != Image.FORMAT_DXT5:
			return null
		var bytes := 0
		var level_width := width
		var level_height := height
		for level in mipmaps + 1:
			bytes += maxi(1, (level_width + 3) >> 2) * maxi(1, (level_height + 3) >> 2) * 16
			level_width = maxi(1, level_width >> 1)
			level_height = maxi(1, level_height >> 1)
		if file.get_length() - file.get_position() != bytes:
			return null
		return Image.create_from_data(width, height, mipmaps > 0, Image.FORMAT_DXT5, file.get_buffer(bytes))
	if format not in [Image.FORMAT_L8, Image.FORMAT_LA8, Image.FORMAT_R8,
		Image.FORMAT_RG8, Image.FORMAT_RGB8, Image.FORMAT_RGBA8,
		Image.FORMAT_RGBA4444, Image.FORMAT_RGB565]:
		return null
	var payload := PackedByteArray()
	for level in mipmaps + 1:
		if file.get_length() - file.get_position() < 4:
			return null
		var payload_size := file.get_32()
		if payload_size <= 0 or payload_size > file.get_length() - file.get_position():
			return null
		if level == 0:
			payload = file.get_buffer(payload_size)
		else:
			file.seek(file.get_position() + payload_size)
	if file.get_position() != file.get_length():
		return null
	if encoding == 1:
		# Godot's Image::png_packer prepends "PNG " before standard PNG bytes.
		if payload.size() < 12 or payload.slice(0, 4).get_string_from_ascii() != "PNG ":
			return null
		payload = payload.slice(4)
		if payload.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
			return null
	if encoding == 2 and (payload.size() < 12 or payload.slice(0, 4).get_string_from_ascii() != "RIFF" or payload.slice(8, 12).get_string_from_ascii() != "WEBP"):
		return null
	var image := Image.new()
	var error := image.load_png_from_buffer(payload) if encoding == 1 else image.load_webp_from_buffer(payload)
	if error != OK or image.is_empty() or image.is_compressed() or image.get_size() != Vector2i(width, height):
		return null
	if image.get_format() != format:
		image.convert(format)
	return image
