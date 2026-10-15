class_name FanAutoAttack
extends Node3D

const EFFECT_LAYER := preload("res://scripts/rendering/combat_effect_layer.gd")

## A01：武器特效独立运行，人物不切换攻击动画。
signal strike_started(direction: Vector3)
signal hit_landed(enemy: WaveEnemy, damage: float)

const SLASH_SHADER := preload("res://shaders/combat/fan_slash.gdshader")
const ART_HALF_ANGLE := deg_to_rad(50.0)
const ART_RADIUS := 0.38
const ART_INNER_RADIUS := 0.20
const ANGLE_STEPS := 24
const RADIAL_STEPS := 4
const HIT_BAND := deg_to_rad(6.0)

@export_group("战斗连接")
@export var session: Node3D
@export var enabled := true
## 等级资源只影响本局攻击，不读取训练或旧技能学习存档。
@export var skill_definition: CombatSkillDefinition
@export_group("伤害、范围与间隔")
@export_range(0.0, 1000.0, 1.0) var damage := 10.0
## 从人物脚下到怪物中心的世界距离；特效同步缩放。
@export_range(0.5, 10.0, 0.1, "suffix:m") var attack_range := 2.4
## 两次起手间隔；短于起手加扫击时，按动作时长执行。
@export_range(0.15, 5.0, 0.05, "suffix:s") var attack_interval := 0.8
@export_range(10.0, 180.0, 5.0, "suffix:°") var fan_angle := 100.0
@export_group("出手与命中")
@export_range(0.0, 0.5, 0.01, "suffix:s") var windup_time := 0.1
@export_range(0.05, 0.8, 0.01, "suffix:s") var sweep_time := 0.18
@export_range(0.0, 0.5, 0.01, "suffix:s") var fade_time := 0.12
## 地面高度差限制；跳跃仍使用人物脚下的实际地表。
@export_range(0.1, 1.0, 0.05, "suffix:m") var height_tolerance := 0.55
@export_range(0.0, 1.0, 0.05, "suffix:m") var knockback_distance := 0.25
@export_group("斩击外观")
@export var frames: SpriteFrames
@export var effect_color := Color.WHITE
@export_range(0.0, 1.0, 0.05) var effect_opacity := 0.85
@export_range(0.0, 3.0, 0.05) var effect_energy := 0.6
## 离地高度，避免与草地重叠闪烁。
@export_range(0.01, 0.4, 0.01, "suffix:m") var effect_height := 0.16
@export_group("攻击音效")
@export var audio_enabled := true:
	set(value):
		audio_enabled = value
		if not value: _stop_audio()
## 斩光出现时播放，每次选择不同的短音源。
@export var sweep_sounds: Array[AudioStream] = []
## 只在真正造成伤害时播放；群体命中受下方间隔和次数限制。
@export var hit_sounds: Array[AudioStream] = []
@export_range(-40.0, 6.0, 0.5) var audio_volume_db := -10.0
## 命中声相对于攻击音效总音量的增益。
@export_range(-24.0, 6.0, 0.5) var hit_volume_db := -6.0
## 留空时使用地图公共声音管理器，所有武器共用预算与混音。
@export var audio_manager: GameAudio
@export_range(0.5, 2.0, 0.01) var audio_pitch := 1.0
@export_range(0.0, 0.15, 0.005) var audio_pitch_variation := 0.035
## 同一击最多播放几次命中声；不影响命中数量或伤害。
@export_range(0, 4, 1) var hit_sound_limit := 2
@export_range(0.0, 0.3, 0.005, "suffix:s") var hit_sound_interval := 0.055
## 连续旋转的声音脉冲间隔；双刃共用，不按帧或刃数叠加。
@export_range(0.2, 2.0, 0.05, "suffix:s") var rotation_sound_interval := 0.55

var direction := Vector3.FORWARD
var _player: Player
var _cooldown := 0.0
var _elapsed := 0.0
var _swinging := false
var _fading := false
var _hits: Dictionary = {}
var _locked_basis := Basis.IDENTITY
var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _sweep_audible := false
var _hit_audio_count := 0
var _hit_audio_clock := 0.0
var _spin_audio_clock := 0.0
var skill_level := 1
var _combo_index := 0
var _aim_basis := Basis.IDENTITY
var _spinning := false
var _spin_time := 0.0
var _spin_hits: Dictionary[int, float] = {}
var _extra_meshes: Array[MeshInstance3D] = []
var _strike_modifiers: RunCombatModifiers
var _mesh_indices := PackedInt32Array()
var _flat_mesh: ArrayMesh
var _flat_mesh_key := Vector3(-1, -1, -1)
var _surface_query: RefCounted

func get_skill_definition() -> CombatSkillDefinition:
	return skill_definition

func apply_skill_level(level: int) -> bool:
	if not skill_definition or (level != 0 and not skill_definition.level_data(level)): return false
	cancel_current()
	var was_unlearned := skill_level == 0
	skill_level = level
	if level == 0 or was_unlearned: set_physics_process(level > 0)
	return true

func get_attack_stats(level := -1, modifiers: RunCombatModifiers = null) -> Dictionary:
	if level < 0: level = skill_level
	var data := skill_definition.level_data(level) if skill_definition else null
	var values: Dictionary = data.parameters if data else {}
	var stats := {"damage": damage * values.get("damage_multiplier", 1.0),
		"range": attack_range * values.get("range_multiplier", 1.0),
		"angle": clampf(fan_angle * values.get("angle_multiplier", 1.0), 10.0, 180.0),
		"interval": attack_interval * values.get("interval_multiplier", 1.0),
		"energy": effect_energy * values.get("energy_multiplier", 1.0),
		"sweeps": clampi(int(values.get("sweep_count", 1.0)), 1, 8),
		"gap": maxf(values.get("repeat_gap", 0.0), 0.0), "turn": values.get("combo_turn", 0.0),
		"rotation": values.get("continuous_rotation", 0.0) > 0.0,
		"rotation_speed": maxf(values.get("rotation_speed", 210.0), 0.0),
		"hit_interval": maxf(values.get("hit_interval", 0.4), 0.05),
		"blades": clampi(int(values.get("spin_blades", 1.0)), 1, 4)}
	if not modifiers and session:
		modifiers = _strike_modifiers if _strike_modifiers and (_swinging or _fading) else session.combat_modifiers
	if modifiers:
		stats.damage *= modifiers.damage_multiplier()
		stats.range *= modifiers.range_multiplier()
		stats.interval *= modifiers.interval_multiplier()
		# 旋转攻击只缩短同体命中间隔，不重复加速旋转。
		stats.hit_interval *= modifiers.interval_multiplier()
	return stats

## 成长卡读取真实收益；后续武器只回传自己支持的属性键。
func get_combat_stats(modifiers: RunCombatModifiers = null) -> Dictionary:
	if not enabled or skill_level <= 0: return {}
	if not modifiers and session: modifiers = session.combat_modifiers
	var stats := get_attack_stats(skill_level, modifiers)
	var shortest: float = windup_time + stats.sweeps * (sweep_time + fade_time) + (stats.sweeps - 1) * stats.gap
	return {"name": "扇击", "damage": stats.damage, "range": stats.range,
		"interval": stats.hit_interval if stats.rotation else maxf(stats.interval, shortest)}

func describe_skill_upgrade(from_level: int, to_level: int) -> String:
	var modifiers: RunCombatModifiers = session.combat_modifiers if session else null
	var before := get_attack_stats(from_level, modifiers)
	var after := get_attack_stats(to_level, modifiers)
	if from_level == 0:
		return "自动攻击近处敌人\n伤害 %s\n范围 %.1f 米\n%s" % [str(snappedf(after.damage, 0.1)), after.range, skill_definition.level_data(to_level).description]
	var lines := PackedStringArray([
		"伤害 %s → %s" % [str(snappedf(before.damage, 0.1)), str(snappedf(after.damage, 0.1))],
		"范围 %.1f → %.1f 米" % [before.range, after.range]])
	if after.rotation:
		lines.append("转速 %d°/秒" % after.rotation_speed)
		lines.append("同体间隔 %.2f 秒" % after.hit_interval)
		lines.append("%s持续旋转" % ("双刃" if after.blades == 2 else "%d刃" % after.blades))
	else:
		if not is_equal_approx(before.angle, after.angle): lines.append("扇角 %d → %d°" % [before.angle, after.angle])
		if before.sweeps != after.sweeps: lines.append("扫击 %d → %d 段" % [before.sweeps, after.sweeps])
		lines.append(skill_definition.level_data(to_level).description)
	return "\n".join(lines)

func _ready() -> void:
	for angular in ANGLE_STEPS:
		for radial in RADIAL_STEPS:
			var a := angular * (RADIAL_STEPS + 1) + radial
			var b := a + RADIAL_STEPS + 1
			_mesh_indices.append_array(PackedInt32Array([a, b, b + 1, a, b + 1, a + 1]))
	_mesh = MeshInstance3D.new()
	_mesh.name = "SlashEffect"
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = EFFECT_LAYER.material(SLASH_SHADER)
	_mesh.material_override = _material
	_mesh.visible = false
	add_child(_mesh)
	if not audio_manager: audio_manager = get_tree().get_first_node_in_group(&"game_audio") as GameAudio
	if session:
		session.register_combat_node(self)
		_player = session.player
		_surface_query = session.get_attack_surface_query()
		session.phase_changed.connect(_on_phase_changed)
		_player.blink_travelled.connect(_on_blink)

func _on_phase_changed(_phase: int) -> void:
	cancel_current()
	_cooldown = 0.0
	# 正常清波保留已命中的短尾音，重试、撤退和结束清理旧声音。
	if _phase != WavePrototype.Phase.REST: _stop_audio()

func _on_blink(_start: Vector3, _destination: Vector3) -> void:
	# 只同步落点与地表裁切，不重启攻击、清除命中记录或扫过瞬移路径。
	if not (_swinging or _fading or _spinning): return
	var origin := _origin()
	global_position = origin
	if _spinning:
		var stats := get_attack_stats()
		var flat_surface := _unclipped_flat_surface(origin, stats.range)
		var effects: Array[MeshInstance3D] = [_mesh]
		effects.append_array(_extra_meshes)
		for effect in effects:
			if effect.visible: _update_mesh(origin, effect, effect.global_basis, stats, flat_surface)
	else:
		_update_mesh(origin)
	reset_physics_interpolation()

func cancel_current() -> void:
	_swinging = false
	_fading = false
	_hits.clear()
	_sweep_audible = false
	_spinning = false
	_spin_audio_clock = 0.0
	_spin_time = 0.0
	_spin_hits.clear()
	_strike_modifiers = null
	if _mesh:
		_mesh.visible = false
		_mesh.transform = Transform3D.IDENTITY
	for effect in _extra_meshes: effect.visible = false

func _active() -> bool:
	return enabled and skill_level > 0 and session and session.combat_active() and session._path_ready and is_instance_valid(_player)

func _origin() -> Vector3:
	return session._path.ground_position(_player.global_position)

func _physics_process(delta: float) -> void:
	if not _active():
		if _swinging or _fading or _spinning: cancel_current()
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_hit_audio_clock = maxf(_hit_audio_clock - delta, 0.0)
	if get_attack_stats().rotation:
		if _cooldown <= 0.0: _advance_spin(delta)
		return
	if _swinging or _fading: _advance_swing(delta)
	if not _swinging and _cooldown <= 0.0: start_swing()

func nearest_target() -> WaveEnemy:
	if not _active(): return null
	var origin := _origin()
	var nearest: WaveEnemy
	var stats := get_attack_stats()
	var distance: float = stats.range
	for enemy: WaveEnemy in session.enemies:
		if not is_instance_valid(enemy) or enemy.dead or enemy.spawn_delay > 0.0: continue
		var gap := TerrainPath.horizontal_distance(origin, enemy.global_position)
		if gap > distance or not _can_reach(enemy, origin, stats): continue
		nearest = enemy
		distance = gap
	return nearest

func start_swing() -> bool:
	if _swinging or _cooldown > 0.0: return false
	var target := nearest_target()
	if not target: return false
	direction = target.global_position - _origin()
	direction.y = 0.0
	if direction.length_squared() < 0.0001: direction = Vector3.FORWARD
	direction = direction.normalized()
	_locked_basis = Basis(Vector3.UP, atan2(-direction.x, -direction.z))
	_aim_basis = _locked_basis
	_combo_index = 0
	# 固定本次扫击的增益；成长选择后，下一次起手应用新值。
	_strike_modifiers = session.combat_modifiers.preview_after(null)
	var stats := get_attack_stats()
	_cooldown = maxf(stats.interval, windup_time + stats.sweeps * (sweep_time + fade_time) + (stats.sweeps - 1) * stats.gap)
	_elapsed = 0.0
	_swinging = true
	_fading = false
	_hits.clear()
	_sweep_audible = false
	_hit_audio_count = 0
	_hit_audio_clock = 0.0
	_mesh.visible = false
	strike_started.emit(direction)
	return true

func _can_reach(enemy: WaveEnemy, origin: Vector3, stats: Dictionary = {}) -> bool:
	if not is_instance_valid(enemy) or enemy.dead or enemy.spawn_delay > 0.0: return false
	if stats.is_empty(): stats = get_attack_stats()
	if TerrainPath.horizontal_distance(origin, enemy.global_position) > stats.range: return false
	if absf(origin.y - enemy.global_position.y) > height_tolerance: return false
	if not _line_clear(origin, enemy.global_position): return false
	var navigation: TerrainPath = session._path
	return not navigation.route(origin, navigation.ground_position(enemy.global_position)).is_empty()

func _line_clear(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.45, to + Vector3.UP * 0.45, 1, [_player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _advance_swing(delta: float) -> void:
	var previous := clampf((_elapsed - windup_time) / maxf(sweep_time, 0.01), 0.0, 1.0)
	_elapsed += delta
	if _elapsed < windup_time: return
	var progress := clampf((_elapsed - windup_time) / maxf(sweep_time, 0.01), 0.0, 1.0)
	if _swinging:
		if not _sweep_audible:
			_sweep_audible = true
			_play_audio(sweep_sounds, 0.0, _origin(), GameAudio.Kind.ATTACK)
		var origin := _origin()
		global_position = origin
		global_basis = _locked_basis
		_apply_hits(origin, previous, progress)
		# 击杀回调可能进入成长选择或结束挑战，不能继续扣血或复活特效。
		if not _swinging or not _active(): return
		_update_mesh(origin)
		if progress >= 1.0:
			_swinging = false
			_fading = true
	var opacity := 1.0
	if _fading:
		opacity = 1.0 - (_elapsed - windup_time - sweep_time) / maxf(fade_time, 0.001)
		if opacity <= 0.0:
			var stats := get_attack_stats()
			if _combo_index + 1 < stats.sweeps:
				_mesh.visible = false
				var next_time: float = windup_time + sweep_time + fade_time + stats.gap
				if _elapsed < next_time: return
				_elapsed = windup_time + _elapsed - next_time
				_combo_index += 1
				_locked_basis = _aim_basis * Basis(Vector3.UP, deg_to_rad(stats.turn * (1.0 if _combo_index % 2 else -1.0)))
				_hits.clear()
				_sweep_audible = false
				_hit_audio_count = 0
				_hit_audio_clock = 0.0
				_swinging = true
				_fading = false
				strike_started.emit(_locked_basis * Vector3.FORWARD)
				_advance_swing(0.0)
				return
			cancel_current()
			return
	_update_texture(progress, opacity)

func _apply_hits(origin: Vector3, previous: float, progress: float) -> void:
	var stats := get_attack_stats()
	var half := deg_to_rad(stats.angle * 0.5)
	var first := lerpf(-half, half, previous) - HIT_BAND
	var last := lerpf(-half, half, progress) + HIT_BAND
	# 死亡会从控制器数组移除敌人，遍历本帧快照。
	for enemy: WaveEnemy in session.enemies.duplicate():
		if not _active() or not _swinging: return
		if not is_instance_valid(enemy) or enemy.dead or enemy.spawn_delay > 0.0: continue
		if _hits.has(enemy.get_instance_id()): continue
		var offset := _locked_basis.inverse() * (enemy.global_position - origin)
		var angle := atan2(offset.x, -offset.z)
		if absf(angle) > half or angle < first or angle > last: continue
		if not _can_reach(enemy, origin, stats): continue
		_hits[enemy.get_instance_id()] = true
		var before := enemy.health
		enemy.take_damage(maxf(stats.damage, 0.0), {"source": &"A01", "direction": enemy.global_position - origin})
		var dealt := before - enemy.health
		if dealt <= 0.0 and not session.combat_modifiers.damage_disabled: continue
		_play_hit_audio(enemy.global_position)
		if not enemy.dead:
			var push := enemy.global_position - origin
			push.y = 0.0
			enemy.apply_knockback(push.normalized(), knockback_distance)
		hit_landed.emit(enemy, dealt)

func _play_hit_audio(position: Vector3) -> void:
	if _hit_audio_count >= hit_sound_limit or _hit_audio_clock > 0.0: return
	if not _play_audio(hit_sounds, hit_volume_db, position, GameAudio.Kind.HIT): return
	_hit_audio_count += 1
	_hit_audio_clock = hit_sound_interval

func _play_audio(clips: Array[AudioStream], gain_db: float, position: Vector3, kind: GameAudio.Kind) -> bool:
	if not audio_enabled or clips.is_empty(): return false
	if not is_instance_valid(audio_manager): audio_manager = get_tree().get_first_node_in_group(&"game_audio") as GameAudio
	if not audio_manager: return false
	return audio_manager.request({"source": self, "cue": &"fan_hit" if kind == GameAudio.Kind.HIT else &"fan_sweep",
		"clips": clips, "kind": kind, "position": position, "volume_db": audio_volume_db + gain_db,
		"follow_source": kind == GameAudio.Kind.ATTACK,
		"pitch": audio_pitch * randf_range(1.0 - audio_pitch_variation, 1.0 + audio_pitch_variation)}) != null

func _stop_audio() -> void:
	if is_instance_valid(audio_manager): audio_manager.stop_source(self)

## 连续旋转仍逐个检查传播路径，双刃共享同体命中间隔。
func _advance_spin(delta: float) -> void:
	var stats := get_attack_stats()
	_spinning = true
	_spin_time += delta
	_spin_audio_clock = maxf(_spin_audio_clock - delta, 0.0)
	if _spin_audio_clock <= 0.0:
		_spin_audio_clock = maxf(rotation_sound_interval, 0.2)
		_hit_audio_count = 0
		if nearest_target(): _play_audio(sweep_sounds, -3.0, _origin(), GameAudio.Kind.ATTACK)
	var origin := _origin()
	global_position = origin
	global_basis = Basis.IDENTITY
	while _extra_meshes.size() < stats.blades - 1:
		var effect := MeshInstance3D.new()
		effect.name = "SpinSlash%d" % (_extra_meshes.size() + 1)
		effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		effect.material_override = EFFECT_LAYER.duplicate_material(_material)
		add_child(effect)
		_extra_meshes.append(effect)
	var effects: Array[MeshInstance3D] = [_mesh]
	effects.append_array(_extra_meshes)
	var travelled := deg_to_rad(stats.rotation_speed * delta)
	var flat_surface := _unclipped_flat_surface(origin, stats.range)
	for index in effects.size():
		var effect := effects[index]
		if index >= stats.blades:
			effect.visible = false
			continue
		var basis := Basis(Vector3.UP, deg_to_rad(stats.rotation_speed * _spin_time) + TAU * index / stats.blades)
		effect.global_position = origin
		effect.global_basis = basis
		_apply_spin_hits(origin, basis, travelled, stats)
		if not _active() or not _spinning: return
		_update_mesh(origin, effect, basis, stats, flat_surface)
		# 保留后段斩光并循环末三帧，旋转交接时不会出现空白帧。
		var progress := lerpf(0.625, 0.999, fposmod(_spin_time / maxf(sweep_time, 0.01) + float(index) / stats.blades, 1.0))
		_update_texture(progress, 1.0, effect, effect.material_override as ShaderMaterial, true)

func _apply_spin_hits(origin: Vector3, basis: Basis, travelled: float, stats: Dictionary) -> void:
	var half := deg_to_rad(stats.angle * 0.5)
	for enemy: WaveEnemy in session.enemies.duplicate():
		if not _active() or not _spinning: return
		if not is_instance_valid(enemy) or enemy.dead or enemy.spawn_delay > 0.0: continue
		var id := enemy.get_instance_id()
		if _spin_time + 0.00001 < _spin_hits.get(id, 0.0): continue
		var offset := basis.inverse() * (enemy.global_position - origin)
		var angle := atan2(offset.x, -offset.z)
		if absf(angle) > half + minf(travelled, PI): continue
		if not _can_reach(enemy, origin, stats): continue
		_spin_hits[id] = _spin_time + stats.hit_interval
		var before := enemy.health
		enemy.take_damage(maxf(stats.damage, 0.0), {"source": &"A01", "direction": enemy.global_position - origin})
		var dealt := before - enemy.health
		if dealt <= 0.0 and not session.combat_modifiers.damage_disabled: continue
		_play_hit_audio(enemy.global_position)
		if not enemy.dead:
			var push := enemy.global_position - origin
			push.y = 0.0
			enemy.apply_knockback(push.normalized(), knockback_distance)
		hit_landed.emit(enemy, dealt)

func _update_texture(progress: float, opacity: float, effect: MeshInstance3D = null, material: ShaderMaterial = null, full_arc := false) -> void:
	if not effect: effect = _mesh
	if not material: material = _material
	if not frames or not frames.has_animation(&"slash") or frames.get_frame_count(&"slash") == 0: return
	var count := frames.get_frame_count(&"slash")
	var index := mini(floori(progress * count), count - 1)
	var texture := frames.get_frame_texture(&"slash", index)
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		var size: Vector2 = atlas.atlas.get_size()
		EFFECT_LAYER.set_parameter(material, "slash_texture", atlas.atlas)
		EFFECT_LAYER.set_parameter(material, "frame_rect", Vector4(atlas.region.position.x / size.x, atlas.region.position.y / size.y, atlas.region.size.x / size.x, atlas.region.size.y / size.y))
	else:
		EFFECT_LAYER.set_parameter(material, "slash_texture", texture)
		EFFECT_LAYER.set_parameter(material, "frame_rect", Vector4(0, 0, 1, 1))
	EFFECT_LAYER.set_parameter(material, "tint", effect_color)
	EFFECT_LAYER.set_parameter(material, "opacity", opacity * effect_opacity)
	EFFECT_LAYER.set_parameter(material, "energy", get_attack_stats().energy)
	EFFECT_LAYER.set_parameter(material, "leading_angle", (ART_HALF_ANGLE if full_arc else lerpf(-ART_HALF_ANGLE, ART_HALF_ANGLE, progress)) + HIT_BAND)
	effect.visible = true

## 沿角度裁切墙体、断层和水面，网格逐环贴合坡面。
func _surface_limit(origin: Vector3, angle: float, range_limit := -1.0, flat_ground := false) -> float:
	var navigation: TerrainPath = session._path
	var terrain: Terrain = session.terrain
	var heading := _locked_basis * Vector3(sin(angle), 0.0, -cos(angle))
	var limit: float = maxf(range_limit if range_limit >= 0.0 else get_attack_stats().range, 0.01)
	var steps := maxi(1, ceili(limit / 0.25))
	for step in range(1, 1 if flat_ground else steps + 1):
		var distance := limit * float(step) / steps
		var point := navigation.ground_position(origin + heading * distance)
		var cell := terrain.data.world_to_cell(terrain.to_local(point))
		if not terrain.data.has_cell(cell) or absf(point.y - origin.y) > height_tolerance or (terrain.data.has_overlay(cell, TerrainData.OVERLAY_WATER) and not terrain.data.has_overlay(cell, TerrainData.OVERLAY_BRIDGE)):
			limit = limit * float(step - 1) / steps
			break
	var end := origin + heading * limit if flat_ground else navigation.ground_position(origin + heading * limit)
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.45, end + Vector3.UP * 0.45, 1, [_player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): limit = minf(limit, maxf(0.0, TerrainPath.horizontal_distance(origin, hit.position) - 0.05))
	return limit

## 只有整个覆盖圆盘都是同高平面且无挡墙时，才复用平面网格。
## 每帧重新检查地形与碰撞，移动、改地形或出现动态挡墙立即回到精确裁切。
func _unclipped_flat_surface(origin: Vector3, radius: float) -> bool:
	return _surface_query.unclipped_flat(origin, radius)

func _update_mesh(origin: Vector3, effect: MeshInstance3D = null, basis := Basis.IDENTITY, stats: Dictionary = {}, flat_surface := false) -> void:
	if not effect:
		effect = _mesh
		basis = _locked_basis
	if stats.is_empty():
		stats = get_attack_stats()
		flat_surface = _unclipped_flat_surface(origin, stats.range)
	var key := Vector3(stats.range, stats.angle, effect_height)
	if flat_surface and _flat_mesh and key == _flat_mesh_key:
		if effect.mesh != _flat_mesh: effect.mesh = _flat_mesh
		return
	var reusable := effect.get_meta(&"clipped_mesh") as ArrayMesh if not flat_surface and effect.has_meta(&"clipped_mesh") else null
	var mesh := _build_effect_mesh(origin, basis, stats, flat_surface, reusable)
	if flat_surface:
		_flat_mesh = mesh
		_flat_mesh_key = key
	elif mesh != reusable:
		effect.set_meta(&"clipped_mesh", mesh)
	if effect.mesh != mesh: effect.mesh = mesh

func _build_effect_mesh(origin: Vector3, basis: Basis, stats: Dictionary, flat_surface: bool, mesh: ArrayMesh = null) -> ArrayMesh:
	var navigation: TerrainPath = session._path
	var flat_ground: bool = flat_surface or _surface_query.flat_ground(origin, stats.range)
	var half := deg_to_rad(stats.angle * 0.5)
	var previous_basis := _locked_basis
	_locked_basis = basis
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var limits := PackedFloat32Array()
	for index in ANGLE_STEPS + 1:
		limits.append(stats.range if flat_surface else _surface_limit(origin, lerpf(-half, half, float(index) / ANGLE_STEPS), stats.range, flat_ground))
	_locked_basis = previous_basis
	# 相邻三角形共享 25×5 个顶点；地形采样从每刃 576 次减少至 125 次。
	for index in ANGLE_STEPS + 1:
		var angular := float(index) / ANGLE_STEPS
		var angle := lerpf(-half, half, angular)
		var heading := Vector3(sin(angle), 0.0, -cos(angle))
		var art_angle := lerpf(-ART_HALF_ANGLE, ART_HALF_ANGLE, angular)
		var art_heading := Vector2(sin(art_angle), -cos(art_angle))
		for ring in RADIAL_STEPS + 1:
			var radius := limits[index] * float(ring) / RADIAL_STEPS
			var local := heading * radius
			local.y = effect_height if flat_ground else navigation.ground_position(origin + basis * local).y - origin.y + effect_height
			vertices.append(local)
			# 展开原斩光的径向拖尾，既看得清外缘，也能表现近身命中。
			var art_radius := lerpf(ART_INNER_RADIUS, ART_RADIUS, radius / maxf(stats.range, 0.01))
			uvs.append(Vector2(0.5, 0.5) + art_heading * art_radius)
	if mesh and DisplayServer.get_name() != "headless":
		# 顶点与 UV 每帧精确更新，索引和 GPU 缓冲保持；每刃独立，不写共享平地网格。
		mesh.surface_update_vertex_region(0, 0, vertices.to_byte_array())
		mesh.surface_update_attribute_region(0, 0, uvs.to_byte_array())
		var bounds := AABB(vertices[0], Vector3.ZERO)
		for vertex in vertices: bounds = bounds.expand(vertex)
		mesh.custom_aabb = bounds
	else:
		# Dummy 渲染器不实现缓冲更新；无渲染验证保留可读取的精确数组。
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = _mesh_indices
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	return mesh
