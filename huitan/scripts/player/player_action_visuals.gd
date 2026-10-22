class_name PlayerActionVisuals
extends Resource

## 每槽可单独替换。clip 使用 side/front/back；侧向左右镜像，空槽沿用原人物动画。
## 保留原生像素、统一脚底锚点和画布；动画不缩放 Sprite、不驱动根节点移动。
@export_group("人物动作槽位")
@export var normal_attack: SpriteFrames
@export var charge: SpriteFrames
@export var flight: SpriteFrames
@export var flight_attack: SpriteFrames
@export var recovery: SpriteFrames
## 仅真实建筑／实体道具碰撞反弹触发，不响应怪群绕行；留空继续当前飞行动画。
@export var bounce: SpriteFrames
## 缺少攻击美术时，接口占用的占位时间；有素材时读取完整原生帧时长。
@export_range(0.05, 2.0, 0.05, "suffix:s") var placeholder_attack_seconds := 0.3
@export_group("蓄力特效")
@export var show_charge_effect := true
## 按人物实际缩放后的原生像素计量；不改变人物或真实拨怪半径。
@export_range(24.0, 64.0, 1.0) var charge_radius_pixels := 42.0
@export_range(0.0, 1.0, 0.05) var charge_effect_opacity := 0.95
@export_range(0.0, 1.0, 0.05) var charge_effect_energy := 0.35
@export_subgroup("蓄力渐强反馈")
@export var charge_dynamic_enabled := false
@export_range(0.0, 0.4, 0.01) var charge_ring_contraction := 0.20
@export_range(1.0, 6.0, 0.1) var charge_mote_speed_gain := 3.0
@export_range(10, 32, 1) var charge_mote_count := 18
@export_range(0.0, 0.15, 0.01, "suffix:s") var charge_full_settle_seconds := 0.06
@export_subgroup("绕身聚力风")
@export var charge_wind_enabled := false
@export var charge_wind_texture: Texture2D
## 下窄上宽的立体风旋；关闭时保留旧的向腰侧收拢轨迹。
@export var charge_wind_funnel_enabled := false
## 漏斗形模式中为上沿半径，按人物实际缩放后的原生像素计量。
@export_range(4.0, 120.0, 1.0) var charge_wind_radius_pixels := 82.0
@export_range(0.0, 60.0, 1.0) var charge_wind_bottom_radius_pixels := 6.0
@export_range(30.0, 100.0, 1.0) var charge_wind_height_pixels := 74.0
@export_range(2.0, 24.0, 1.0) var charge_wind_width_pixels := 8.0
@export_range(1.0, 4.0, 0.25) var charge_wind_turns := 2.25
## 每层沿不同方位旋转，内层轻微收径并降低不透明度；旧模式保持单层。
@export_range(1, 5, 1) var charge_wind_layers := 1
## 每条风带沿螺旋延伸的高度比例；越大越连贯，不扩大风场外沿。
@export_range(0.08, 0.4, 0.01) var charge_wind_trail_span := 0.14
## 按当前人物真实贴图轮廓剔除风带并留白；0 关闭，不改变风场几何。
@export_range(0.0, 6.0, 0.5) var charge_wind_body_clearance_pixels := 0.0
@export_range(0.0, 1.0, 0.05) var charge_wind_opacity := 0.70
@export_range(0.4, 2.0, 0.05, "suffix:s") var charge_wind_cycle_seconds := 1.05
@export_range(1.0, 4.0, 0.05) var charge_wind_full_speed_multiplier := 1.45
@export_group("碰撞路线预览")
@export var show_aim_guide := true
## Merge invisible intermediate physics previews into the next render update.
## Only display work changes; release, damage and real collisions stay physical.
@export var coalesce_charge_preview := false
## Coalesce empty-space ray checks inside one synchronous prediction only.
## Dynamic walls/mirrors are queried again on every prediction.
@export var deduplicate_charge_preview := false
@export var preview_show_target := true
## 仅首次碰墙可显示一次反射；后续接触只截断短尾段。
@export_range(0, 1, 1) var preview_bounces := 1
@export_range(1.0, 20.0, 0.5, "suffix:m") var preview_distance := 8.0
## 首次响应后的短方向提示，不推演完整怪群绕行；0 在接触点结束。
@export_range(0.0, 2.0, 0.1, "suffix:m") var preview_followup_distance := 1.0
@export var preview_color := Color(0.9, 0.82, 0.66)
@export_range(0.0, 1.0, 0.05) var preview_opacity := 0.45
@export_range(0.5, 2.0, 0.25) var preview_line_width_pixels := 1.0
@export_group("碰墙反弹特效")
@export var show_bounce_effect := true
@export var bounce_frames: SpriteFrames
## 同一画布内的碰撞核心像素坐标，旋转时保持该点锚定真实墙面。
@export var bounce_anchor_pixels := Vector2(16, 24)
@export_range(0.08, 0.4, 0.01, "suffix:s") var bounce_duration := 0.18
@export_range(0.0, 1.0, 0.05) var bounce_opacity := 0.95
@export_range(0.0, 2.0, 0.05) var bounce_energy := 0.65
@export_range(0.0, 1.0, 0.01, "suffix:m") var bounce_height := 0.45
@export_subgroup("碰点原生像素粒子")
@export var bounce_particles_enabled := false
@export_range(1, 16, 1) var bounce_particle_count := 8
@export_range(0.5, 6.0, 0.1, "suffix:m/s") var bounce_particle_speed := 3.2
@export_range(0.12, 0.5, 0.01, "suffix:s") var bounce_particle_seconds := 0.24
@export_group("人物受击像素粒子")
## 只响应真实扣血；地图独立启用，不添加受伤音效或改变战斗规则。
@export var hurt_particles_enabled := false
@export_range(1, 12, 1) var hurt_particle_count := 8
@export_range(0.15, 0.45, 0.01, "suffix:s") var hurt_particle_seconds := 0.32
## 散开距离与方片尺寸均按人物实际缩放后的原生像素计量。
@export_range(6.0, 24.0, 1.0, "suffix:px") var hurt_particle_spread_pixels := 16.0
@export_range(1.0, 3.0, 1.0, "suffix:px") var hurt_particle_size_pixels := 2.0
@export var hurt_particle_color := Color(1.0, 0.10, 0.16)
@export_group("人物受击画面提示")
@export var hurt_screen_enabled := false
@export_range(0.0, 0.15, 0.01) var hurt_screen_opacity := 0.08
@export_range(0.1, 0.4, 0.01, "suffix:s") var hurt_screen_seconds := 0.2
@export var hurt_screen_color := Color(0.9, 0.04, 0.07)
@export var hurt_camera_enabled := false
@export_range(0.0, 3.0, 0.25, "suffix:px") var hurt_shake_pixels := 1.5
@export_range(0.04, 0.12, 0.01, "suffix:s") var hurt_shake_seconds := 0.08
@export_range(0.0, 1.5, 0.05, "suffix:px") var hurt_orbit_shake_pixels := 0.65
@export_range(0.03, 0.08, 0.01, "suffix:s") var hurt_orbit_shake_seconds := 0.05
## 只限制镜头提示，不新增无敌时间；被高优先级反馈覆盖后不延后补播。
@export_range(0.2, 0.8, 0.05, "suffix:s") var hurt_shake_interval := 0.35
@export_group("弹射运动表现")
## 各地图独立开启；仅改变显示姿态，不改变人物动画、根节点或碰撞体。
@export var motion_feedback_enabled := false
@export_range(0.0, 15.0, 0.5, "suffix:°") var flight_lean_degrees := 9.0
@export_range(1.0, 30.0, 0.5, "suffix:m/s") var motion_reference_speed := 12.0
@export_range(0.01, 0.15, 0.005, "suffix:s") var impact_lean_hold := 0.045
@export_range(0.02, 0.3, 0.01, "suffix:s") var impact_lean_turn := 0.10
@export_range(0.02, 0.3, 0.01, "suffix:s") var lean_return_seconds := 0.12
@export_subgroup("反弹出射气流")
@export var departure_airflow_enabled := false
@export var departure_airflow_texture: Texture2D
@export_range(0.05, 0.4, 0.01, "suffix:s") var departure_airflow_seconds := 0.18
@export_range(0.05, 0.4, 0.01, "suffix:s") var departure_airflow_lifetime := 0.16
@export_range(0.1, 0.8, 0.02, "suffix:m") var departure_airflow_spacing := 0.30
@export_range(0.0, 1.0, 0.05) var departure_airflow_opacity := 0.65
@export_subgroup("反弹面能量扩散")
## 原生发光贴花沿真实接触平面扩张；只影响表面，不新增光源。
@export var surface_wave_enabled := false
@export var surface_wave_texture: Texture2D
@export_range(0.3, 2.0, 0.05, "suffix:m") var surface_wave_radius := 1.15
@export_range(0.15, 0.7, 0.01, "suffix:s") var surface_wave_seconds := 0.38
@export_range(0.0, 3.0, 0.05) var surface_wave_energy := 1.4
@export_subgroup("旧速度描边对照")
## 沿当前真实帧的后缘描光，不替换贴图，也不影响残影或碰撞体。
@export var speed_rim_enabled := false
@export_range(0.0, 4.0, 0.05) var speed_rim_strength := 1.8
@export_range(0.5, 3.0, 0.25, "suffix:px") var speed_rim_width_pixels := 1.25
@export var speed_rim_color := Color(1.0, 0.87, 0.57)
@export_subgroup("贴身速度气流")
## World 选择纹理粒子，旧速度描边仅保留手动对照。
@export var speed_flow_enabled := false
@export_enum("笔触粒子（对照）", "掠过气流") var speed_flow_mode := 0
@export var speed_flow_texture: Texture2D
## 归一化采样区域，只去掉纹理画布留白，不裁剪或重采样源文件。
@export var speed_flow_texture_region := Rect2(0, 0, 1, 1)
@export_range(0.0, 1.0, 0.05) var speed_flow_opacity := 0.5
@export_range(0.2, 1.5, 0.05, "suffix:m") var speed_flow_length := 0.65
@export_range(0.06, 0.3, 0.01, "suffix:s") var speed_flow_lifetime := 0.14
@export_range(0.2, 0.7, 0.01, "suffix:m") var speed_flow_radius := 0.34
## 与旧描边共用起效门槛，保留已保存参数的内部名称。
@export_range(0.0, 12.0, 0.25, "suffix:m/s") var speed_rim_min_speed := 3.0
@export_group("弹射地面火带")
## 视觉试玩；只记录真实飞行路径，暂不结算伤害或加入成长池。
@export var show_fire_trail := false
@export_range(0.1, 0.8, 0.01, "suffix:m") var fire_trail_width := 0.36
@export_range(0.05, 0.6, 0.01, "suffix:s") var fire_trail_fresh_seconds := 0.18
@export_range(0.1, 1.5, 0.05, "suffix:s") var fire_trail_burn_seconds := 0.65
@export_range(0.1, 3.0, 0.05, "suffix:s") var fire_trail_ember_seconds := 1.35
@export_range(0.0, 3.0, 0.05) var fire_trail_energy := 1.1
## 世界坐标像素密度；不把镜头透视烘焙进素材。
@export_range(20.0, 80.0, 1.0) var fire_trail_pixels_per_meter := 40.0
@export_subgroup("贴地火焰笔触与火星")
@export var fire_trail_flow_enabled := false
@export var fire_trail_brush: Texture2D
## 只在着色器中选择笔触区域，保留原图与原生像素。
@export var fire_trail_brush_region := Rect2(0.0201823, 0.3506944, 0.9544271, 0.2986111)
@export_range(0.0, 1.0, 0.05) var fire_trail_flow_strength := 0.8
@export_range(0.5, 4.0, 0.1) var fire_trail_flow_speed := 2.2
@export_range(0.05, 0.4, 0.01, "suffix:m") var fire_trail_spark_height := 0.22
@export_range(0.15, 0.5, 0.01, "suffix:m") var fire_trail_spark_spacing := 0.30
@export_range(0.0, 0.5, 0.05) var fire_trail_spark_amount := 0.2
@export_range(1.0, 5.0, 0.5, "suffix:px") var fire_trail_body_clearance_pixels := 2.0
@export_group("持续攻击视觉层次")
@export var combat_readability_enabled := false
@export var combat_contact_frames: SpriteFrames
@export_range(0.06, 0.2, 0.01, "suffix:s") var combat_contact_seconds := 0.12
@export_range(0.0, 0.4, 0.01) var combat_sword_body_opacity := 0.16
@export_range(0.1, 1.0, 0.05) var combat_residue_opacity := 0.35
@export_range(0.15, 0.5, 0.01, "suffix:s") var combat_death_focus_seconds := 0.28
@export_group("战斗反馈预热")
## 准备／休整阶段分帧建立完整对象；0 关闭，超出储备仍按需扩容。
@export_range(0, 128, 1) var feedback_prewarm_deaths := 0
@export_range(0, 128, 1) var feedback_prewarm_contacts := 0
@export_group("怪物受击身体反应")
## 真实非致死命中仅改变贴图姿态；不新增位移、眩晕或动画停顿。
@export var enemy_hit_reaction_enabled := false
@export_range(0.0, 20.0, 0.5, "suffix:°") var enemy_hit_lean_degrees := 12.0
@export_range(0.1, 0.5, 0.01, "suffix:s") var enemy_hit_recovery_seconds := 0.26
@export_group("弹射命中局部剪影")
## 弹射挥剑与奔雷的真实命中；只改变目标的原帧颜色，不改变人物、镜头或世界时间。
@export var enemy_hit_silhouette_enabled := false
@export_range(0.03, 0.3, 0.01, "suffix:s") var enemy_hit_silhouette_seconds := 0.08
@export_range(0.0, 1.0, 0.05) var enemy_hit_silhouette_strength := 0.95
## 同一目标的重复命中合并，保留恢复原色的间隔。
@export_range(0.08, 0.4, 0.01, "suffix:s") var enemy_hit_silhouette_interval := 0.14
@export var enemy_hit_silhouette_color := Color(1.0, 0.96, 0.82)
@export_group("命中碎屑与击杀重音")
@export var hit_debris_enabled := false
@export_range(1, 32, 1) var hit_debris_count := 5
@export_range(0.5, 4.0, 0.1) var hit_debris_speed_multiplier := 1.0
@export_range(0.15, 0.6, 0.01, "suffix:s") var hit_debris_seconds := 0.38
@export_range(0.05, 0.3, 0.01, "suffix:s") var hit_debris_interval := 0.12
@export var kill_slash_enabled := false
@export var kill_slash_texture: Texture2D
@export_range(0.15, 0.6, 0.01, "suffix:s") var kill_slash_seconds := 0.32
## 密集击杀共用长斩痕；每只怪物仍保留自己的碎屑。
@export_range(0.05, 0.4, 0.01, "suffix:s") var kill_slash_interval := 0.12
## 普通挥剑非致死命中；轻反馈不占用击杀与群杀的重音间隔。
@export var sword_hit_impact_enabled := false
@export_range(0.0, 0.08, 0.005, "suffix:s") var sword_hitstop_seconds := 0.035
@export_range(0.2, 1.0, 0.01, "suffix:s") var sword_hit_impact_interval := 0.35
@export_range(0.06, 0.3, 0.01, "suffix:s") var sword_hit_shake_seconds := 0.14
@export_range(0.0, 8.0, 0.5, "suffix:px") var sword_hit_shake_pixels := 3.0
@export var kill_impact_enabled := false
@export_range(0.0, 0.2, 0.005, "suffix:s") var kill_hitstop_seconds := 0.1
@export_range(0.0, 0.2, 0.01, "suffix:s") var kill_slow_tail_seconds := 0.08
## 同批／连续击杀共用间隔，不延长已触发的短顿。
@export_range(0.15, 2.0, 0.01, "suffix:s") var kill_hitstop_interval := 0.85
@export_range(0.06, 0.4, 0.01, "suffix:s") var kill_shake_seconds := 0.26
@export_range(0.0, 16.0, 0.5, "suffix:px") var kill_shake_pixels := 9.0
@export var kill_shot_enabled := false
## 群杀推进独立统计；单杀只触发短顿与震动。
@export_range(2, 12, 1) var kill_shot_minimum_kills := 3
@export_range(0.03, 0.25, 0.01, "suffix:s") var kill_shot_group_window := 0.12
@export_range(0.12, 0.4, 0.01, "suffix:s") var kill_shot_enter_seconds := 0.24
@export_range(0.6, 3.0, 0.05, "suffix:s") var kill_shot_interval := 1.1
@export_range(0.25, 1.2, 0.01, "suffix:s") var kill_shot_seconds := 0.72
@export_range(0.6, 1.0, 0.01) var kill_shot_zoom_scale := 0.94
@export_group("近身与奔雷击杀击飞")
## 普通挥剑、弹射挥剑与奔雷的随机抛射致死表现；不改变存活怪物外力、眩晕或死亡结算。
@export var melee_death_enabled := false
@export_range(0.2, 1.2, 0.05, "suffix:s") var melee_death_seconds := 0.6
@export_range(0.2, 4.0, 0.1, "suffix:m") var melee_death_distance := 1.4
@export_range(0.1, 2.0, 0.05, "suffix:m") var melee_death_height := 0.75
@export_range(0.0, 1080.0, 5.0, "suffix:°") var melee_death_spin_degrees := 110.0
@export_subgroup("击杀速度与距离")
@export_range(0.5, 8.0, 0.1, "suffix:m") var melee_death_near_distance := 3.0
@export_range(1.0, 20.0, 0.5, "suffix:m/s") var melee_death_reference_speed := 6.0
@export_range(0.1, 1.0, 0.05) var melee_death_min_strength := 0.3
@export_range(0.4, 1.0, 0.05) var melee_death_storm_retention := 0.7
@export_subgroup("击杀短顿与爆点")
@export_range(0.0, 0.08, 0.005, "suffix:s") var melee_death_hit_pause := 0.035
@export_range(0.2, 1.0, 0.05, "suffix:s") var melee_death_air_seconds := 0.5
@export var melee_death_impact_frames: SpriteFrames
@export_range(0.06, 0.3, 0.01, "suffix:s") var melee_death_impact_seconds := 0.16
@export_subgroup("飞行余迹与落地")
@export var melee_death_trail_enabled := false
@export var melee_death_landing_enabled := false
@export_range(0.0, 0.6, 0.02, "suffix:m") var melee_death_bounce_height := 0.28
@export_range(0.0, 1.0, 0.05, "suffix:m") var melee_death_slide_distance := 0.45
@export var melee_death_cluster_enabled := false
@export_group("框架观察")
## 仅用于观察拨怪圆周，不改变真实范围。
@export var show_push_ring := false

## 命中快照仅驱动死亡表现；速度先封顶，再让奔雷从首层起逐层衰减。
func melee_death_strength(hit: Dictionary) -> float:
	var motion: Vector3 = hit.get("motion_velocity", Vector3.ZERO)
	if not motion.is_finite(): motion = Vector3.ZERO
	motion.y = 0.0
	var strength := clampf(motion.length() / maxf(melee_death_reference_speed, 0.1), melee_death_min_strength, 1.8)
	if hit.get("source", &"") == &"ricochet_storm":
		strength *= pow(melee_death_storm_retention, maxi(0, int(hit.get("storm_layer", 0))))
	return strength

func frames_for(action: StringName) -> SpriteFrames:
	match action:
		&"normal_attack": return normal_attack
		&"charge": return charge
		&"flight": return flight
		&"flight_attack": return flight_attack
		&"recovery": return recovery
		&"bounce": return bounce
	return null
