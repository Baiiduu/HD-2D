@tool
class_name HDRBokeh
extends CompositorEffect
## Linear HDR depth of field, with isolated highlights scattered as separate lens discs.
## Runs before Godot glow/ACES. Buffers belong to the viewport and are recreated on resize.

const PREFILTER = preload("res://shaders/visual/dof_prefilter.glsl")
const GATHER = preload("res://shaders/visual/dof_gather.glsl")
const BOKEH = preload("res://shaders/visual/dof_bokeh.glsl")
const COMPOSITE = preload("res://shaders/visual/dof_composite.glsl")

@export_range(0.1, 20.0) var focus_band := 6.0
@export_range(0.0, 30.0) var blur_pixels_1080 := 13.0
@export_range(0.0, 3.0) var near_multiplier := 1.5
@export_range(0.0, 3.0) var far_multiplier := 1.15
@export_range(0.0, 1.0) var tilt_strength := 0.42
@export_range(0.0, 1.0) var tilt_center := 0.5
@export_range(0.0, 1.0) var tilt_width := 0.3
@export_range(0.01, 1.0) var tilt_feather := 0.3
@export_range(0.1, 10.0) var highlight_threshold := 1.5
@export_range(0.0, 4.0) var highlight_gain := 1.6

var _rd: RenderingDevice
var _context: StringName
var _shaders: Array[RID] = []
var _pipelines: Array[RID] = []
var _scatter_pipeline := RID()
var _sampler := RID()
var _mutex := Mutex.new()
var _camera := Vector3(28.0, 0.05, 150.0)
var _rendered_frames := 0
var _failed := false
var _buffer_owners: Dictionary = {}

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true
	_context = StringName("hdr_bokeh_%d" % get_instance_id())
	_rd = RenderingServer.get_rendering_device()

func set_camera_state(depth: float, near_plane: float, far_plane: float) -> void:
	_mutex.lock()
	_camera = Vector3(maxf(depth, near_plane), near_plane, far_plane)
	_mutex.unlock()

func debug_state() -> Dictionary:
	_mutex.lock()
	var result := {"frames": _rendered_frames, "failed": _failed, "focus_depth": _camera.x}
	_mutex.unlock()
	return result

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd:
		# A viewport can survive level changes. Retire this effect's named buffers as well as its shaders.
		RenderingServer.call_on_render_thread(HDRBokeh._release_contexts.bind(_context, _buffer_owners.values()))
		for shader in _shaders:
			if shader.is_valid(): _rd.free_rid(shader)
		if _sampler.is_valid(): _rd.free_rid(_sampler)

static func _release_contexts(context: StringName, owners: Array) -> void:
	for owner: WeakRef in owners:
		var buffers := owner.get_ref() as RenderSceneBuffersRD
		if buffers: buffers.clear_context(context)

func _initialize_gpu() -> bool:
	if _failed or not _rd: return false
	if not _shaders.is_empty(): return true
	for file: RDShaderFile in [PREFILTER, GATHER, BOKEH, COMPOSITE]:
		var spirv := file.get_spirv()
		if not spirv.compile_error_compute.is_empty() or not spirv.compile_error_vertex.is_empty() or not spirv.compile_error_fragment.is_empty():
			push_error("HDRBokeh: shader import failed: " + file.resource_path)
			_failed = true
			return false
		_shaders.append(_rd.shader_create_from_spirv(spirv))
	_pipelines = [_rd.compute_pipeline_create(_shaders[0]), _rd.compute_pipeline_create(_shaders[1]), RID(), _rd.compute_pipeline_create(_shaders[3])]
	var sampler := RDSamplerState.new()
	sampler.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = _rd.sampler_create(sampler)
	return true

func _uniform(binding: int, texture: RID, sampled := true) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.binding = binding
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE if sampled else RenderingDevice.UNIFORM_TYPE_IMAGE
	if sampled: uniform.add_id(_sampler)
	uniform.add_id(texture)
	return uniform

func _dispatch(index: int, uniforms: Array[RDUniform], push: PackedFloat32Array, size: Vector2i) -> void:
	var set := UniformSetCacheRD.get_cache(_shaders[index], 0, uniforms)
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipelines[index])
	_rd.compute_list_bind_uniform_set(list, set, 0)
	_rd.compute_list_set_push_constant(list, push.to_byte_array(), push.size() * 4)
	_rd.compute_list_dispatch(list, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
	_rd.compute_list_end()

func _scatter(texture: RID, uniforms: Array[RDUniform], push: PackedFloat32Array, size: Vector2i) -> void:
	var framebuffer := FramebufferCacheRD.get_cache_multipass([texture], [], 1)
	if not _scatter_pipeline.is_valid():
		var attachment := RDPipelineColorBlendStateAttachment.new()
		attachment.enable_blend = true
		attachment.src_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		attachment.dst_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		attachment.src_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		attachment.dst_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		var blend := RDPipelineColorBlendState.new()
		blend.attachments = [attachment]
		var raster := RDPipelineRasterizationState.new()
		raster.cull_mode = RenderingDevice.POLYGON_CULL_DISABLED
		_scatter_pipeline = _rd.render_pipeline_create(_shaders[2], _rd.framebuffer_get_format(framebuffer), -1,
			RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, raster, RDPipelineMultisampleState.new(), RDPipelineDepthStencilState.new(), blend)
	var set := UniformSetCacheRD.get_cache(_shaders[2], 0, uniforms)
	var list := _rd.draw_list_begin(framebuffer, RenderingDevice.DRAW_CLEAR_COLOR_0, PackedColorArray([Color(0, 0, 0, 0)]))
	_rd.draw_list_bind_render_pipeline(list, _scatter_pipeline)
	_rd.draw_list_bind_uniform_set(list, set, 0)
	_rd.draw_list_set_push_constant(list, push.to_byte_array(), push.size() * 4)
	_rd.draw_list_draw(list, false, ceili(size.x / 2.0) * ceili(size.y / 2.0), 6)
	_rd.draw_list_end()

func _render_callback(callback: int, data: RenderData) -> void:
	if callback != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or not _initialize_gpu(): return
	var buffers := data.get_render_scene_buffers() as RenderSceneBuffersRD
	if not buffers: return
	_buffer_owners[buffers.get_instance_id()] = weakref(buffers)
	var size := buffers.get_internal_size()
	if size.x < 2 or size.y < 2: return
	var half := Vector2i(ceili(size.x / 2.0), ceili(size.y / 2.0))
	if buffers.has_texture(_context, &"color_coc_0"):
		var format := buffers.get_texture_format(_context, &"color_coc_0")
		if format.width != half.x or format.height != half.y: buffers.clear_context(_context)
	_mutex.lock()
	var camera := _camera
	_mutex.unlock()
	var push := PackedFloat32Array([size.x, size.y, half.x, half.y, camera.x, maxf(focus_band, 0.1),
		blur_pixels_1080 * size.y / 1080.0, maxf(highlight_threshold, 0.1), near_multiplier, far_multiplier,
		tilt_strength, tilt_center, tilt_width, tilt_feather, highlight_gain, 0.0, camera.y, camera.z, ceili(half.x / 2.0), 0.0])
	for view in buffers.get_view_count():
		var textures: Array[RID] = []
		for name in ["color_coc", "highlights", "gathered", "far_bokeh", "near_bokeh"]:
			textures.append(buffers.create_texture(_context, StringName("%s_%d" % [name, view]), RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
				RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT,
				RenderingDevice.TEXTURE_SAMPLES_1, half, 1, 1, false, false))
		var color := buffers.get_color_layer(view)
		var depth := buffers.get_depth_layer(view)
		_dispatch(0, [_uniform(0, color, false), _uniform(1, depth), _uniform(2, textures[0], false), _uniform(3, textures[1], false)], push, half)
		_dispatch(1, [_uniform(0, textures[0]), _uniform(1, textures[2], false)], push, half)
		var scatter_uniforms: Array[RDUniform] = [_uniform(0, textures[0]), _uniform(1, textures[1]), _uniform(2, textures[2])]
		push[15] = 0.0
		_scatter(textures[3], scatter_uniforms, push, half)
		push[15] = 1.0
		_scatter(textures[4], scatter_uniforms, push, half)
		_dispatch(3, [_uniform(0, color, false), _uniform(1, depth), _uniform(2, textures[0]), _uniform(3, textures[2]),
			_uniform(4, textures[3]), _uniform(5, textures[4])], push, size)
	_mutex.lock()
	_rendered_frames += 1
	_mutex.unlock()
