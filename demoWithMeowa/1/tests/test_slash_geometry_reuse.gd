extends "res://tests/test_player_sword.gd"
## 比较实时裁切后的原始几何和参数，不启动渲染窗口。
const LEGACY := preload("res://tests/fixtures/legacy_ground_slash.gd")

func draw(effect: MeshInstance3D, rules: PlayerSwordRules, origin: Vector3, heading: Vector3, radius: float, angle: float, reverse: bool, age: float) -> void:
	var excluded: Array[RID] = [player.get_rid()]
	effect.display(origin,heading,radius,angle,reverse,rules.frames,age,rules,session._path,sword._surface,excluded)

func compare(current: MeshInstance3D, old: MeshInstance3D) -> void:
	var a := current.mesh.surface_get_arrays(0)
	var b := old.mesh.surface_get_arrays(0)
	var columns: int = b[Mesh.ARRAY_VERTEX].size() / 5
	var stride: int = a[Mesh.ARRAY_VERTEX].size() / columns
	var first_ring := 5 - stride
	for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_TEX_UV]:
		var matching := stride > 0 and stride <= 5
		for index in a[channel].size():
			var original_index: int = (index / stride) * 5 + first_ring + index % stride
			if a[channel][index] != b[channel][original_index]: matching = false
		check(matching, "保留的顶点与 UV 逐项等于原始采样，只有透明中心的无引用顶点省略")
	var kept: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	kept = kept.duplicate()
	for index in kept.size(): kept[index] = (kept[index] / stride) * 5 + first_ring + kept[index] % stride
	var original: PackedInt32Array = b[Mesh.ARRAY_INDEX]
	var material: ShaderMaterial = current.material_override
	if kept == original:
		check(true, "非环绕模式保留原有完整三角形")
	else:
		check(material.shader.resource_path.ends_with("player_sword_orbit.gdshader"), "仅环绕材质剔除已知透明中心")
		var cursor := 0
		var safe := true
		var uvs: PackedVector2Array = b[Mesh.ARRAY_TEX_UV]
		var inner: float = material.get_shader_parameter("inner_ratio")
		for triangle in range(0, original.size(), 3):
			if cursor < kept.size() and kept[cursor] == original[triangle] and kept[cursor + 1] == original[triangle + 1] and kept[cursor + 2] == original[triangle + 2]:
				cursor += 3
				continue
			for vertex in 3:
				if ((uvs[original[triangle + vertex]] - Vector2.ONE * 0.5) * 2.0).length() >= inner: safe = false
		check(safe and cursor == kept.size(), "只移除整面位于零透明度区的三角形，可见三角形与顺序保持原样")
	check(current.global_transform == old.global_transform,"复用网格不冻结世界位置或朝向")
	var reference: ShaderMaterial = old.material_override
	for uniform in material.shader.get_shader_uniform_list():
		var key: StringName = uniform.name
		check(material.get_shader_parameter(key) == reference.get_shader_parameter(key),"动画与材质参数保留原值："+key)

func manual_checks() -> void:
	await reset()
	var current := GroundSlashEffect.new()
	var old := LEGACY.new()
	world.add_child(current)
	world.add_child(old)
	var rules := load("res://data/combat/scenes/world/player/basic_sword.tres").duplicate() as PlayerSwordRules
	rules.ribbon_visual = rules.flight_ribbon_visual.duplicate()
	var wall := box(Vector3(0.65,0.6,0),Vector3(0.04,1.2,5.0))
	await settle()
	for reverse in [false,true]:
		for angle in [120.0,360.0]:
			draw(current,rules,Vector3.ZERO,Vector3.RIGHT,1.52,angle,reverse,0.1)
			draw(old,rules,Vector3.ZERO,Vector3.RIGHT,1.52,angle,reverse,0.1)
			compare(current,old)
			var mesh := current.mesh
			draw(current,rules,Vector3.ZERO,Vector3.RIGHT,1.52,angle,reverse,0.12)
			draw(old,rules,Vector3.ZERO,Vector3.RIGHT,1.52,angle,reverse,0.12)
			check(current.mesh == mesh,"仍然实时查询墙体，但裁切结果相同的余迹复用已有网格")
			compare(current,old)
	for position in [Vector3(0.45,0.6,0),Vector3(0.8,0.6,0),Vector3(20,0.6,0),Vector3(-0.7,0.6,0)]:
		wall.position = position
		await settle()
		for heading in [Vector3.RIGHT,Vector3.FORWARD,Vector3(0.4,0,-1).normalized()]:
			for effect in [current,old]: draw(effect,rules,Vector3(0.1,0,0.05),heading,1.4,360,false,0.18)
			compare(current,old)
	terrain.data.set_overlay(Vector2i.RIGHT,TerrainData.OVERLAY_WATER,true)
	await settle()
	for effect in [current,old]: draw(effect,rules,Vector3.ZERO,Vector3.RIGHT,1.4,360,false,0.2)
	compare(current,old)
	terrain.data.set_overlay(Vector2i.RIGHT,TerrainData.OVERLAY_WATER,false)
	await settle()
	for mode in [PlayerSwordRules.SlashVisual.FRAME_ANIMATION,PlayerSwordRules.SlashVisual.THIN_ARC,PlayerSwordRules.SlashVisual.MEOWA_ARC,PlayerSwordRules.SlashVisual.NATIVE_RIBBON]:
		rules.effect_mode = mode
		rules.ribbon_visual = load("res://data/visual/sword_slash_world.tres").duplicate()
		for step in 3:
			if step == 1: rules.ribbon_visual.ribbon_flow_speed += 0.00000001
			if step == 2: rules.effect_opacity *= 0.7
			for effect in [current,old]: draw(effect,rules,Vector3.ZERO,Vector3.RIGHT,1.52,120,step==2,0.04+step*0.02)
			compare(current,old)
	await edge_checks(current, old, rules, wall)
	await avoidable_work_checks(current, old, rules, wall)
	wall.queue_free()
	current.queue_free()
	old.queue_free()
	await settle()

func edge_checks(current: GroundSlashEffect, old: MeshInstance3D, rules: PlayerSwordRules, wall: StaticBody3D) -> void:
	rules.effect_mode = PlayerSwordRules.SlashVisual.NATIVE_RIBBON
	rules.ribbon_visual = rules.flight_ribbon_visual.duplicate()
	wall.get_child(0).shape.size = Vector3(0.1, 1.2, 8.0)
	for side in [-1.0, 1.0]:
		var edge := (terrain.data.origin.x + terrain.data.size.x - 0.5 if side > 0.0 else terrain.data.origin.x - 0.5) * terrain.data.cell_size
		var origin := Vector3(edge - side * 0.9, 0, 0)
		wall.position = Vector3(origin.x + side * 0.6, 0.6, 0)
		await settle()
		check(not sword._surface.flat_ground(origin, 1.52), "地图边缘的宽平地资格确实失败，覆盖原慢路径")
		for reverse in [false, true]:
			for effect in [current, old]: draw(effect, rules, origin, Vector3.RIGHT, 1.52, 360, reverse, 0.18)
			compare(current, old)
			var mesh := current.mesh
			for effect in [current, old]: draw(effect, rules, origin, Vector3.RIGHT, 1.52, 360, reverse, 0.19)
			compare(current, old)
			check(current.mesh == mesh, "边缘平地的实际裁切范围不变时，余迹复用网格而非重复逐点建模")
			# 同一物理步修改地表也必须立刻撤销平地证明。
			var cell := terrain.data.world_to_cell(terrain.to_local(origin))
			terrain.data.set_overlay(cell, TerrainData.OVERLAY_WATER, true)
			for effect in [current, old]: draw(effect, rules, origin, Vector3.RIGHT, 1.52, 360, reverse, 0.2)
			compare(current, old)
			terrain.data.set_overlay(cell, TerrainData.OVERLAY_WATER, false)
			terrain.data.set_level(cell, 1)
			for effect in [current, old]: draw(effect, rules, origin, Vector3.RIGHT, 1.52, 360, reverse, 0.21)
			compare(current, old)
			terrain.data.set_level(cell, 0)
		# 移动边墙后仍须重新裁切，不能复用上一位置的遮挡结果。
		wall.position.x -= side * 0.2
		await settle()
		for effect in [current, old]: draw(effect, rules, origin, Vector3.FORWARD, 1.52, 360, false, 0.22)
		compare(current, old)

func avoidable_work_checks(current: GroundSlashEffect, old: MeshInstance3D, rules: PlayerSwordRules, wall: StaticBody3D) -> void:
	rules.effect_mode = PlayerSwordRules.SlashVisual.NATIVE_RIBBON
	rules.ribbon_visual = rules.flight_ribbon_visual.duplicate()
	wall.position = Vector3(0.65, 0.6, 0)
	wall.get_child(0).shape.size = Vector3(0.04, 1.2, 5.0)
	await settle()
	for effect in [current, old]: draw(effect, rules, Vector3.ZERO, Vector3.RIGHT, 1.52, 360, false, 0.1)
	compare(current, old)
	check(current.mesh.surface_get_array_index_len(0) < old.mesh.surface_get_array_index_len(0), "正式环绕刀光不提交完整透明中心的三角形")
	check(current.mesh.surface_get_array_len(0) < old.mesh.surface_get_array_len(0), "透明中心的无引用顶点也不再生成或上传")
	print(JSON.stringify({"case":"single_wall_orbit","rays":current.get("wall_rays"),"rays_skipped":current.get("wall_rays_skipped"),"triangles_before":old.mesh.surface_get_array_index_len(0)/3,"triangles_after":current.mesh.surface_get_array_index_len(0)/3,"vertices_before":old.mesh.surface_get_array_len(0),"vertices_after":current.mesh.surface_get_array_len(0)}))
	check("wall_rays" in current and "wall_rays_skipped" in current, "显示结果记录实际原生射线与安全省略数量")
	if "wall_rays" in current:
		check(current.get("wall_rays") > 0 and current.get("wall_rays") < 129 and current.get("wall_rays_skipped") > 0, "单侧墙面只精查可能碰墙的方向")
	for inner in [0.9, 0.2, 0.58]:
		rules.ribbon_visual.ribbon_inner_ratio = inner
		for effect in [current, old]: draw(effect, rules, Vector3.ZERO, Vector3.FORWARD, 1.52, 360, true, 0.12)
		compare(current, old)
	# 方向锥跨越 -PI/PI、斜墙和部分扇面时仍须保留每个真实命中。
	for index in 8:
		var theta := TAU * index / 8.0
		wall.position = Vector3(sin(theta) * 0.9, 0.6, -cos(theta) * 0.9)
		wall.rotation.y = theta + 0.31
		wall.get_child(0).shape.size = Vector3(0.04, 1.2, 1.8)
		await settle()
		for angle in [96.0, 360.0]:
			for effect in [current, old]: draw(effect, rules, Vector3.ZERO, Vector3(0.4, 0, -1).normalized(), 1.52 + index * 0.07, angle, index % 2 == 0, 0.12)
			compare(current, old)
	wall.rotation.y = 0.0
	wall.position = Vector3(0.65, 0.6, 0)
	wall.get_child(0).shape.size = Vector3(0.04, 1.2, 5.0)
	# 过多形状或新的射线层无法得到完整证明时，保留逐条原生查询。
	var crowded: Array[StaticBody3D] = []
	for index in 16: crowded.append(box(Vector3(-1.0 + index * 0.1, 0.45, 0.8), Vector3(0.025, 0.1, 0.025)))
	await settle()
	for effect in [current, old]: draw(effect, rules, Vector3.ZERO, Vector3.RIGHT, 1.52, 360, false, 0.13)
	compare(current, old)
	if "wall_rays" in current: check(current.get("wall_rays") == 129 and current.get("wall_rays_skipped") == 0, "障碍收集饱和时不跳过任何真实射线")
	for obstacle in crowded: obstacle.queue_free()
	await settle()
	var unknown := StaticBody3D.new()
	var unknown_collision := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.RIGHT, -0.5)
	unknown_collision.shape = plane
	unknown.add_child(unknown_collision)
	world.add_child(unknown)
	await settle()
	for effect in [current, old]: draw(effect, rules, Vector3.ZERO, Vector3.RIGHT, 1.52, 360, false, 0.14)
	compare(current, old)
	if "wall_rays" in current: check(current.get("wall_rays") == 129, "没有有限包围盒的平面保持所有原生查询")
	unknown.queue_free()
	await settle()
	current._wall_ray.collision_mask = 2
	old._wall_ray.collision_mask = 2
	for effect in [current, old]: draw(effect, rules, Vector3.ZERO, Vector3.RIGHT, 1.52, 360, false, 0.14)
	compare(current, old)
	if "wall_rays" in current: check(current.get("wall_rays") == 129, "自定义射线层不被默认障碍证明绕过")
	current._wall_ray.collision_mask = 1
	old._wall_ray.collision_mask = 1
	current._wall_ray.collide_with_areas = true
	old._wall_ray.collide_with_areas = true
	for effect in [current, old]: draw(effect, rules, Vector3.ZERO, Vector3.RIGHT, 1.52, 360, false, 0.14)
	compare(current, old)
	if "wall_rays" in current: check(current.get("wall_rays") == 129, "包含区域的自定义射线保持实时原生查询")
	current._wall_ray.collide_with_areas = false
	old._wall_ray.collide_with_areas = false
	# 模式热切换不能误用另一种索引布局的缓存网格。
	wall.position.x = 20
	await settle()
	for orbit in [false, true, false, true]:
		rules.ribbon_visual.ribbon_orbit_enabled = orbit
		for effect in [current, old]: draw(effect, rules, Vector3.ZERO, Vector3.RIGHT, 1.52, 360, false, 0.14)
		compare(current, old)
		check(current.mesh.surface_get_array_index_len(0) == (1536 if orbit else 3072), "平地缓存正确区分完整扇面与空心索引")

func attack_speed_checks() -> void: pass
func flight_checks() -> void: pass
func freeze_checks() -> void: pass
func input_and_art_checks() -> void: pass
func score_checks() -> void: pass
