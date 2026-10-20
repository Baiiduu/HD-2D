class_name WavePresentation
extends CanvasLayer
## 只监听真实波次节点，不持有战斗时间、输入、相机或出怪权限。

const Settings = preload("res://scripts/world/wave_presentation_settings.gd")
const FONT = preload("res://assets/fonts/maoken_assorted_sans/MaokenAssortedSans.ttf")
const NUMBER_FONT = preload("res://assets/fonts/press_start_2p/PressStart2P-Regular.ttf")
const EDGE = preload("res://shaders/effects/wave_transition_edge.gdshader")
const PULSE = preload("res://shaders/effects/wave_transition_pulse.gdshader")
const SHOT = preload("res://scripts/camera/wave_finish_shot.gd")
const OPENING_TITLE = preload("res://scripts/ui/wave_opening_title.gd")
enum Cue { NONE, OPENING, NEXT_WAVE, CLEAR }

@export var session: WavePrototype
@export var wave_hud: WaveHUD
@export var settings: WavePresentationSettings
@export var enabled := true:
	set(value):
		enabled = value
		if not value: _stop()

var current_cue := Cue.NONE
var displayed_wave := 0
var age := 0.0
var cue_duration := 0.0
var subtitle_text := ""
var content_visible: bool:
	get: return is_instance_valid(_root) and _root.visible
var pulse: MeshInstance3D
var _root: Control
var _content: Control
var _clip: Control
var _frame: TextureRect
var _kicker: Label
var _title: Label
var _subtitle: Label
var _opening_title: OPENING_TITLE
var _edge: ColorRect
var _edge_material: ShaderMaterial
var _pulse_material: ShaderMaterial
var _started_wave := 0
var _cleared_wave := 0
var _owns_hud := false
var _hud_was_hidden := false
var shot := SHOT.new()
var _last_tick := 0

func _ready() -> void:
	layer = 24
	process_priority = 6 # 正常跟随／Q/E 和蓄力之后，水面反射之前。
	set_process(false)
	if not settings: settings = Settings.new()
	_build()
	get_viewport().size_changed.connect(_fit)
	if not is_instance_valid(session): return
	if is_instance_valid(wave_hud): wave_hud.wave_style = settings
	var score_hud := session.get_node_or_null("ScoreHUD") as ScoreHUD
	if score_hud: score_hud.wave_style = settings
	session.run_started.connect(_reset)
	session.phase_changed.connect(_phase_changed)
	session.wave_cleared.connect(_wave_cleared)
	session.combat_frozen_changed.connect(_frozen_changed)
	session.enemy_defeated.connect(_enemy_defeated)
	shot.bind(session, settings)

func prepare_feedback(closing := false) -> void:
	if not enabled: return
	_opening_title.configure(1,settings,closing)
	_prepare_pulse()
	if is_instance_valid(pulse): pulse.hide()
	_root.hide()

func _label(font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.025, 0.035, 0.055, 0.9))
	label.add_theme_constant_override("outline_size", 2)
	_content.add_child(label)
	return label

func _build() -> void:
	_root = Control.new()
	_root.name = "WaveFeedback"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_edge_material = ShaderMaterial.new()
	_edge_material.shader = EDGE
	_edge = ColorRect.new()
	_edge.material = _edge_material
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_edge)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_root.add_child(_content)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_clip)
	_frame = TextureRect.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_clip.add_child(_frame)
	_kicker = _label(NUMBER_FONT, 12, settings.battle_color)
	_title = _label(FONT, 36, settings.title_color)
	_subtitle = _label(FONT, 18, settings.title_color)
	_opening_title = OPENING_TITLE.new()
	_content.add_child(_opening_title)
	_opening_title.hide()
	_root.hide()
	_fit()

func _fit() -> void:
	if not _content: return
	var viewport := get_viewport().get_visible_rect().size
	var width := maxf(settings.banner_width, 1.0)
	var scale_factor := minf(1.0, minf((viewport.x - 32.0) / width, viewport.y / 720.0))
	_content.size = Vector2(width, 184)
	_content.scale = Vector2.ONE * maxf(scale_factor, 0.1)
	var top := settings.opening_title_top_ratio if _styled_title() else settings.top_ratio
	_content.position = Vector2((viewport.x - width * scale_factor) * 0.5, viewport.y * top)
	_opening_title.fit_width(width)
	_frame.size = Vector2(width, 108)
	_kicker.size = Vector2(width, 24)
	_title.position = Vector2(0, 43)
	_title.size = Vector2(width, 66)
	_subtitle.position = Vector2(0, 139)
	_subtitle.size = Vector2(width, 34)

func _eligible() -> bool:
	return enabled and is_instance_valid(session) and session.is_endless() and not session.is_horde_simulation()

func _reset() -> void:
	_stop()
	_started_wave = 0
	_cleared_wave = 0

func _phase_changed(phase: WavePrototype.Phase) -> void:
	if phase == WavePrototype.Phase.READY:
		_reset()
	elif phase == WavePrototype.Phase.RESULT or not _eligible():
		_stop()
	elif phase == WavePrototype.Phase.BATTLE and session.wave > _started_wave:
		_started_wave = session.wave
		_play(Cue.OPENING if session.wave == 1 else Cue.NEXT_WAVE, session.wave)

func _enemy_defeated(enemy: WaveEnemy) -> void:
	if not _eligible() or session.phase != WavePrototype.Phase.BATTLE or session._pending > 0 or not session.enemies.is_empty() or _suspended(): return
	_stop()
	shot.begin_finish(enemy)
	if shot.active:
		_last_tick = Time.get_ticks_usec()
		set_process(true)
		_render()

func _wave_cleared(number: int) -> void:
	if not _eligible() or session.phase != WavePrototype.Phase.REST or number != session.completed_waves or number <= _cleared_wave: return
	_cleared_wave = number
	_play(Cue.CLEAR, number)

func _play(cue: Cue, number: int) -> void:
	_stop()
	current_cue = cue
	displayed_wave = number
	age = 0.0
	var clear := cue == Cue.CLEAR
	cue_duration = settings.clear_seconds if clear else (settings.opening_seconds if cue == Cue.OPENING else settings.next_wave_seconds)
	_frame.texture = settings.clear_frame if clear else settings.battle_frame
	_kicker.text = "WAVE CLEAR" if clear else "ENDLESS / WAVE %02d" % number
	_title.text = "第 %d 波清除" % number if clear else ("无尽开战" if cue == Cue.OPENING else "第 %d 波" % number)
	subtitle_text = "休整 · 按 %s 继续第 %d 波" % [OS.get_keycode_string(session.interact_key), number + 1] if clear else ("第 1 波 · 迎击怪潮" if cue == Cue.OPENING else "再次迎战")
	_subtitle.text = subtitle_text
	var animated := _styled_title()
	_opening_title.visible = animated
	_clip.visible = not animated
	_kicker.visible = not animated
	_title.visible = not animated
	_subtitle.visible = not animated
	if animated: _opening_title.configure(number, settings, clear)
	_fit()
	_kicker.add_theme_color_override("font_color", settings.clear_color if clear else settings.battle_color)
	_edge_material.set_shader_parameter("edge_color", Color(0.045, 0.13, 0.11) if clear else Color(0.20, 0.06, 0.025))
	_prepare_pulse()
	_last_tick = Time.get_ticks_usec()
	set_process(true)
	_render()

func _animated_opening() -> bool:
	return settings.animated_opening_enabled and current_cue in [Cue.OPENING, Cue.NEXT_WAVE]

func _styled_title() -> bool:
	return _animated_opening() or (settings.compact_clear_enabled and current_cue == Cue.CLEAR)

func _prepare_pulse() -> void:
	if _styled_title(): return
	if not settings.ground_pulse_enabled or not settings.pulse_texture or not is_instance_valid(session.player): return
	if not is_instance_valid(pulse):
		pulse = MeshInstance3D.new()
		pulse.name = "WaveTransitionPulse"
		pulse.mesh = QuadMesh.new()
		pulse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pulse.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		pulse.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_pulse_material = ShaderMaterial.new()
		_pulse_material.shader = PULSE
		pulse.material_override = _pulse_material
		session.add_child(pulse)
	var texture := settings.pulse_texture
	var region := Vector4(0, 0, 1, 1)
	if texture is AtlasTexture:
		var rect := (texture as AtlasTexture).region
		texture = (texture as AtlasTexture).atlas
		var image_size := texture.get_size()
		region = Vector4(rect.position.x / image_size.x, rect.position.y / image_size.y, rect.size.x / image_size.x, rect.size.y / image_size.y)
	_pulse_material.set_shader_parameter("ring_texture", texture)
	_pulse_material.set_shader_parameter("texture_region", region)
	_pulse_material.set_shader_parameter("tint", Color.WHITE if current_cue != Cue.CLEAR else Color(0.82, 1.0, 0.90))
	pulse.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), session.player.global_position + Vector3.UP * 0.045)

func _suspended() -> bool:
	return session.combat_frozen or get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_delta := (now - _last_tick) / 1000000.0
	_last_tick = now
	advance(real_delta)

func advance(delta: float) -> void:
	if current_cue == Cue.NONE and not shot.active: return
	if not _eligible():
		_stop()
		return
	if shot.finishing and not settings.finish_shot_enabled: shot.stop()
	if _suspended():
		shot.stop()
		_render()
		if current_cue == Cue.NONE: set_process(false)
		return
	shot.advance(delta)
	if current_cue == Cue.NONE:
		_render()
		if not shot.active: set_process(false)
		return
	age += maxf(delta, 0.0)
	if age >= cue_duration:
		_stop()
		return
	_render()

func _frozen_changed(_value: bool) -> void:
	if _value: shot.stop()
	_render()

func _render() -> void:
	var showing := current_cue != Cue.NONE and not _suspended()
	_root.visible = showing
	if is_instance_valid(pulse): pulse.visible = showing and not _styled_title() and settings.ground_pulse_enabled and settings.pulse_texture != null
	if not showing and not shot.finishing:
		_release_hud()
		return
	if not _owns_hud and is_instance_valid(wave_hud):
		_hud_was_hidden = wave_hud.presentation_active
		_owns_hud = true
		wave_hud.presentation_active = true
	if not showing: return
	if _styled_title():
		_content.modulate.a = 1.0
		_edge_material.set_shader_parameter("amount", 0.0)
		_opening_title.render_at(age, cue_duration)
		return
	var progress := clampf(age / maxf(cue_duration, 0.001), 0.0, 1.0)
	var enter := 1.0 - pow(1.0 - clampf(progress / 0.23, 0.0, 1.0), 3.0)
	var alpha := smoothstep(0.0, 0.10, progress) * (1.0 - smoothstep(0.72, 1.0, progress))
	_content.modulate.a = alpha
	var width := settings.banner_width
	_clip.position = Vector2(width * (1.0 - enter) * 0.5, 30)
	_clip.size = Vector2(width * enter, 108)
	_frame.position = Vector2(-_clip.position.x, 0)
	_title.position.y = 43.0 + (1.0 - enter) * 10.0
	_edge_material.set_shader_parameter("amount", settings.edge_strength * alpha * (1.0 - progress))
	if is_instance_valid(pulse) and settings.ground_pulse_enabled and settings.pulse_texture:
		var clear := current_cue == Cue.CLEAR
		var end_radius := settings.clear_pulse_radius if clear else settings.battle_pulse_radius
		var radius := lerpf(0.65, end_radius, 1.0 - pow(1.0 - progress, 2.0))
		var aspect := settings.pulse_texture.get_width() / float(settings.pulse_texture.get_height())
		pulse.scale = Vector3(radius * 2.0 * aspect, radius * 2.0, 1.0)
		_pulse_material.set_shader_parameter("opacity", settings.pulse_opacity * alpha * (1.0 - progress))

func _release_hud() -> void:
	if _owns_hud and is_instance_valid(wave_hud): wave_hud.presentation_active = _hud_was_hidden
	_owns_hud = false

func _stop() -> void:
	shot.stop()
	current_cue = Cue.NONE
	set_process(false)
	if is_instance_valid(_root): _root.hide()
	if is_instance_valid(pulse): pulse.hide()
	_release_hud()

func _exit_tree() -> void:
	_stop()
	if is_instance_valid(wave_hud) and wave_hud.wave_style == settings: wave_hud.wave_style = null
	var score_hud := session.get_node_or_null("ScoreHUD") as ScoreHUD if is_instance_valid(session) else null
	if score_hud and score_hud.wave_style == settings: score_hud.wave_style = null
	if is_instance_valid(pulse): pulse.queue_free()
