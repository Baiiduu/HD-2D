extends SceneTree

const IMAGE := preload("res://scripts/rendering/imported_texture_image.gd")
const PREVIEW := preload("res://scripts/combat/aim_path_preview.gd")
const CASES := [
	["res://assets/meowa/slime/animations.tres", &"idle_front", 0],
	["res://assets/meowa/slime/animations.tres", &"hop_front", 0],
	["res://assets/meowa/slime/animations.tres", &"hop_front", 4],
	["res://assets/meowa/enemies/leaf_charger/animations.tres", &"walk_front", 3],
	["res://assets/meowa/enemies/lantern_spitter/animations.tres", &"skill_front", 3],
	["res://assets/meowa/enemies/pot_brood/animations.tres", &"walk_front", 3],
	["res://assets/meowa/enemies/bell_frog/animations.tres", &"walk_front", 3],
	["res://assets/meowa/enemies/mini_slime/animations.tres", &"walk_front", 3],
	["res://assets/meowa/player/animations.tres", &"idle", 0],
]
var checks := 0
var failures := 0
var preview: AimPathPreview
var sprite: Sprite3D
var camera: Camera3D
var fixture_dir := "user://tests/aim-target-image-cache"

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run this image oracle with a native rendering driver.")
		quit(2)
		return
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func base_image(image: Image) -> Image:
	if image == null: return null
	var result := image.duplicate() as Image
	if result.is_compressed(): result.decompress()
	if result.has_mipmaps(): result.clear_mipmaps()
	return result

func compare_images(actual: Image, expected: Image, label: String) -> void:
	var a := base_image(actual)
	var b := base_image(expected)
	check(a != null and b != null, label + ": both paths return image data")
	if a == null or b == null: return
	check(a.get_size() == b.get_size() and a.get_format() == b.get_format(), label + ": exact size and format")
	check(a.get_data() == b.get_data(), label + ": every base-level pixel byte matches native readback")
	check(a.get_used_rect() == b.get_used_rect(), label + ": exact nonzero-alpha boundary")

func native_bounds(texture: Texture2D) -> Rect2i:
	var atlas := texture as AtlasTexture
	var source := atlas.atlas if atlas else texture
	var image := base_image(source.get_image())
	if atlas and image:
		var region := atlas.region
		if region.size == Vector2.ZERO: region.size = source.get_size()
		image = image.get_region(region)
	var result := image.get_used_rect() if image and not image.is_empty() else Rect2i(Vector2i.ZERO, texture.get_size())
	if atlas: result.position += Vector2i(atlas.margin.position)
	return result

func mark(texture: Texture2D, label: String) -> void:
	sprite.texture = texture
	preview.mark_target(sprite)
	check(preview._bounds.has(texture) and preview._bounds[texture] == native_bounds(texture), label + ": marker keeps exact Atlas crop/margin bounds")

func imported_frames() -> void:
	var seen := {}
	for entry in CASES:
		var frames: SpriteFrames = load(entry[0])
		var texture := frames.get_frame_texture(entry[1], entry[2])
		mark(texture, entry[0] + ":" + str(entry[1]))
		var source: Texture2D = texture
		while source is AtlasTexture: source = source.atlas
		if seen.has(source): continue
		seen[source] = true
		var decoded := IMAGE.decode(source)
		if IMAGE.supports_engine():
			check(decoded != null, "verified engine supports the formal PNG/WebP/DXT5 import")
			compare_images(decoded, source.get_image(), source.resource_path)
		else:
			check(decoded == null, "an unverified engine uses native fallback")
		compare_images(IMAGE.read(source), source.get_image(), "public exact fallback/read")
	# Multiple Atlas frames from the same hop sheet retain one source fact.
	preview._clear_image_facts()
	var slime: SpriteFrames = load("res://assets/meowa/slime/animations.tres")
	mark(slime.get_frame_texture(&"hop_front", 0), "shared sheet first frame")
	mark(slime.get_frame_texture(&"hop_front", 4), "shared sheet later frame")
	check(preview._source_images.size() == 1 and preview._bounds.size() == 2, "different Atlas frames share one exact decoded sheet")

func write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

func make_png_import(pixels: Image) -> String:
	var payload := "PNG ".to_ascii_buffer() + pixels.save_png_to_buffer()
	var path := fixture_dir.path_join("valid.ctex")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer("GST2".to_ascii_buffer())
	file.store_32(1)
	file.store_32(pixels.get_width())
	file.store_32(pixels.get_height())
	file.store_32(0)
	file.store_32(0xffffffff)
	for index in 3: file.store_32(0)
	file.store_32(1)
	file.store_16(pixels.get_width())
	file.store_16(pixels.get_height())
	file.store_32(0)
	file.store_32(Image.FORMAT_RGBA8)
	file.store_32(payload.size())
	file.store_buffer(payload)
	file.close()
	return path

func format_and_pack_checks() -> void:
	var pixels := Image.create(23, 17, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.TRANSPARENT)
	pixels.set_pixel(1, 1, Color(1, 0, 0, 1.0 / 255.0))
	pixels.set_pixel(21, 15, Color(0, 1, 0, 1.0 / 255.0))
	var path := make_png_import(pixels)
	var texture := CompressedTexture2D.new()
	check(texture.load(path) == OK, "synthetic PNG uses the actual Godot import wrapper")
	compare_images(IMAGE.read(texture), texture.get_image(), "PNG import with thin alpha edge")
	check(base_image(IMAGE.read(texture)).get_used_rect() == Rect2i(1, 1, 21, 15), "alpha 1/255 boundary pixels remain visible")
	var original := FileAccess.get_file_as_bytes(path)
	for invalid in [
		[0, 0], [4, 2], [16, 1], [16, 1 << 22], [24, 1],
		[36, 3], [40, 0], [44, 20], [48, Image.FORMAT_DXT3], [52, 0xffffffff], [56, 0],
	]:
		var bytes := original.duplicate()
		bytes.encode_u32(invalid[0], invalid[1])
		var bad := fixture_dir.path_join("unknown.ctex")
		write_bytes(bad, bytes)
		check(IMAGE.decode_file(bad, Vector2i(23, 17)) == null, "unknown or malformed encoding retains native fallback")
	var truncated := fixture_dir.path_join("truncated.ctex")
	write_bytes(truncated, original.slice(0, 60))
	check(IMAGE.decode_file(truncated, Vector2i(23, 17)) == null, "truncated buffers retain native fallback")
	check(IMAGE.decode_file(path, Vector2i(24, 17)) == null, "logical-size mismatch retains native fallback")
	# Read the import from a mounted pack, without source PNG files.
	var packer := PCKPacker.new()
	var pack_path := fixture_dir.path_join("images.pck")
	var packed_path := "res://__aim_target_image_cache_test__/valid.ctex"
	check(packer.pck_start(pack_path) == OK and packer.add_file(packed_path, path) == OK and packer.flush() == OK, "make isolated imported-only texture pack")
	check(ProjectSettings.load_resource_pack(pack_path), "mount imported-only texture pack")
	var packed := CompressedTexture2D.new()
	check(packed.load(packed_path) == OK, "native texture loads the exported-style ctex path")
	compare_images(IMAGE.read(packed), packed.get_image(), "imported image in PCK without source PNG")

func changed_and_fallback_checks() -> void:
	var pixels := Image.create(32, 24, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.TRANSPARENT)
	pixels.set_pixel(4, 5, Color.WHITE)
	var texture := ImageTexture.create_from_image(pixels)
	check(IMAGE.decode(texture) == null, "dynamic ImageTexture retains the original native path")
	compare_images(IMAGE.read(texture), texture.get_image(), "dynamic texture fallback")
	mark(texture, "dynamic before")
	pixels.set_pixel(30, 22, Color(1, 0, 0, 1.0 / 255.0))
	texture.set_image(pixels)
	texture.emit_changed()
	check(preview._bounds.is_empty() and preview._source_images.is_empty(), "changed immediately invalidates all image facts")
	mark(texture, "dynamic after")
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(0, 0, 16, 12)
	atlas.margin = Rect2(2, 3, 4, 6)
	mark(atlas, "Atlas before")
	atlas.region = Rect2(0, 0, 32, 24)
	check(preview._bounds.is_empty(), "Atlas region changes invalidate immediately")
	mark(atlas, "Atlas region after")
	atlas.margin = Rect2(5, 7, 8, 10)
	check(preview._bounds.is_empty(), "Atlas margin changes invalidate immediately")
	mark(atlas, "Atlas margin after")
	pixels.set_pixel(1, 1, Color.WHITE)
	texture.set_image(pixels)
	texture.emit_changed()
	check(preview._bounds.is_empty(), "underlying image change invalidates Atlas frame facts")
	mark(atlas, "Atlas parent after")
	preview._clear_image_facts()
	check(preview._bounds.is_empty() and preview._source_images.is_empty() and preview._image_watches.is_empty(), "clearing facts releases cached images and resource listeners")

func run() -> void:
	fixture_dir = fixture_dir.path_join(str(OS.get_process_id()))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture-dir="): fixture_dir = argument.trim_prefix("--fixture-dir=")
	DirAccess.make_dir_recursive_absolute(fixture_dir)
	root.size = Vector2i(64, 64)
	camera = Camera3D.new()
	root.add_child(camera)
	camera.position.z = 3.0
	camera.current = true
	sprite = Sprite3D.new()
	root.add_child(sprite)
	sprite.position.x = 1000.0
	preview = PREVIEW.new()
	root.add_child(preview)
	preview.display(AimPathData.new(), camera, 0.016, 0.015, 0.7, 1.0, Color.WHITE, 0.45)
	preview.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	imported_frames()
	format_and_pack_checks()
	changed_and_fallback_checks()
	print("Aim target image cache: %d checks, %d failures; verified_engine=%s" % [checks, failures, IMAGE.supports_engine()])
	preview.queue_free()
	sprite.queue_free()
	camera.queue_free()
	await process_frame
	quit(1 if failures else 0)
