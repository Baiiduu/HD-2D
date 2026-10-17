@tool
extends RefCounted

const SYSTEM_SWITCH_LABELS := {
	"run_growth.gd": "升级系统本地开关",
	"run_skill_draft.gd": "抽卡系统本地开关",
	"run_skill_manager.gd": "局内技能管理器本地开关",
}
const CATEGORIES := ["视觉", "人物", "战斗与成长", "地图与地编", "UI", "声音", "物品与规则"]
const LABELS := {
	"configuration": "场景战斗配置", "storm_damage": "奔雷基础伤害", "storm_attack_interval": "奔雷施放间隔", "bottom_bars_collapsed": "隐藏底部装备栏",
	"sky_strength": "天空极光亮度", "reflection_strength": "极光倒影强度", "flow_speed": "极光流动速度",
	"green_color": "极光青绿主色", "purple_color": "极光紫色边缘", "reflection_regions": "极光倒影区域（中心 X/Z、半径 X/Z）",
	"blue_color": "极光青蓝过渡", "pink_color": "极光粉红边缘",
	"crowd_deflection_enabled": "人物接群偏转开关", "crowd_contact_radius": "人物接群距离",
	"crowd_turn_distance": "绕群接入与脱离过渡长度", "crowd_exit_outward": "接群出射外向分量",
	"crowd_arc_degrees": "人物沿怪群绕行角度", "enemy_push_enabled": "旧版拨怪开关",
	"crowd_arc_distance": "人物贴群弧线路程上限",
	"crowd_speed_retention": "接群速度保留", "crowd_release_clearance": "同群再次接触脱离余量",
	"eccentric_enabled": "怪群自动环绕开关", "eccentric_step_distance": "环绕轮廓更新路程",
	"eccentric_edge_clearance": "偏心外沿额外间隔", "eccentric_outward_sway": "偏心外摆幅度",
	"eccentric_search_radius": "环绕怪群搜索距离",
	"eccentric_capture_margin": "环绕提前捕获余量",
	"show_bounce_effect": "碰墙反弹特效开关", "bounce_frames": "反弹火花原生帧",
	"bounce_anchor_pixels": "反弹火花碰点像素锚点", "bounce_duration": "反弹火花持续时间",
	"bounce_opacity": "反弹火花透明度", "bounce_energy": "反弹火花亮度", "bounce_height": "反弹火花显示高度",
	"show_fire_trail": "弹射地面火带开关", "fire_trail_width": "地面火带宽度",
	"fire_trail_fresh_seconds": "火带新生亮火时间", "fire_trail_burn_seconds": "火带持续燃烧时间",
	"fire_trail_ember_seconds": "火带暗红余烬时间", "fire_trail_energy": "地面火带亮度",
	"fire_trail_pixels_per_meter": "火带世界像素密度",
	"playlists": "BGM 场合曲池", "default_context": "默认音乐场合", "music_transition_time": "曲间切换时长",
	"follow_battle_session": "音乐跟随波次状态", "exploration_context": "准备与结算曲池", "combat_context": "战斗与波间曲池",
	"track_id": "曲目标识", "track_title": "曲目名称", "stream": "音乐文件", "loop_crossfade": "曲尾衔接时长",
	"context_id": "播放场合标识", "tracks": "曲池曲目", "play_order": "曲池播放顺序",
	"music_enabled": "背景音乐开关", "music_stream": "旧场景单曲", "music_fade_time": "音乐开关淡化时长",
	"music_loop_crossfade": "旧单曲循环衔接时长", "music_bus": "音乐输出总线",
	"crowd_clearance_distance": "人物周身留白距离（额外）",
	"pursuit_lookahead": "追击路线前视距离", "pursuit_flank_strength": "追击侧向让行强度",
	"patch_enabled": "成片电涌开关", "patch_duration": "成片电涌停留时间", "patch_opacity": "成片电涌强度", "patch_height": "成片电涌高度",
	"mixed_horde": "自动目录混合怪潮", "horde_weight": "怪潮出场权重（0 排除）",
	"action_volume_db": "核心动作音量", "enemy_volume_db": "怪物反馈音量", "feedback_volume_db": "成长与波次音量",
	"bounce_gain_db": "人物反弹碰撞音量增益",
	"water_boundary_reflection_enabled": "人物遇水边界反弹",
	"flight_audio_enabled": "弹射动能气流开关", "flight_gain_db": "弹射气流音量增益",
	"flight_low_speed_gain_db": "低速气流额外音量", "flight_reference_speed": "气流满音量参考速度",
	"flight_volume_smoothing": "气流音量平滑时间", "flight_fade_out_seconds": "停止弹射气流淡出时间",
	"low_health_ratio": "濒危提示血量比例", "pickup_interval": "经验音提示间隔",
	"propagation_sounds": "雷潮传导音源", "propagation_layer_gain_db": "雷潮逐层音量变化",
	"ricochet_camera_settings": "弹射镜头反馈配置", "launch_lag_seconds": "起射镜头滞后时间",
	"launch_follow_fraction": "起射镜头跟随比例", "lookahead_ratio": "飞行镜头前视比例",
	"lead_settle_seconds": "飞行前视过渡时间", "bounce_inertia_seconds": "反弹镜头惯性时间",
	"return_seconds": "弹射镜头归位时间", "max_offset_ratio": "新增镜头偏移上限",
	"impact_shake_pixels": "撞墙轻震像素", "impact_shake_seconds": "撞墙轻震时间", "impact_min_interval": "撞墙轻震最短间隔",
	"number_styles": "伤害数字样式列表", "style_id": "伤害表现标签", "number_font": "伤害数字字体（可替换像素字体）",
	"number_font_size": "伤害数字字号", "number_color": "伤害数字颜色", "number_outline_color": "数字描边颜色",
	"number_outline_size": "数字描边粗细", "number_shadow_color": "数字投影颜色", "number_shadow_offset": "数字投影偏移",
	"number_suffix": "数字后缀", "decimal_places": "伤害显示小数位", "number_lifetime": "数字存留时间",
	"squash_seconds": "数字起跳压缩时间", "rise_seconds": "数字上升时间", "apex_seconds": "顶点停留时间",
	"rise_pixels": "数字上升高度", "fall_pixels": "数字回落距离", "drift_pixels": "数字侧向飘动距离",
	"pop_scale": "数字起跳放大倍率", "tilt_degrees": "数字倾斜幅度", "fade_start": "数字开始消散进度",
	"number_spark_count": "收尾碎光数量", "number_spark_color": "收尾碎光颜色", "number_stack_columns": "连续命中错位列数",
	"number_stack_spacing": "连续命中错位间距", "number_prewarm": "数字节点预热数量", "number_idle_limit": "数字闲置池上限",
	"trigger_radius": "雷潮切入半径", "spread_radius": "雷潮传导距离", "spread_layers": "雷潮扩散层数", "max_propagation_radius": "雷潮传播总半径",
	"targets_per_layer": "雷潮每片目标数", "layer_interval": "雷潮片间间隔", "sky_height": "降雷高度",
	"arc_texture": "雷潮电弧素材", "arc_duration": "电弧消退时长", "reveal_seconds": "电弧展开时间",
	"arc_energy_multiplier": "雷潮主电弧亮度倍率",
	"flight_trail_settings": "弹射人物残影（飞行拖尾）", "flight_trail_color": "人物残影乘色",
	"flight_echo_count": "人物残影数量", "flight_echo_spacing": "人物残影间距",
	"flight_echo_saturation": "人物残影饱和度", "flight_echo_brightness": "人物残影亮度",
	"flight_trail_max_length": "人物残影尾迹长度", "flight_trail_lifetime": "人物残影消散时间",
	"flight_trail_opacity": "人物残影透明度", "flight_trail_energy": "人物残影自发光",
	"sword_rules": "人物自带基础剑术", "normal_interval": "普攻出手间隔", "flight_interval": "弹射挥剑间隔", "minimum_attack_interval": "剑术最短出手间隔",
	"normal_range": "普攻半径", "flight_range": "弹射挥剑半径", "normal_angle": "普攻扇角", "flight_angle": "弹射挥剑扇角",
	"sweep_seconds": "基础剑术扫击时间", "fade_seconds": "基础剑术收尾时间", "art_radius_pixels": "剑光原生半径像素",
	"effect_height": "刀光中心高度", "effect_tilt_degrees": "刀光斜切角度",
	"effect_mode": "剑光显示方式", "arc_width": "窄弧刀痕厚度", "arc_trail_degrees": "窄弧尾迹角度",
	"arc_blade_color": "窄弧刀锋颜色", "arc_tail_color": "窄弧尾迹颜色", "arc_pixel_size": "窄弧原生像素尺寸",
	"meowa_body_opacity": "Meowa 白刃存在感", "meowa_tail_spread": "Meowa 拖尾展开倍率", "meowa_tail_inner_ratio": "Meowa 拖尾内端半径比例", "meowa_tail_seconds": "Meowa 破碎消散时长",
	"tree_local_light_softness": "树图近灯柔化", "lamp_canopy_clearance": "灯头树冠间隙",
	"ricochet_rules": "人物本体弹射规则", "action_visuals": "人物动作资源槽位",
	"full_charge_seconds": "蓄满所需时间", "minimum_launch_speed": "起步弹射速度", "maximum_launch_speed": "满蓄力弹射速度",
	"flight_seconds": "旧版飞行时间（已停用）", "cooldown_seconds": "弹射冷却", "wall_bounce_limit": "旧版反弹次数（已停用）",
	"minimum_bounce_speed": "人物续弹最低速度", "flight_deceleration": "飞行每秒耗速", "bounce_speed_cost": "每次碰撞固定耗速",
	"bounce_speed_retention": "反弹速度保留比例", "ground_height_tolerance": "弹射允许地表高差",
	"push_radius": "拨怪触发半径", "push_initial_speed": "怪群绕行速度", "push_seconds": "怪群绕行收势缓冲时间",
	"push_group_link_distance": "怪群相连判定距离", "push_group_search_radius": "怪群局部搜索半径", "push_group_edge_margin": "怪群绕行外沿余量",
	"push_arrival_arc_degrees": "怪群后沿落点扇区角度",
	"push_chain_layers": "怪群绕行接力层数", "push_chain_speed_retention": "接力推力保留比例",
	"push_chain_stun_retention": "接力眩晕保留比例", "push_chain_min_speed": "接力最低传递速度",
	"clockwise": "人物正撞绕群顺时针旋向（兼容拨怪）", "push_height_tolerance": "怪群接触允许高差", "normal_attack": "普通攻击动画",
	"charge": "蓄力动画", "flight": "弹射飞行动画", "flight_attack": "飞行攻击动画", "recovery": "弹射收尾动画",
	"placeholder_attack_seconds": "缺少攻击素材的占位时长", "show_aim_guide": "显示碰撞路线预览", "show_push_ring": "显示拨怪作用圆",
	"preview_show_target": "预览首个目标提示", "preview_bounces": "仅预览显示的反弹次数", "preview_distance": "预览路线最长距离",
	"preview_followup_distance": "首次接触后的预测长度",
	"preview_color": "预览路线颜色", "preview_opacity": "预览路线透明度", "preview_line_width_pixels": "预览虚线宽度（人物原生像素）",
	"show_charge_effect": "显示蓄力特效", "charge_radius_pixels": "蓄力环半径（人物原生像素）",
	"charge_effect_opacity": "蓄力特效透明度", "charge_effect_energy": "蓄力特效亮度",
	"enemies": "已登记怪物", "display_name": "怪物名称", "spawn_clearance": "出场留空半径",
	"trigger_distance": "冲锋触发距离", "windup_seconds": "招式蓄力时间", "recovery_seconds": "招式恢复时间",
	"charge_speed": "锁线冲锋速度", "charge_distance": "锁线冲锋距离", "shooting_range": "吐籽射击范围", "retreat_distance": "花兽退步距离",
	"projectile_speed": "种子飞行速度", "projectile_distance": "种子最大距离", "projectile_radius": "种子碰撞半径",
	"child_enemy_id": "分裂幼体标识", "split_delay": "死亡后分裂延迟", "boost_radius": "鸣铃鼓舞半径",
	"speed_multiplier": "鼓舞移速倍率", "boost_seconds": "鼓舞持续时间", "attack_sound": "怪物招式音源", "death_sound": "怪物死亡音源",
	"extra_asset_manifest": "附加地编素材目录", "extra_density": "附加植物密度", "extra_scale": "附加植物尺度", "extra_asset_ids": "附加植物选择",
	"style_wind": "时段风摆倍率", "style_wind_tempo": "时段风摆节奏", "style_fireflies": "时段光点可见比例",
	"region_wind": "区域风摆倍率", "region_fireflies": "区域光点可见比例", "region_blend_width": "动态区域过渡宽度",
	"transition_seconds": "环境动态渐变时间", "battle_fireflies_enabled": "战区外围光点", "battle_firefly_height": "外围光点高度",
	"night_firefly_size": "夜晚光点尺寸倍率",
	"style": "画面风格", "runtime_switch_enabled": "游戏内切换开关", "style_key": "切换按键",
	"pixel_art_enabled": "统一像素美术", "color_ramps_enabled": "材质色阶开关", "color_palette": "材质色板",
	"distance": "镜头距离", "pitch_degrees": "俯角", "fov": "视野 FOV", "focus_height": "焦点高度",
	"dof_amount": "景深强度", "smoothing": "跟随平滑度", "dead_zone": "跟随死区", "yaw_degrees": "初始朝向",
	"exposure": "曝光", "brightness": "亮度", "contrast": "对比度", "saturation": "饱和度", "bloom": "辉光",
	"ambient_energy": "环境光强度", "moon_energy": "主光强度", "fog_amount": "雾强度", "wetness": "地面湿润",
	"wet_surface_enabled": "湿地面反射开关", "wet_surface_minimum": "雨后湿润下限", "wet_surface_coverage": "湿膜覆盖", "wet_surface_patch_size": "湿膜斑块尺寸",
	"wet_surface_roughness": "湿膜粗糙度", "wet_surface_reflectivity": "湿膜镜面强度", "wet_surface_ripple_strength": "倒影波纹扰动", "wet_surface_ripple_speed": "倒影波纹速度", "wet_surface_grass_response": "草地湿膜响应",
	"hemisphere_fill_enabled": "半球补光开关", "hemisphere_sky_color": "半球天空色", "hemisphere_ground_color": "半球地面反弹色",
	"value_sample_enabled": "明暗层次样板开关", "value_sample_profile": "明暗层次配置",
	"fog_post_enabled": "雾与后处理样板开关", "fog_post_presets": "雾与后处理配置",
	"fog_begin": "距离雾起点", "fog_end": "距离雾终点", "fog_curve": "距离雾增长曲线", "low_fog": "低处雾密度", "volumetric_density": "体积雾密度",
	"bloom_threshold": "泛光 HDR 阈值", "bloom_floor": "低亮度泛光强度", "vignette": "暗角强度", "vignette_radius": "暗角清晰区半径", "shadow_lift": "Lumina 暗部提亮", "split_toning": "分离色调强度",
	"original_light_refinement_enabled": "原始光影增强开关", "original_light_preset": "原始光影增强配置",
	"original_material_palette": "原版材质色板", "material_palette": "层次材质色板", "original_foliage_palette": "原版花草色板", "foliage_palette": "层次花草色板", "lighting_presets": "层次光影配置",
	"weather_mode": "晴雨模式", "rain_intensity": "雨量比例", "rain_amount": "雨丝数量", "wind_strength": "风力",
	"ground_rain_enabled": "地面落雨开关", "ground_splash_size": "地面雨纹半径", "ground_splash_density": "地面雨纹密度", "ground_splash_strength": "地面雨纹强度",
	"ground_sheen": "草地湿亮斑覆盖",
	"stable_shadows": "固定柔和簇影",
	"street_fill_shadows_enabled": "路灯全向补光阴影开关", "fill_shadows_enabled": "本灯全向补光阴影开关",
	"street_cone_shadows_enabled": "路灯聚光阴影开关",
	"blink_plant_strength": "闪身压弯花草", "blink_rain_strength": "闪身带偏雨滴",
	"speed": "人物速度", "blink_distance": "闪身距离", "blink_cooldown": "闪身间隔", "jump_height": "跳跃高度",
	"damage": "伤害", "attack_range": "攻击范围", "attack_interval": "攻击间隔", "fan_angle": "扇角",
	"mark_duration": "镜印持续时间", "reflection_limit": "反射次数上限", "match_player_pixel_density": "匹配人物实际像素密度",
	"flight_speed": "弹丸速度", "hit_radius": "弹丸碰撞半径", "flight_height": "弹丸离地高度", "height_tolerance": "允许地面高差",
	"head_width": "晶体显示宽度", "trail_width": "光丝显示宽度", "bounce_sounds": "墙面反射音源",
	"effect_scene": "弹丸特效场景", "feedback_scene": "碰撞反馈场景",
	"definitions": "本局增益列表", "attribute": "增益属性", "bonus_per_level": "每级增益比例", "max_level": "增益等级上限", "bonus_cap": "同类总增幅上限",
	"diminishing_after": "温和递减起始等级（0 关闭）", "breakthrough_every": "突破间隔等级（0 关闭）",
	"breakthrough_multiplier": "突破收益倍率", "required_levels": "专精前置等级", "extra_effects": "组合收益与代价",
	"card_text_color": "成长卡片文字颜色",
	"cards_per_draw": "升级每次抽取张数", "initial_cards_per_draw": "初始技能抽取张数",
	"rerolls_per_run": "本局共用重抽次数", "draw_seed": "抽卡复现种子（0 随机）", "choice_hint": "抽卡操作提示",
	"skill_definition": "本局技能定义", "skill_paths": "起始技能组件", "levels": "技能等级列表", "parameters": "等级倍率与行为参数",
	"show_run_skill_icons": "本局技能图标", "level_font_size": "技能等级字号",
	"windup_time": "起手时间", "sweep_time": "扫击时间", "fade_time": "收尾时间", "knockback_distance": "击退距离",
	"effect_opacity": "特效透明度", "effect_energy": "特效亮度", "health": "生命", "attack_damage": "怪物攻击伤害",
	"move_speed": "怪物速度", "experience_reward": "经验掉落", "waves": "波次列表", "entries": "出怪编排",
	"batch_size": "怪潮每批数量", "start_delay": "首次进场时间", "interval": "批次或逐只间隔", "spawn_zone_ids": "允许进场区域",
	"enemy_catalog": "怪物目录", "enemy_id": "怪物标识", "population_rules": "怪潮数量档位", "population_cost": "怪物容量成本", "max_alive": "同种怪物同场上限",
	"enemy_occlusion_outline_enabled": "波次怪物遮挡轮廓（全部）",
	"simulation_mode": "巨量怪潮模拟模式", "simulation_enemy_count": "模拟怪潮目标数量",
	"simulation_skills": "模拟持有技能与等级", "skill_level": "本局技能等级（0 不携带）",
	"health_growth_rules": "无尽生命成长规则", "health_growth_enabled": "参与无尽生命成长", "start_wave": "生命成长起始波",
	"bonus_per_wave": "每波基础生命增幅", "minimum_multiplier": "生命倍率下限", "maximum_multiplier": "生命倍率上限",
	"role": "怪物分类", "body_radius": "身体碰撞半径", "body_height": "身体碰撞高度", "knockback_multiplier": "击退倍率",
	"stun_duration_multiplier": "眩晕时长倍率", "push_stun_seconds": "拨怪基础眩晕秒数",
	"combat_stop_distance": "接近停止距离", "contact_distance": "接触攻击距离", "contact_height": "接触攻击高差", "route_interval": "路线刷新间隔",
	"separation_radius": "聚群目标间距", "separation_strength": "聚群避让强度", "animation_speed": "动画速度",
	"navigation_radius": "导航通行半径",
	"first_active_limit": "开场同场上限", "growth_start_wave": "容量递增起始波", "active_growth_per_wave": "每波同场容量增量",
	"max_active": "同场容量终值", "max_population_cost": "同场容量点预算", "role_limits": "四类怪物同场上限",
	"enemies_per_wave_increment": "每波总数增量", "max_wave_enemies": "单波怪物总数上限", "max_queued_per_wave": "单波含召唤登记预算",
	"interval_reduction_per_wave": "每波刷新间隔减幅", "max_interval_reduction": "刷新间隔最大减幅", "min_spawn_interval": "最短出怪间隔",
	"surround_start_wave": "多向进场起始波（0 停用）", "surround_max_fronts": "怪潮同时进场方向上限",
	"spawns_per_tick": "每物理帧生成上限", "checks_per_tick": "每物理帧检查上限", "position_attempts": "每任务位置尝试上限",
	"spawn_interval": "出怪间隔", "spawn_warning": "出场预告", "retry_key": "重试按键", "rules": "规则资源",
	"max_active_enemies": "同场怪物上限", "top_margin": "顶部边距", "hint_font_size": "波次提示字号", "hint_opacity": "波次提示透明度",
	"endless_mode": "无尽模式", "endless_enemies_per_wave": "无尽每波增加数量", "endless_max_enemies": "无尽每波数量上限",
	"endless_interval_reduction": "无尽每波刷怪间隔减幅", "endless_min_spawn_interval": "无尽最短刷怪间隔",
	"grass_density": "草丛密度", "flower_density": "花簇密度", "paint_palette": "地表画笔列表", "data": "地形数据",
	"grass_variation_enabled": "草地深浅开关", "grass_variation_strength": "草地深浅强度", "grass_variation_size": "草地斑块大小",
	"core_size": "战区中心尺寸", "loop_width": "绕行带宽度", "ui_scale": "界面缩放", "font_size": "文字字号",
	"opening_spawn_offset": "开场刷新左右／前进距离", "entry_inset": "开战交互向场内距离",
	"first_level_experience": "首次升级经验", "per_level_increase": "每级经验增量", "curve_increase": "经验曲线增量", "level_cap": "本局等级上限",
	"bar_width": "属性条宽度", "slot_size": "槽位尺寸", "slot_spacing": "槽位间隔", "screen_margin": "屏幕边距", "glow_strength": "辉光强度",
	"track_width": "经验槽宽度", "badge_width": "等级底片宽度", "attribute_gap": "血蓝条下方间隔", "follow_attributes": "经验条跟随属性条",
	"medium_threshold": "紫色宝石经验阈值", "large_threshold": "暖金宝石经验阈值", "gem_height": "宝石世界高度",
	"bob_amplitude": "宝石漂浮幅度", "bob_speed": "宝石漂浮速度", "absorb_size": "吸收微光尺寸", "absorb_opacity": "吸收微光透明度",
	"flow_enabled": "经验条流光开关", "flow_interval": "流光间隔", "flow_duration": "流光扫过时间", "flow_width": "流光宽度", "flow_strength": "流光亮度",
	"glint_size": "端点星芒尺寸", "glint_strength": "端点星芒强度", "glint_pulse_speed": "端点呼吸速度",
	"trail_length": "宝石流光长度", "trail_size": "尾迹光点尺寸", "trail_brightness": "宝石尾迹亮度", "trail_opacity": "宝石尾迹透明度",
	"background_opacity": "暗底透明度", "volume_db": "音量", "pixel_stone_detail_strength": "卵石暗点保留",
	"music_volume_db": "背景音乐音量", "rain_volume_db": "雨声音量", "wind_volume_db": "风声音量",
	"audio_enabled": "攻击音效开关", "audio_volume_db": "攻击音效音量", "hit_volume_db": "命中声增益",
	"sweep_sounds": "挥击音源", "hit_sounds": "命中音源", "audio_bus": "音频总线", "audio_pitch": "攻击音高",
	"audio_pitch_variation": "攻击音高变化", "hit_sound_limit": "每击命中声上限", "hit_sound_interval": "命中声最小间隔",
	"rotation_sound_interval": "旋转声音脉冲间隔",
	"audio_manager": "公共声音管理器", "max_voices": "全局战斗声音上限", "important_reserve": "重要声音预留",
	"per_cue_limit": "同种声音同时上限", "minimum_interval": "同源声音最小间隔", "merge_window": "密集反馈合并时间",
	"merge_radius": "密集反馈合并半径", "near_distance": "声音清晰半径", "far_distance": "声音最远距离",
	"distance_falloff": "声音距离衰减", "offscreen_gain": "画面外普通声音增益", "panning_strength": "左右声像强度",
	"listener_height": "听觉中心高度", "combat_volume_db": "战斗分组增益", "ambience_volume_db": "环境分组增益",
	"ui_volume_db": "UI 分组增益", "movement_volume_db": "人物动作分组增益", "compression_enabled": "战斗压缩开关",
	"compression_threshold_db": "战斗压缩阈值", "compression_ratio": "战斗压缩比例", "limiter_enabled": "总输出限幅开关",
	"limiter_ceiling_db": "总输出峰值上限",
}
const COMMON := {
	"environment_lantern.gd": ["fill_shadows_enabled"],
	"scene_combat_binding.gd": ["configuration"],
	"scene_combat_configuration.gd": ["ricochet_rules", "sword_rules", "population_rules", "waves", "max_active_enemies", "endless_mode", "storm_damage", "storm_attack_interval", "crowd_clearance_distance"],
	"aurora_sky.gd": ["enabled", "sky_strength", "reflection_strength", "flow_speed", "green_color", "blue_color", "purple_color", "pink_color", "reflection_regions"],
	"ricochet_camera_settings.gd": ["enabled", "launch_lag_seconds", "lookahead_ratio", "lead_settle_seconds", "bounce_inertia_seconds", "return_seconds", "max_offset_ratio", "impact_shake_pixels"],
	"damage_numbers.gd": ["enabled", "number_styles", "number_stack_columns", "number_stack_spacing", "number_idle_limit"],
	"damage_number_style.gd": ["number_font", "number_font_size", "number_color", "number_lifetime", "rise_pixels", "drift_pixels", "pop_scale"],
	"ricochet_storm.gd": ["enabled", "damage", "attack_interval", "trigger_radius", "spread_radius", "max_propagation_radius", "spread_layers", "targets_per_layer", "layer_interval", "skill_definition", "effect_scene"],
	"ricochet_storm_effect.gd": ["pixel_size", "arc_duration", "reveal_seconds", "sky_height", "effect_energy", "arc_energy_multiplier", "effect_opacity", "impact_frames", "patch_enabled", "patch_duration", "patch_opacity", "patch_height"],
	"player_flight_trail_settings.gd": ["enabled", "flight_echo_count", "flight_echo_spacing", "flight_trail_color", "flight_echo_saturation", "flight_echo_brightness", "flight_trail_max_length", "flight_trail_lifetime", "flight_trail_opacity", "flight_trail_energy"],
	"player_sword_rules.gd": ["enabled", "damage", "normal_interval", "flight_interval", "minimum_attack_interval", "normal_range", "flight_range", "normal_angle", "flight_angle", "effect_mode", "frames", "arc_width", "arc_trail_degrees", "meowa_body_opacity", "meowa_tail_spread", "meowa_tail_inner_ratio", "meowa_tail_seconds", "effect_height", "effect_tilt_degrees", "effect_opacity", "effect_energy"],
	"player_ricochet_rules.gd": ["eccentric_enabled", "eccentric_capture_margin", "eccentric_step_distance", "eccentric_edge_clearance", "eccentric_outward_sway", "eccentric_search_radius", "crowd_deflection_enabled", "crowd_arc_degrees", "crowd_arc_distance", "enemy_push_enabled", "crowd_contact_radius", "crowd_turn_distance", "crowd_exit_outward", "crowd_speed_retention", "crowd_release_clearance", "full_charge_seconds", "minimum_launch_speed", "maximum_launch_speed", "bounce_speed_retention", "minimum_bounce_speed", "flight_deceleration", "bounce_speed_cost", "push_radius", "push_initial_speed", "push_seconds", "push_stun_seconds", "push_group_link_distance", "push_group_search_radius", "push_group_edge_margin", "push_arrival_arc_degrees", "push_chain_layers", "push_chain_speed_retention", "push_chain_stun_retention", "push_chain_min_speed", "clockwise"],
	"player_action_visuals.gd": ["normal_attack", "charge", "flight", "flight_attack", "recovery", "show_bounce_effect", "bounce_frames", "bounce_anchor_pixels", "bounce_duration", "bounce_opacity", "bounce_energy", "bounce_height", "show_fire_trail", "fire_trail_width", "fire_trail_fresh_seconds", "fire_trail_burn_seconds", "fire_trail_ember_seconds", "fire_trail_energy", "fire_trail_pixels_per_meter", "show_charge_effect", "show_aim_guide", "charge_radius_pixels", "charge_effect_opacity", "charge_effect_energy", "preview_show_target", "preview_bounces", "preview_distance", "preview_followup_distance", "preview_color", "preview_opacity", "preview_line_width_pixels"],
	"leaf_charger_definition.gd": ["health", "attack_damage", "move_speed", "trigger_distance", "charge_speed", "charge_distance", "windup_seconds", "recovery_seconds", "attack_interval", "max_alive"],
	"lantern_spitter_definition.gd": ["health", "attack_damage", "shooting_range", "retreat_distance", "projectile_speed", "projectile_distance", "windup_seconds", "attack_interval", "max_alive"],
	"pot_brood_definition.gd": ["health", "move_speed", "attack_damage", "child_enemy_id", "split_delay", "max_alive"],
	"bell_frog_definition.gd": ["health", "move_speed", "boost_radius", "speed_multiplier", "boost_seconds", "windup_seconds", "attack_interval", "max_alive"],
	"ground_dressing_region.gd": ["enabled", "area_size", "density_multiplier", "extra_asset_manifest", "extra_density", "extra_scale"],
	"game_audio.gd": ["enabled", "max_voices", "important_reserve", "merge_window", "far_distance", "combat_volume_db", "music_volume_db"],
	"environment_dynamics.gd": ["enabled", "style_wind", "style_wind_tempo", "style_fireflies", "night_firefly_size", "region_wind", "region_fireflies", "region_blend_width", "transition_seconds", "battle_fireflies_enabled"],
	"spawn_visual_sample.gd": ["style", "runtime_switch_enabled", "style_key", "original_light_refinement_enabled", "original_light_preset", "pixel_art_enabled", "color_ramps_enabled", "color_palette", "grass_variation_enabled", "grass_variation_strength", "grass_variation_size", "value_sample_enabled", "value_sample_profile", "fog_post_enabled", "fog_post_presets"],
	"follow_camera.gd": ["distance", "pitch_degrees", "fov", "dof_amount", "focus_height", "ricochet_camera_settings"],
	"art_direction.gd": ["street_fill_shadows_enabled", "exposure", "contrast", "saturation", "bloom", "moon_energy", "ambient_energy", "hemisphere_fill_enabled", "hemisphere_sky_color", "hemisphere_ground_color", "fog_begin", "fog_end", "fog_curve", "fog_amount", "low_fog", "volumetric_density", "bloom_threshold", "bloom_floor", "vignette", "vignette_radius", "shadow_lift", "split_toning", "wet_surface_enabled", "wet_surface_minimum", "wet_surface_coverage", "wet_surface_roughness", "wet_surface_reflectivity", "wet_surface_ripple_strength", "wet_surface_ripple_speed"],
	"weather.gd": ["weather_mode", "rain_intensity", "ground_rain_enabled", "ground_splash_size", "ground_splash_density", "ground_splash_strength", "wind_strength", "blink_plant_strength", "blink_rain_strength", "rain_volume_db", "wind_volume_db"],
	"player.gd": ["speed", "blink_distance", "blink_cooldown", "jump_height", "ricochet_rules", "action_visuals", "sword_rules", "flight_trail_settings", "crowd_clearance_distance"],
	"fan_auto_attack.gd": ["damage", "attack_range", "attack_interval", "fan_angle", "effect_opacity", "skill_definition", "audio_enabled", "audio_volume_db", "hit_sound_limit"],
	"mirror_mark_auto_attack.gd": ["damage", "attack_range", "attack_interval", "flight_speed", "mark_duration", "reflection_limit", "match_player_pixel_density", "skill_definition"],
	"run_buffs.gd": ["definitions"],
	"growth_buff_definition.gd": ["bonus_per_level", "max_level", "bonus_cap", "diminishing_after", "breakthrough_every", "breakthrough_multiplier", "required_levels", "extra_effects"],
	"growth_buff_effect.gd": ["attribute", "bonus_per_level", "bonus_cap"],
	"combat_skill_definition.gd": ["levels"],
	"combat_skill_level.gd": ["parameters"],
	"wave_enemy_definition.gd": ["health", "move_speed", "attack_damage", "experience_reward", "health_growth_enabled"],
	"wave_melee_enemy_definition.gd": ["enemy_id", "health", "move_speed", "attack_damage", "experience_reward", "health_growth_enabled", "body_radius", "contact_distance", "knockback_multiplier", "population_cost", "max_alive"],
	"wave_population_rules.gd": ["simulation_mode", "simulation_enemy_count", "simulation_skills", "first_active_limit", "max_active", "max_wave_enemies", "max_population_cost", "role_limits", "surround_start_wave", "surround_max_fronts"],
	"simulation_skill_entry.gd": ["skill_definition", "skill_level"],
	"wave_spawn_entry.gd": ["mixed_horde", "enemy", "count", "batch_size", "start_delay", "interval", "spawn_zone_ids"],
	"wave_health_growth_rules.gd": ["start_wave", "bonus_per_wave", "minimum_multiplier", "maximum_multiplier"],
	"wave_prototype.gd": ["enemy_catalog", "population_rules", "health_growth_rules", "enemy_occlusion_outline_enabled", "waves", "endless_mode", "endless_enemies_per_wave", "endless_max_enemies", "endless_interval_reduction", "endless_min_spawn_interval", "max_active_enemies", "retry_key", "show_ui"],
	"wave_hud.gd": ["enabled", "font_size", "hint_font_size", "top_margin", "text_color"],
	"battle_area.gd": ["core_size", "loop_width", "opening_spawn_offset", "core_density", "edge_density"],
	"ground_dressing.gd": ["grass_density", "flower_density", "stable_shadows"],
	"terrain.gd": ["data", "paint_palette"],
	"bgm.gd": ["music_enabled", "music_volume_db", "playlists", "music_transition_time", "music_fade_time"],
	"bgm_track.gd": ["track_id", "track_title", "stream", "volume_db", "loop_crossfade"],
	"bgm_playlist.gd": ["context_id", "tracks", "play_order"],
	"experience_rules.gd": ["first_level_experience", "per_level_increase", "level_cap"],
	"loadout_ui.gd": ["ui_scale", "font_size"],
	"skill_hud.gd": ["slot_size", "slot_spacing", "screen_margin", "glow_strength"],
	"attribute_hud.gd": ["bar_width", "screen_margin", "glow_strength"],
	"experience_hud.gd": ["track_width", "follow_attributes", "attribute_gap", "background_opacity", "show_values", "flow_enabled", "flow_strength", "glint_strength"],
	"experience_pickup.gd": ["medium_threshold", "large_threshold", "gem_height", "bob_amplitude", "trail_length", "trail_brightness"],
	"item_quickbar.gd": ["slot_size", "slot_spacing", "background_opacity"],
	"ui_audio.gd": ["volume_db"],
	"core_feedback_audio.gd": ["enabled", "action_volume_db", "bounce_gain_db", "flight_audio_enabled", "flight_gain_db", "flight_low_speed_gain_db", "flight_reference_speed", "flight_volume_smoothing", "flight_fade_out_seconds", "enemy_volume_db", "feedback_volume_db", "sounds"],
}

var entries: Array[Dictionary] = []
var _resources := {}
var _descriptions := {}

func collect(scene: Node) -> Array[Dictionary]:
	entries.clear()
	_resources.clear()
	if scene: _visit(scene, scene)
	return entries

func _visit(node: Node, scene: Node) -> void:
	var path := String(scene.get_path_to(node))
	if node.get_script(): _object(node, path, node)
	for child in node.get_children():
		# 仅登记场景拥有的节点，跳过地形、建筑和 UI 的运行时生成对象。
		if child.owner != null: _visit(child, scene)

func category(filename: String, group: String) -> String:
	if filename == "scene_combat_configuration.gd": return "人物" if group == "人物基础战斗" else "战斗与成长"
	if filename == "scene_combat_binding.gd": return "战斗与成长"
	if filename == "aurora_sky.gd": return "视觉"
	if filename in ["core_feedback_audio.gd", "core_sound_bank.gd"]: return "声音"
	if filename == "ricochet_camera_settings.gd": return "视觉"
	if filename in ["damage_numbers.gd", "damage_number_style.gd"]: return "战斗与成长"
	if filename.begins_with("ricochet_storm"): return "战斗与成长"
	if filename in ["leaf_charger_definition.gd", "lantern_spitter_definition.gd", "pot_brood_definition.gd", "bell_frog_definition.gd", "creature_enemy.gd", "leaf_charger.gd", "lantern_spitter.gd", "pot_brood.gd", "bell_frog.gd", "mini_slime.gd"]: return "战斗与成长"
	if filename in ["environment_dynamics.gd", "environment_lantern.gd"]: return "视觉"
	if filename in ["game_audio.gd", "bgm.gd", "bgm_track.gd", "bgm_playlist.gd", "player_movement_audio.gd", "movement_sound_bank.gd", "ui_audio.gd", "ui_sound_bank.gd"] or "声音" in group or "音效" in group or "风声" in group: return "声音"
	if filename in ["character_skill_manager.gd", "player.gd", "player_blink.gd", "player_ricochet_rules.gd", "player_action_visuals.gd", "player_sword_rules.gd", "player_flight_trail_settings.gd", "character_lighting.gd"]: return "人物"
	if filename == "wave_hud.gd": return "UI"
	if filename.begins_with("wave_") or filename.begins_with("combat_skill_") or filename.begins_with("mirror_") or filename in ["fan_auto_attack.gd", "prism_ricochet_auto_attack.gd", "prism_ricochet_effect.gd", "slime.gd", "run_growth.gd", "run_skill_manager.gd", "run_skill_draft.gd", "run_buffs.gd", "growth_buff_definition.gd", "growth_buff_effect.gd", "experience_rules.gd", "experience_pickup.gd"]: return "战斗与成长"
	if filename in ["spawn_visual_sample.gd", "spawn_visual_preset.gd", "pixel_color_palette.gd", "value_lighting_profile.gd", "art_direction.gd", "weather.gd", "follow_camera.gd", "atmospheric_light.gd", "daylight_preview.gd", "map_effects.gd", "planar_water_reflection.gd"]: return "视觉"
	if filename in ["training_rules.gd", "loadout_catalog.gd", "equipment_definition.gd", "skill_definition.gd", "item_definition.gd"]: return "物品与规则"
	if filename.ends_with("_ui.gd") or filename.ends_with("_hud.gd") or filename in ["item_quickbar.gd", "inventory_book_page.gd", "growth_choice_card.gd", "growth_choice_option.gd"]: return "UI"
	return "地图与地编"

func _object(object: Object, path: String, node: Node) -> void:
	var script := object.get_script() as Script
	if not script: return
	var filename := script.resource_path.get_file()
	var group := "基础"
	var subgroup := ""
	# 非 @tool 脚本在编辑器中是占位实例；从脚本读取导出信息，避免遗漏人物和战斗参数。
	var properties: Array[Dictionary] = script.get_script_property_list()
	# FOV 是 Camera3D 内置属性，与脚本参数放在同一入口。
	if object is Camera3D:
		_add(object, path, node, filename, "构图", "fov")
	for info in properties:
		var usage: int = info.usage
		if usage & PROPERTY_USAGE_GROUP:
			group = info.name
			subgroup = ""
			continue
		if usage & PROPERTY_USAGE_SUBGROUP:
			subgroup = info.name
			continue
		if not usage & PROPERTY_USAGE_EDITOR: continue
		var property: String = info.name
		if object is Node and _bound_by_configuration(object, property): continue
		_add(object, path, node, filename, group + (" / " + subgroup if not subgroup.is_empty() else ""), property)
		var value: Variant = object.get(property)
		if value is Resource: _resource(value, path + " → " + LABELS.get(property, property), node)
		elif value is Array:
			for index in value.size():
				if value[index] is Resource: _resource(value[index], path + " → " + property + "[%d]" % index, node)
	if filename == "spawn_visual_sample.gd":
		for suffix in ["original", "lumina_day", "lumina_rain", "lumina_night"]:
			_resource(load("res://data/visual/spawn_" + suffix + ".tres"), "风格预设 → " + suffix, node)
	if filename == "wave_prototype.gd" and not _has_combat_configuration(node):
		for preset in ["horde_128", "horde_512", "stress_768"]:
			_resource(load("res://data/waves/population/" + preset + ".tres"), "怪潮数量预设 → " + preset, node)

func _has_combat_configuration(node: Node) -> bool:
	var current := node
	while current:
		if current.has_node("BattleConfiguration"): return true
		current = current.get_parent()
	return false

func _bound_by_configuration(node: Node, property: String) -> bool:
	if not _has_combat_configuration(node): return false
	var filename: String = node.get_script().resource_path.get_file()
	if filename == "player.gd": return property in ["ricochet_rules", "sword_rules", "action_visuals", "flight_trail_settings", "crowd_clearance_distance"]
	if filename == "wave_prototype.gd": return property in ["enemy_catalog", "default_enemy", "population_rules", "health_growth_rules", "waves", "endless_mode", "max_active_enemies", "batch_crowd_enabled", "native_chase_enabled", "slime_ground_movement_enabled"]
	if filename == "follow_camera.gd": return property == "ricochet_camera_settings"
	if filename == "run_growth.gd": return property in ["rules", "cards_per_draw", "rerolls_per_run"]
	if filename == "run_buffs.gd": return property == "definitions"
	if filename == "damage_numbers.gd": return property == "number_styles"
	if filename == "ricochet_storm.gd" and property in ["damage", "attack_interval", "trigger_radius", "spread_radius", "max_propagation_radius", "spread_layers", "targets_per_layer", "layer_interval"]: return true
	return property == "skill_definition" and node.get_parent() is WavePrototype

func _resource(resource: Resource, path: String, node: Node) -> void:
	if _resources.has(resource.get_instance_id()): return
	_resources[resource.get_instance_id()] = true
	if resource.get_script(): _object(resource, path, node)
	elif resource is ShaderMaterial:
		for info in resource.get_property_list():
			var property: String = info.name
			if not property.begins_with("shader_parameter/") or not info.usage & PROPERTY_USAGE_EDITOR: continue
			var name := property.trim_prefix("shader_parameter/")
			entries.append({"object": resource, "node": node, "property": property, "label": name, "category": "视觉",
				"group": "底层着色器（高级）", "path": path, "common": false,
				"description": "直接编辑材质；若此项由视觉、相机或天气控制，请优先调节对应控制节点。",
				"search": ("视觉 材质 着色器 " + path + " " + name).to_lower()})

func _add(object: Object, path: String, node: Node, filename: String, group: String, property: String) -> void:
	var label: String = SYSTEM_SWITCH_LABELS[filename] if property == "enabled" and SYSTEM_SWITCH_LABELS.has(filename) else LABELS.get(property, property)
	var section := category(filename, group)
	var description: String = _documentation(object.get_script()).get(property, "")
	entries.append({"object": object, "node": node, "property": property, "label": label, "category": section,
		"group": group, "path": path, "common": (property == "enabled" and SYSTEM_SWITCH_LABELS.has(filename)) or property in COMMON.get(filename, []) or (object is WaveEnemyDefinition and property in ["stun_duration_multiplier", "horde_weight"]) or (object is WaveMeleeEnemyDefinition and property in ["separation_radius", "separation_strength", "pursuit_lookahead", "pursuit_flank_strength"]),
		"description": description, "search": (section + " " + group + " " + path + " " + label + " " + property + " " + description).to_lower()})

func _documentation(script: Script) -> Dictionary:
	if _descriptions.has(script.resource_path): return _descriptions[script.resource_path]
	var descriptions := {}
	if script.get_base_script(): descriptions.merge(_documentation(script.get_base_script()))
	var pattern := RegEx.create_from_string("^@export[^\\n]*\\bvar\\s+(\\w+)")
	var comments := PackedStringArray()
	for line in FileAccess.get_file_as_string(script.resource_path).split("\n"):
		line = line.strip_edges()
		if line.begins_with("##"):
			comments.append(line.trim_prefix("##").strip_edges())
			continue
		var match := pattern.search(line)
		if match: descriptions[match.get_string(1)] = "\n".join(comments)
		if not line.is_empty(): comments.clear()
	_descriptions[script.resource_path] = descriptions
	return descriptions
