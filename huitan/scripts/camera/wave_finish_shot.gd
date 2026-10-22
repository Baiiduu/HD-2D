class_name WaveFinishShot
extends RefCounted
## 只保留真实致死位置与死亡池中的可见快照；不保存将被释放的怪物。

var active := false
var finishing := false
var age := 0.0
var session: WavePrototype
var camera: FollowCamera
var settings: WavePresentationSettings
var _duration := 1.0
var _point := Vector3.ZERO
var _corpse: MeshInstance3D
var _player_sprite: Sprite3D
var _charge: ChargePresentation
var _post: ShaderMaterial
var _saved_scale := 1.0
var _owned_scale := -1.0
var _yielded_time := false
var _hud_colors: Dictionary[CanvasItem, Color] = {}
var _experience_root: Control

func bind(wave: WavePrototype, configuration: WavePresentationSettings) -> void:
	session = wave
	settings = configuration
	camera = wave.player.movement_camera as FollowCamera
	_charge = wave.get_parent().get_node_or_null("MapEffects/ChargePresentation") as ChargePresentation

func begin_finish(enemy: WaveEnemy) -> void:
	stop()
	if not settings.finish_shot_enabled or not is_instance_valid(camera) or not camera.is_processing(): return
	# 先归还击杀短顿的基准，再接管三秒特写，避免保存到临时的近零时间比例。
	session.get_tree().call_group(&"hit_impact_presentations", &"cancel_beat")
	var duration := clampf(settings.finish_shot_seconds, 0.6, 4.0)
	if not session.hold_wave_finish(duration + 0.1): return
	active = true
	finishing = true
	age = 0.0
	var point := enemy.global_position
	_point = point + Vector3.UP * camera.focus_height
	_duration = duration
	_player_sprite = session.player.sprite
	if is_instance_valid(session.loadout) and is_instance_valid(session.loadout._root):
		_hud_colors[session.loadout._root] = session.loadout._root.modulate
	var score_hud := session.get_node_or_null("ScoreHUD") as ScoreHUD
	if score_hud and is_instance_valid(score_hud._root): _hud_colors[score_hud._root] = score_hud._root.modulate
	var experience := session.get_node_or_null("RunGrowth/ExperienceHUD") as ExperienceHUD
	_experience_root = experience._root if experience else null
	if is_instance_valid(_experience_root): _hud_colors[_experience_root] = _experience_root.modulate
	# 只在真实最后一击扫描一次死亡池，之后直接跟随快照，不逐帧找怪。
	var pool := session._attack_root.get_node_or_null("EnemyFeedbackPool") as EnemyFeedbackPool if is_instance_valid(session._attack_root) else null
	if pool: _corpse = pool.death_subject_at(point)
	# 无普通死亡表现的远程收尾也使用原帧，避免镜头只拍到空地。
	if not is_instance_valid(_corpse) and is_instance_valid(session._attack_root):
		var sprite := enemy.get_node_or_null("Sprite") as Sprite3D
		if sprite and sprite.texture:
			if not pool:
				pool = EnemyFeedbackPool.new()
				pool.name = "EnemyFeedbackPool"
				session._attack_root.add_child(pool)
			var effect := pool.death(sprite, false, session.player.action_visuals, enemy.fatal_hit_context)
			_corpse = effect.get_focus_subject()
	if is_instance_valid(_charge): _charge.set_wave_finish_override(true)
	_saved_scale = Engine.time_scale
	_yielded_time = false
	camera.wave_shot_active = true
	_apply_finish()

func advance(real_delta: float) -> void:
	if not active: return
	age += maxf(0.0, real_delta)
	if age >= _duration:
		stop()
		return
	_apply_finish()

func _apply_finish() -> void:
	var t := age / _duration
	# 延长主体特写的保持段，推近仍短促，最后约 0.72 秒平滑归位。
	var enter := 1.0 - pow(1.0 - clampf(age / minf(0.22, _duration * 0.20), 0.0, 1.0), 3.0)
	var leave := 1.0 - smoothstep(maxf(_duration * 0.48, _duration - 0.72), _duration, age)
	var weight := enter * leave
	for hud in _hud_colors:
		# 经验条独立于 LoadoutUI 的 CanvasLayer；整段特写完全隐藏，保留成长和菜单的显示所有权。
		if is_instance_valid(hud): hud.modulate.a = 0.0 if hud == _experience_root else _hud_colors[hud].a * (1.0 - weight * 0.96)
	var player_point := session.player.get_global_transform_interpolated().origin + Vector3.UP * camera.focus_height
	# 快照结束后保留最后看到的位置，避免长特写归位时跳回原击杀点。
	if is_instance_valid(_corpse) and _corpse.visible: _point = _corpse.global_position
	var gap := _point - player_point
	# 远程收尾保留人物，不穿越整张地图去追一个已消失的远处目标。
	camera.wave_shot_focus = player_point + gap.limit_length(6.0) * 0.56
	camera.wave_shot_weight = weight
	var framing := clampf((gap.length() - 3.0) / 12.0, 0.0, 1.0)
	var zoom := lerpf(settings.finish_zoom_scale, 0.94, framing)
	camera.wave_shot_distance_scale = lerpf(1.0, zoom, weight)
	camera.wave_shot_roll = -3.5 * weight
	camera.wave_shot_yaw = lerpf(-3.0, 6.0, smoothstep(0.0, 0.65, t)) * weight
	camera._apply_transform()
	var slow := lerpf(clampf(settings.finish_slow_scale, 0.08, 1.0), 1.0, smoothstep(maxf(_duration * 0.38, _duration - 0.9), maxf(_duration * 0.76, _duration - 0.18), age))
	_write_time(slow)
	var impact := smoothstep(0.07, 0.16, age) * (1.0 - smoothstep(_duration * 0.45, _duration * 0.62, age)) * settings.finish_contrast
	if is_instance_valid(_player_sprite): _player_sprite.set_instance_shader_parameter("wave_finish_silhouette", impact)
	if is_instance_valid(_corpse): _corpse.set_instance_shader_parameter("wave_finish_silhouette", impact)
	var material := camera.post_process.material as ShaderMaterial if is_instance_valid(camera.post_process) else null
	if material != _post:
		_clear_post()
		_post = material
	if _post:
		_post.set_shader_parameter("wave_finish_amount", weight)
		_post.set_shader_parameter("wave_finish_impact", impact)
		var center := camera.unproject_position(camera.wave_shot_focus) / camera.get_viewport().get_visible_rect().size.max(Vector2.ONE)
		_post.set_shader_parameter("wave_finish_center", center)

func _write_time(ratio: float) -> void:
	if _owned_scale >= 0.0 and not is_equal_approx(Engine.time_scale, _owned_scale):
		_owned_scale = -1.0
		_yielded_time = true
	if _yielded_time: return
	_owned_scale = _saved_scale * ratio
	Engine.time_scale = _owned_scale

func _clear_post() -> void:
	if _post:
		_post.set_shader_parameter("wave_finish_amount", 0.0)
		_post.set_shader_parameter("wave_finish_impact", 0.0)
	_post = null

func stop() -> void:
	if not active: return
	if finishing:
		if is_instance_valid(session): session.hold_wave_finish(0.0)
		if _owned_scale >= 0.0 and is_equal_approx(Engine.time_scale, _owned_scale): Engine.time_scale = _saved_scale
		if is_instance_valid(_charge): _charge.set_wave_finish_override(false)
		if is_instance_valid(_player_sprite): _player_sprite.set_instance_shader_parameter("wave_finish_silhouette", 0.0)
		if is_instance_valid(_corpse): _corpse.set_instance_shader_parameter("wave_finish_silhouette", 0.0)
	_clear_post()
	for hud in _hud_colors:
		if is_instance_valid(hud): hud.modulate = _hud_colors[hud]
	_hud_colors.clear()
	_experience_root = null
	_corpse = null
	_player_sprite = null
	_owned_scale = -1.0
	active = false
	finishing = false
	if is_instance_valid(camera):
		camera.wave_shot_active = false
		camera.wave_shot_focus = Vector3.ZERO
		camera.wave_shot_weight = 0.0
		camera.wave_shot_distance_scale = 1.0
		camera.wave_shot_roll = 0.0
		camera.wave_shot_yaw = 0.0
		if camera.is_inside_tree() and is_instance_valid(camera.target): camera._apply_transform()
