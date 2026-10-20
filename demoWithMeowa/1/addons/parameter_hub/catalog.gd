@tool
extends RefCounted

const SYSTEM_SWITCH_LABELS := {
	"run_growth.gd": "升级系统本地开关",
	"run_skill_draft.gd": "抽卡系统本地开关",
	"run_skill_manager.gd": "局内技能管理器本地开关",
}
const CATEGORIES := ["视觉", "人物", "战斗与成长", "地图与地编", "UI", "声音", "物品与规则"]
const LABELS := {
	"equipment_bonuses_enabled": "旧装备数值加成",
	"growth_rules": "成长与基础续航规则", "epic": "史诗解锁成长", "epic_every": "史诗选择等级间隔",
	"orbit_damage_reduction": "持续环绕减伤", "sword_heal_fraction": "每次剑术命中恢复生命比例", "sword_heal_cap": "剑术每秒恢复上限比例",
	"speed_damage_low": "动能增伤低速端", "speed_damage_high": "动能增伤高速端", "speed_damage_min_bonus": "低速增伤系数", "speed_damage_max_bonus": "高速增伤系数",
	"strike_speed_thresholds": "千手加刀速度门槛", "strike_speed_hysteresis": "千手速度切档余量", "maximum_strikes": "单次千手斩击上限", "additional_strike_damage_ratio": "千手追加刀伤害比例", "heavy_interval_multiplier": "重击攻击间隔倍率",
	"ui_sounds": "UI 音效配置", "actions": "UI 操作音效映射", "action_intervals": "UI 连续操作音效间隔",
	"player_access_enabled": "人物与背包玩家入口", "management_enabled": "技能栏管理入口",
	"rules_version": "计分规则版本", "common_points": "普通怪基础分", "special_points": "特殊怪基础分",
	"enemy_points": "怪物独立基础分", "performance_excluded": "仅给基础分的怪物", "wave_points": "清波基础分",
	"combo_enabled": "连杀倍率开关", "combo_thresholds": "连杀击杀门槛", "combo_multipliers": "连杀得分倍率",
	"combo_grace_seconds": "连杀宽限时间", "combo_decay_seconds": "连杀降档间隔",
	"burst_enabled": "成片奖励开关", "burst_thresholds": "成片击杀门槛", "burst_rewards": "成片固定奖励",
	"online_demo_enabled": "匿名试玩榜自动提交",
	"include_scene_props": "花坛与场景道具参与遮挡淡化",
	"occluded_opacity": "遮挡物保留不透明度", "detection_interval": "人物遮挡检测间隔",
	"occlusion_fade_seconds": "建筑淡出时间", "restore_seconds": "建筑恢复时间", "restore_delay": "解除遮挡保留时间",
	"ribbon_layered_enabled": "剑光分层流动笔触", "ribbon_brush": "剑光笔触贴图", "ribbon_noise": "剑光流动噪声",
	"ribbon_flow_speed": "剑光流动速度", "ribbon_distortion": "剑光笔触扰动", "ribbon_wake_strength": "剑光次级拖丝强度",
	"ribbon_spark_strength": "剑光飞散亮点强度", "ribbon_view_tilt": "剑光俯视显示倾角",
	"ribbon_visual": "原生剑光外观", "flight_ribbon_visual": "弹射环绕剑光外观", "ribbon_width": "剑光丝带宽度", "ribbon_degrees": "剑光丝带弧长",
	"ribbon_orbit_enabled": "剑光缺口圆环", "ribbon_orbit_secondary_strength": "环绕交错余迹强度", "ribbon_orbit_secondary_offset": "环绕交错余迹角度",
	"ribbon_inner_ratio": "剑光尾端贴身比例", "ribbon_pixel_size": "剑光笔触像素尺寸",
	"ribbon_blade_color": "剑光亮刃颜色", "ribbon_middle_color": "剑光过渡颜色", "ribbon_tail_color": "剑光拖尾颜色",
	"ribbon_emission": "剑光自发光强度", "ribbon_blade_enabled": "剑光亮刃层", "ribbon_trail_enabled": "剑光拖尾层", "ribbon_tail_seconds": "剑光独立消散时间",
	"meowa_visibility_strength": "剑光清晰强度",
	"meowa_stretch_enabled": "剑光动态拉伸", "meowa_stretch_strength": "剑光拉伸强度",
	"enemy_hit_reaction_enabled": "怪物受击身体反应", "enemy_hit_lean_degrees": "怪物受击倾斜幅度",
	"enemy_hit_recovery_seconds": "怪物受击回正时间",
	"hurt_particles_enabled": "人物受击红色像素粒子", "hurt_particle_count": "人物受击粒子数量",
	"hurt_particle_seconds": "人物受击粒子消散时间", "hurt_particle_spread_pixels": "人物受击粒子散开距离",
	"hurt_particle_size_pixels": "人物受击粒子原生像素尺寸", "hurt_particle_color": "人物受击粒子颜色",
	"hurt_screen_enabled": "人物受伤边缘红光", "hurt_screen_opacity": "受伤红光强度上限",
	"hurt_screen_seconds": "受伤红光消退时间", "hurt_screen_color": "受伤红光颜色",
	"hurt_camera_enabled": "人物受伤轻震", "hurt_shake_pixels": "普通受伤轻震幅度",
	"hurt_shake_seconds": "普通受伤轻震时间", "hurt_orbit_shake_pixels": "绕行受伤轻震幅度",
	"hurt_orbit_shake_seconds": "绕行受伤轻震时间", "hurt_shake_interval": "受伤轻震最短间隔",
	"enemy_hit_silhouette_enabled": "弹射命中局部剪影", "enemy_hit_silhouette_seconds": "命中剪影持续时间",
	"enemy_hit_silhouette_strength": "命中剪影强度", "enemy_hit_silhouette_interval": "同目标剪影最短间隔", "enemy_hit_silhouette_color": "命中剪影亮边颜色",
	"hit_debris_enabled": "定向命中碎屑开关", "hit_debris_count": "单次命中碎屑数量", "hit_debris_seconds": "命中碎屑存留时间",
	"hit_debris_interval": "同目标碎屑最短间隔", "kill_impact_enabled": "击杀定格与曲线震动",
	"hit_debris_speed_multiplier": "命中碎屑速度倍率", "kill_slash_enabled": "击杀长斩痕开关",
	"kill_slash_texture": "击杀长斩痕原生贴图", "kill_slash_seconds": "击杀长斩痕持续时间", "kill_slash_interval": "击杀长斩痕最短间隔",
	"kill_hitstop_seconds": "击杀世界短顿时间", "kill_hitstop_interval": "击杀重音最短间隔",
	"sword_hit_impact_enabled": "普攻命中短顿与冲击开关", "sword_hitstop_seconds": "普攻命中短顿时间",
	"sword_hit_impact_interval": "普攻命中重音最短间隔", "sword_hit_shake_seconds": "普攻命中震动时间", "sword_hit_shake_pixels": "普攻命中震动像素幅度",
	"kill_slow_tail_seconds": "击杀定格后慢放时间", "kill_shake_seconds": "击杀曲线震动时间", "kill_shake_pixels": "击杀曲线震动像素幅度",
	"kill_shot_enabled": "群杀缓慢推进开关", "kill_shot_seconds": "群杀推进总时长", "kill_shot_zoom_scale": "群杀推进距离比例",
	"kill_shot_minimum_kills": "群杀推进最低击杀数", "kill_shot_group_window": "群杀推进统计窗口",
	"kill_shot_enter_seconds": "群杀缓慢推进时间", "kill_shot_interval": "群杀推进最短间隔",
	"orbit_focus_enabled": "持续环绕专属取景", "orbit_lead_retention": "环绕切向前视保留比例",
	"orbit_focus_weight": "环绕怪群参照权重", "orbit_focus_max_distance": "环绕参照最大采样距离",
	"orbit_settle_seconds": "环绕取景平滑时间", "orbit_pullback_ratio": "环绕适量展开取景比例",
	"orbit_shot_enabled": "环绕近景与进出特写开关", "orbit_enter_magnification": "入圈特写放大倍数",
	"orbit_hold_magnification": "正常环绕保持放大倍数", "orbit_closeup_enter_seconds": "环绕特写推近时间",
	"orbit_closeup_exit_seconds": "离圈近景恢复时间",
	"orbit_closeup_exit_hold_seconds": "离圈近景停留时间",
	"orbit_shot_offset_ratio": "环绕进出弧形运镜幅度", "orbit_shot_pitch_degrees": "环绕进出特写俯角幅度",
	"orbit_shot_seconds": "入圈特写收稳与曲线总时长",
	"orbit_shot_interval": "环绕进出特写共用间隔", "orbit_exit_minimum_seconds": "出圈特写最低环绕时长",
	"combat_beat_enabled": "连续攻击与清群镜头重音", "combat_beat_pixels": "清群定向冲击像素",
	"combat_beat_seconds": "清群冲击持续时间", "combat_beat_interval": "清群镜头重音最短间隔",
	"combat_pullback_ratio": "清群瞬间展开取景比例",
	"combat_readability_enabled": "持续攻击视觉层次", "combat_contact_frames": "飞行剑伤命中原生帧",
	"feedback_prewarm_deaths": "死亡反馈预热数量", "feedback_prewarm_contacts": "命中反馈预热数量",
	"combat_contact_seconds": "飞行剑伤短闪时间", "combat_sword_body_opacity": "飞行刀锋白刃存在感",
	"combat_residue_opacity": "旧刀光余迹保留亮度", "combat_death_focus_seconds": "新死亡优先表现时间",
	"flight_speed_camera_enabled": "滑行速度镜头开关", "flight_charge_focus_enabled": "高速延续满蓄视觉开关",
	"flight_charge_focus_ratio": "高速保留满蓄视觉比例", "flight_pullback_ratio": "旧式速度镜头额外拉远比例",
	"flight_pitch_drop": "旧式速度镜头压低角度", "flight_speed_smoothing": "滑行镜头速度响应时间",
	"kill_audio_rules": "击杀声音反馈配置", "group_window": "群杀声音统计窗口",
	"balance": "地图默认战斗混音", "gains_db": "事件默认音量补偿", "priorities": "事件播放优先级",
	"intervals": "事件跨来源最短间隔", "voice_limits": "事件同时播放上限",
	"common_hit_enabled": "通用命中随机音效", "hit_material_layer_enabled": "命中混合轻材质层", "hit_material_gain_db": "命中材质层相对音量",
	"group_radius": "群杀声音合并半径", "group_threshold": "群杀强调最低数量",
	"large_group_threshold": "厚重群杀声音数量", "group_cooldown": "群杀重音最短间隔",
	"group_gain_db": "群杀重音相对音量", "air_gain_db": "死亡抛飞气流相对音量",
	"landing_gain_db": "死亡落地相对音量", "duck_seconds": "群杀声音退让恢复时间",
	"motion_feedback_enabled": "弹射人物惯性倾斜开关", "flight_lean_degrees": "飞行人物倾斜幅度",
	"motion_reference_speed": "人物运动表现参考速度", "impact_lean_hold": "反弹保留入射姿态时间",
	"impact_lean_turn": "反弹转向出射姿态时间", "lean_return_seconds": "人物倾斜回稳时间",
	"departure_airflow_enabled": "反弹出射气流开关", "departure_airflow_texture": "出射气流原生像素素材",
	"departure_airflow_seconds": "反弹后气流生成时段", "departure_airflow_lifetime": "单段出射气流存留时间",
	"departure_airflow_spacing": "出射气流沿途间距", "departure_airflow_opacity": "出射气流透明度",
	"surface_wave_enabled": "反弹面能量扩散开关", "surface_wave_radius": "反弹面扩散半径",
	"surface_wave_texture": "反弹面冲击波纹理",
	"surface_wave_seconds": "反弹面扩散时长", "surface_wave_energy": "反弹面扩散亮度",
	"speed_rim_enabled": "旧速度描边对照开关", "speed_rim_strength": "旧速度描边亮度",
	"speed_rim_width_pixels": "速度轮廓原生像素宽度", "speed_rim_min_speed": "速度气流起效速度",
	"speed_rim_color": "速度轮廓颜色",
	"speed_flow_enabled": "贴身速度气流开关", "speed_flow_texture": "速度气流原生纹理",
	"speed_flow_texture_region": "速度气流纹理采样区域",
	"speed_flow_mode": "速度气流表现方式",
	"speed_flow_opacity": "速度气流透明度", "speed_flow_length": "气流掠过长度",
	"speed_flow_lifetime": "速度气流短尾存留时间", "speed_flow_radius": "速度气流身体留白半径",
	"bounce_rhythm_enabled": "反弹残影节奏开关", "bounce_echo_rebuild_seconds": "出射残影重建时间",
	"bounce_echo_fade_seconds": "入射残影收尾时间",
	"impact_shot_enabled": "碰撞镜头反馈开关", "impact_shot_curve": "单段回弹曲线（分层关闭时）", "impact_shot_seconds": "碰撞机位段时长",
	"impact_split_enabled": "撞击与出射分层开关", "impact_punch_pixels": "撞击短震像素", "impact_punch_seconds": "撞击短震时间",
	"impact_shot_offset_ratio": "碰撞构图偏移比例", "impact_shot_yaw_degrees": "碰撞临时偏航幅度",
	"impact_shot_roll_degrees": "碰撞临时侧倾幅度", "impact_shot_pullback_ratio": "碰撞释放拉开比例",
	"impact_reference_speed": "碰撞镜头法向参考速度",
	"charge_release_handoff_enabled": "蓄满到发射连续交接开关", "charge_release_pitch_seconds": "发射后俯角恢复时间",
	"charge_release_framing_seconds": "发射前视构图交接时间",
	"charge_release_burst": "发射镜头前段展开力度", "charge_direction_bias_ratio": "满蓄前方留白比例",
	"launch_release_enabled": "发射画面与声音释放编排", "direction_focus_lift": "满蓄前方通道轻提亮",
	"launch_audio_hold_seconds": "发射主音背景退让保持", "launch_audio_return_seconds": "发射后背景音恢复时间",
	"launch_release_audio_enabled": "发射主音与气流衔接", "launch_full_gain_db": "满蓄发射声音增益",
	"launch_wind_entry_seconds": "发射后飞行气流渐入时间", "launch_wind_start_gain_db": "发射瞬间气流音量退让",
	"direction_focus_enabled": "满蓄方向聚焦开关", "direction_focus_length": "满蓄前方清晰通道长度",
	"direction_focus_half_width": "满蓄清晰通道半宽", "direction_focus_blur_pixels": "满蓄两侧与身后柔化强度",
	"direction_focus_release_seconds": "未延续满蓄时方向聚焦退去时间",
	"charge_staging_enabled": "蓄力分段运镜开关", "charge_pitch_drop": "蓄力压低俯角幅度",
	"charge_arc_ratio": "蓄力中段横移比例", "charge_full_punch_ratio": "满蓄单次距离挤压比例",
	"charge_full_settle_seconds": "满蓄光点短暂停留时间",
	"edge_darken": "蓄力外围压暗强度", "edge_desaturation": "蓄力外围降饱和度",
	"clear_radius": "蓄力中心清晰半径", "gather_seconds": "蓄力场景反馈聚拢时间", "release_seconds": "蓄力场景反馈回退时间",
	"airflow_radius": "蓄力局部气流半径", "plant_pull": "蓄力草木聚拢幅度", "rain_pull": "蓄力雨丝聚拢幅度",
	"music_duck_db": "蓄力音乐临时退让", "ambience_duck_db": "蓄力风雨临时退让",
	"charge_drama_enabled": "蓄力持续慢放", "charge_drama_start_fraction": "蓄力慢放开始进度",
	"charge_drama_slow_scale": "蓄力慢放速度比例", "charge_drama_enter_seconds": "蓄力慢放进入时间",
	"charge_drama_fade_seconds": "蓄力场景强调淡入淡出时间",
	"full_slow_enabled": "满蓄真实慢动作对照开关", "full_slow_scale": "满蓄慢动作速度比例", "full_slow_seconds": "满蓄慢动作真实时长",
	"orbit_slow_enabled": "持续环绕慢动作开关", "orbit_slow_scale": "环绕慢动作速度比例",
	"orbit_slow_enter_seconds": "环绕慢动作进入真实时长", "orbit_slow_exit_seconds": "环绕慢动作脱离真实时长",
	"bounce_slow_enabled": "建筑蹬墙短慢动作开关", "bounce_slow_scale": "蹬墙慢动作速度比例",
	"bounce_slow_enter_seconds": "蹬墙慢动作进入真实时长", "bounce_slow_hold_seconds": "蹬墙慢动作保持真实时长",
	"bounce_slow_exit_seconds": "蹬墙慢动作恢复真实时长", "bounce_slow_interval": "蹬墙慢动作最短触发间隔",
	"preview_on_direct_run": "直接运行地图预览入场", "sky_extra_distance": "入场远空额外距离",
	"sky_extra_height": "入场远空额外高度", "sky_lateral_offset": "入场远空侧向偏移", "sky_view_pitch": "入场天空起始视角",
	"arrival_ratio": "入场运镜时段占比", "camera_sweep_degrees": "入场水平绕转角度", "camera_bank_degrees": "入场左右侧倾幅度",
	"fog_opacity": "入场雾团整体强度", "fog_flow_speed": "入场云雾流速", "volume_density": "入场体积雾浓度",
	"fog_retreat_distance": "散雾向外退开距离", "fog_curl_strength": "入场云雾翻卷强度",
	"cloud_bank_scale": "入场局部体积云尺寸比例", "cloud_bank_density_ratio": "入场局部体积云密度比例",
	"wisp_opacity": "入场近景薄雾强度", "wisp_depth_bulge": "入场薄雾曲面起伏",
	"building_atmosphere_enabled": "入场建筑透雾与柔边开关", "building_light_gain": "入场已有灯窗发光增益",
	"fog_self_emission": "入场云雾中性自发光", "mist_light_response": "入场云片透灯强度", "mist_light_threshold": "入场透灯亮部阈值",
	"building_edge_softness_pixels": "入场建筑轮廓模糊半径", "building_edge_blur_strength": "入场建筑轮廓虚化强度",
	"emission_fog_enabled": "入场建筑发光雾散射开关", "emission_fog_strength": "入场材质发光散射强度",
	"emission_fog_radius": "入场发光散射半径", "emission_fog_max_lights": "入场雾散射源上限", "emission_fog_refresh_seconds": "入场发光控制刷新间隔",
	"traversal_audio_enabled": "入场穿雾声音开关", "traversal_sound": "入场穿梭音源", "traversal_volume_db": "入场穿梭音量",
	"opening_seconds": "首波开战演出时长", "next_wave_seconds": "后续开战演出时长", "clear_seconds": "清波演出时长",
	"animated_opening_enabled": "B 版开战动态大字开关", "opening_title_size": "开战波次数字号",
	"opening_title_top_ratio": "开战大字纵向位置", "opening_title_enter_seconds": "开战文字切入落定时长",
	"opening_title_exit_seconds": "开战文字退场时长", "opening_title_travel_pixels": "开战文字切入距离",
	"compact_clear_enabled": "清波简洁收尾与底部休整提示", "clear_title_size": "清波波次数字号",
	"clear_title_enter_seconds": "清波文字淡入时长", "clear_title_exit_seconds": "清波文字淡出时长",
	"rest_hint_font_size": "底部休整提示字号", "rest_hint_bottom_margin": "休整提示离画面底部距离",
	"finish_shot_enabled": "最后一击镜头开关", "finish_shot_seconds": "最后一击镜头时长", "finish_slow_scale": "最后一击世界速度", "finish_zoom_scale": "最后一击推近距离比例", "finish_contrast": "最后一击剪影重音",
	"battle_frame": "开战标题素材", "clear_frame": "清波标题素材", "pulse_texture": "地面亮纹素材",
	"banner_width": "波次标题宽度", "top_ratio": "波次标题纵向位置", "title_color": "标题文字颜色",
	"battle_color": "开战强调色", "clear_color": "清波强调色", "ground_pulse_enabled": "波次地面亮纹",
	"battle_pulse_radius": "开战亮纹半径", "clear_pulse_radius": "清波亮纹半径", "pulse_opacity": "波次亮纹透明度", "edge_strength": "波次边缘氛围强度",
	"spotlight_color": "入场聚光颜色", "spotlight_energy": "入场人物聚光亮度", "spotlight_fog_energy": "入场雾中光束强度",
	"spotlight_height": "入场聚光高度", "spotlight_angle": "入场聚光半角", "allow_skip": "允许 Esc 跳过入场",
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
	"orbit_speed_ratio": "环绕实际移速比例", "orbit_enter_seconds": "进入环绕减速时间", "orbit_exit_seconds": "脱离环绕回速时间",
	"eccentric_minimum_members": "首次环绕最少成员数",
	"show_bounce_effect": "碰墙反弹特效开关", "bounce_frames": "反弹火花原生帧",
	"bounce_anchor_pixels": "反弹火花碰点像素锚点", "bounce_duration": "反弹火花持续时间",
	"bounce_particles_enabled": "反弹像素粒子开关", "bounce_particle_count": "反弹粒子数量",
	"bounce_particle_speed": "反弹粒子速度", "bounce_particle_seconds": "反弹粒子寿命",
	"bounce_opacity": "反弹火花透明度", "bounce_energy": "反弹火花亮度", "bounce_height": "反弹火花显示高度",
	"show_fire_trail": "弹射地面火带开关", "fire_trail_width": "地面火带宽度",
	"fire_trail_fresh_seconds": "火带新生亮火时间", "fire_trail_burn_seconds": "火带持续燃烧时间",
	"fire_trail_ember_seconds": "火带暗红余烬时间", "fire_trail_energy": "地面火带亮度",
	"fire_trail_pixels_per_meter": "火带世界像素密度",
	"fire_trail_flow_enabled": "火带流动笔触开关", "fire_trail_spark_height": "火带火星离地高度",
	"fire_trail_spark_spacing": "火带火星候选间距", "fire_trail_flow_strength": "火带笔触卷曲强度",
	"fire_trail_brush": "火带 Meowa 笔触", "fire_trail_brush_region": "火带笔触采样区域", "fire_trail_flow_speed": "火带流动与爆发节奏",
	"fire_trail_spark_amount": "火带少量飞火密度", "fire_trail_body_clearance_pixels": "火带人物轮廓留白",
	"melee_death_enabled": "近身与奔雷击杀击飞开关", "melee_death_seconds": "近身击飞消散时长",
	"melee_death_distance": "近身击飞基础距离", "melee_death_height": "近身击飞腾空高度",
	"melee_death_spin_degrees": "近身击飞翻转角度",
	"melee_death_near_distance": "近身死亡击飞距离门槛", "melee_death_reference_speed": "死亡击飞参考人物速度",
	"melee_death_min_strength": "静止击杀最低击飞力度", "melee_death_storm_retention": "奔雷每层死亡击飞保留比例",
	"melee_death_hit_pause": "死亡局部短顿时间", "melee_death_air_seconds": "死亡快速抛飞时长",
	"melee_death_impact_frames": "死亡爆点原生帧", "melee_death_impact_seconds": "死亡爆点持续时间",
	"melee_death_trail_enabled": "死亡飞行残影与碎屑", "melee_death_landing_enabled": "死亡落地弹跳与烟尘",
	"melee_death_bounce_height": "死亡落地小弹跳高度", "melee_death_slide_distance": "死亡落地滑出距离",
	"melee_death_cluster_enabled": "附近密集击杀集中爆点",
	"death_impact_gain_db": "近身与奔雷死亡声增益",
	"playlists": "BGM 场合曲池", "default_context": "默认音乐场合", "music_transition_time": "曲间切换时长",
	"follow_battle_session": "音乐跟随波次状态", "exploration_context": "准备与结算曲池", "combat_context": "战斗与波间曲池",
	"track_id": "曲目标识", "track_title": "曲目名称", "stream": "音乐文件", "loop_crossfade": "曲尾衔接时长",
	"context_id": "播放场合标识", "tracks": "曲池曲目", "play_order": "曲池播放顺序",
	"music_enabled": "背景音乐开关", "music_stream": "旧场景单曲", "music_fade_time": "音乐开关淡化时长",
	"music_loop_crossfade": "旧单曲循环衔接时长", "music_bus": "音乐输出总线",
	"crowd_clearance_distance": "人物周身留白距离（额外）",
	"pursuit_throttle_threshold": "普通追击降频启用数量（0关闭）",
	"pursuit_lookahead": "追击路线前视距离", "pursuit_flank_strength": "追击侧向让行强度",
	"patch_enabled": "成片电涌开关", "patch_duration": "成片电涌停留时间", "patch_opacity": "成片电涌强度", "patch_height": "成片电涌高度",
	"mixed_horde": "自动目录混合怪潮", "horde_weight": "怪潮出场权重（0 排除）",
	"action_volume_db": "核心动作音量", "enemy_volume_db": "怪物反馈音量", "feedback_volume_db": "成长与波次音量",
	"bounce_gain_db": "人物反弹碰撞音量增益",
	"water_boundary_reflection_enabled": "人物遇水边界反弹",
	"flight_audio_enabled": "弹射动能气流开关", "flight_gain_db": "弹射气流音量增益",
	"charge_energy_audio_enabled": "旧蓄力起手与循环开关",
	"charge_progress_audio_enabled": "蓄力声音渐强开关", "charge_start_gain_db": "蓄力起始音量增益",
	"charge_full_gain_db": "蓄满循环音量增益", "charge_start_pitch": "蓄力起始音高",
	"charge_full_pitch": "蓄满循环音高", "charge_ready_gain_db": "满蓄提示音量增益",
	"flight_low_speed_gain_db": "低速气流额外音量", "flight_reference_speed": "气流满音量参考速度",
	"flight_volume_smoothing": "气流音量平滑时间", "flight_fade_out_seconds": "停止弹射气流淡出时间",
	"low_health_ratio": "濒危提示血量比例", "pickup_interval": "经验音提示间隔",
	"propagation_sounds": "雷潮传导音源", "propagation_layer_gain_db": "雷潮逐层音量变化",
	"ricochet_camera_settings": "弹射镜头反馈配置", "launch_lag_seconds": "起射镜头滞后时间",
	"launch_follow_fraction": "起射镜头跟随比例", "lookahead_ratio": "飞行镜头前视比例",
	"lead_settle_seconds": "飞行前视过渡时间", "bounce_inertia_seconds": "反弹镜头惯性时间",
	"return_seconds": "弹射镜头归位时间", "max_offset_ratio": "新增镜头偏移上限",
	"charge_focus_enabled": "蓄力聚焦镜头开关", "charge_zoom_ratio": "蓄力镜头最大推近比例",
	"charge_onset_ratio": "蓄力起手推近份额", "charge_focus_seconds": "蓄力推近与聚焦平滑时间",
	"charge_release_seconds": "发射镜头拉开时间", "charge_cancel_seconds": "取消蓄力镜头回位时间",
	"charge_full_shake_enabled": "满蓄单次定向轻震开关", "charge_full_shake_pixels": "满蓄定向轻震像素强度",
	"charge_full_shake_seconds": "满蓄定向轻震持续时间",
	"charge_tremor_enabled": "蓄力混合波颤动开关", "charge_tremor_pixels": "蓄力颤动最大像素幅度",
	"charge_tremor_start_hz": "蓄力颤动起始频率", "charge_tremor_full_hz": "蓄力颤动满蓄频率",
	"charge_tremor_release_seconds": "蓄力颤动松手收尾时间",
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
	"normal_stationary_enabled": "普攻前摇与扫刃站定", "normal_windup_seconds": "站定普攻前摇时间",
	"normal_slash_alignment_enabled": "普攻动作与刀光对齐", "normal_attack_frame_breaks": "普攻动画起手与斩击结束进度",
	"ribbon_hilt_enabled": "刀光腰前起刀", "ribbon_hilt_offset": "刀光内端持剑侧与前后偏移",
	"ribbon_hilt_width_ratio": "刀光内端宽度比例", "ribbon_height_offset": "刀光腰前高度偏移",
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
	"clockwise": "人物正撞绕群顺时针旋向（兼容拨怪）", "push_height_tolerance": "怪群接触允许高差", "bounce": "人物反弹动画槽", "normal_attack": "普通攻击动画",
	"charge": "蓄力动画", "flight": "弹射飞行动画", "flight_attack": "飞行攻击动画", "recovery": "弹射收尾动画",
	"placeholder_attack_seconds": "缺少攻击素材的占位时长", "show_aim_guide": "显示碰撞路线预览", "show_push_ring": "显示拨怪作用圆",
	"preview_show_target": "预览首个目标提示", "preview_bounces": "仅预览显示的反弹次数", "preview_distance": "预览路线最长距离",
	"preview_followup_distance": "首次接触后的预测长度",
	"preview_color": "预览路线颜色", "preview_opacity": "预览路线透明度", "preview_line_width_pixels": "预览虚线宽度（人物原生像素）",
	"show_charge_effect": "显示蓄力特效", "charge_radius_pixels": "蓄力环半径（人物原生像素）",
	"charge_effect_opacity": "蓄力特效透明度", "charge_effect_energy": "蓄力特效亮度",
	"charge_dynamic_enabled": "蓄力视觉渐强开关", "charge_ring_contraction": "蓄力圆弧收紧比例",
	"charge_mote_speed_gain": "满蓄光点汇聚速度倍率", "charge_mote_count": "蓄力汇聚光点数量",
	"charge_wind_enabled": "绕身聚力风开关", "charge_wind_texture": "聚力风原生像素纹理",
	"charge_wind_radius_pixels": "聚力风上沿／外半径（人物原生像素）", "charge_wind_height_pixels": "聚力风高度（人物原生像素）",
	"charge_wind_opacity": "聚力风不透明度", "charge_wind_cycle_seconds": "聚力风基础循环时长",
	"charge_wind_funnel_enabled": "聚力风下窄上宽模式", "charge_wind_bottom_radius_pixels": "聚力风下沿半径（人物原生像素）",
	"charge_wind_width_pixels": "聚力风带厚度（人物原生像素）", "charge_wind_turns": "聚力风螺旋圈数",
	"charge_wind_full_speed_multiplier": "聚力风满蓄速度倍率",
	"charge_wind_layers": "人物风场层数", "charge_wind_trail_span": "人物风场风带延伸比例",
	"charge_wind_body_clearance_pixels": "人物风场轮廓间隙（原生像素）",
	"charge_wind_audio_enabled": "蓄力聚力风声开关", "charge_wind_gain_db": "满蓄聚力风声增益",
	"charge_wind_energy_duck_db": "聚力风开启时原能量声退让", "charge_wind_fade_out_seconds": "聚力风声松手淡出时间",
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
	"follow_enabled": "镜头跟随人物", "edge_pan_speed": "鼠标边缘移动速度", "edge_pan_margin": "鼠标边缘触发宽度",
	"follow_max_speed": "跟随速度上限", "follow_max_lag": "最大跟随落后距离",
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
	"independent_weather": "晴雨独立于画面风格", "weather_mode": "晴雨模式", "rain_intensity": "雨量比例", "rain_amount": "雨丝数量", "wind_strength": "风力",
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
	"spawn_shadow_settings": "怪物落点剪影预告",
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
	"run_score.gd": ["rules", "online_demo_enabled"],
	"run_score_rules.gd": ["common_points", "special_points", "enemy_points", "performance_excluded", "wave_points", "combo_enabled", "combo_thresholds", "combo_multipliers", "combo_grace_seconds", "combo_decay_seconds", "burst_enabled", "burst_thresholds", "burst_rewards"],
	"building_occlusion.gd": ["enabled", "include_scene_props", "occluded_opacity", "detection_interval", "occlusion_fade_seconds", "restore_seconds", "restore_delay"],
	"character_lighting.gd": ["lighting_enabled", "light_wrap", "top_light_response", "back_rim_strength", "local_light_response", "normal_mapping_enabled", "normal_mapping_strength"],
	"character_spotlight.gd": ["fill_enabled", "fill_color", "fill_energy", "fill_height", "fill_front_offset", "fill_side_offset", "fill_target_height", "fill_angle"],
	"kill_audio_rules.gd": ["enabled", "group_window", "group_radius", "group_threshold", "large_group_threshold", "group_cooldown", "group_gain_db", "air_gain_db", "landing_gain_db", "music_duck_db", "ambience_duck_db", "duck_seconds"],
	"charge_presentation.gd": ["bounce_slow_enabled", "bounce_slow_scale", "bounce_slow_enter_seconds", "bounce_slow_hold_seconds", "bounce_slow_exit_seconds", "bounce_slow_interval", "charge_drama_enabled", "charge_drama_start_fraction", "charge_drama_slow_scale", "charge_drama_enter_seconds", "charge_drama_fade_seconds", "orbit_slow_enabled", "orbit_slow_scale", "orbit_slow_enter_seconds", "orbit_slow_exit_seconds", "enabled", "edge_darken", "edge_desaturation", "clear_radius", "gather_seconds", "release_seconds", "direction_focus_enabled", "direction_focus_length", "direction_focus_half_width", "direction_focus_blur_pixels", "direction_focus_release_seconds", "direction_focus_lift", "launch_release_enabled", "launch_audio_hold_seconds", "launch_audio_return_seconds", "airflow_radius", "plant_pull", "rain_pull", "music_duck_db", "ambience_duck_db", "full_slow_enabled", "full_slow_scale", "full_slow_seconds"],
	"world_entry.gd": ["settings", "preview_on_direct_run"],
	"wave_presentation.gd": ["enabled", "settings"],
	"wave_presentation_settings.gd": ["compact_clear_enabled", "clear_title_size", "clear_title_enter_seconds", "clear_title_exit_seconds", "rest_hint_font_size", "rest_hint_bottom_margin", "animated_opening_enabled", "opening_title_size", "opening_title_top_ratio", "opening_title_enter_seconds", "opening_title_exit_seconds", "opening_title_travel_pixels", "opening_seconds", "next_wave_seconds", "clear_seconds", "finish_shot_enabled", "finish_shot_seconds", "finish_slow_scale", "finish_zoom_scale", "finish_contrast", "banner_width", "top_ratio", "ground_pulse_enabled", "battle_pulse_radius", "clear_pulse_radius", "pulse_opacity", "edge_strength"],
	"world_entry_settings.gd": ["enabled", "duration_seconds", "arrival_ratio", "camera_sweep_degrees", "camera_bank_degrees", "sky_extra_distance", "sky_extra_height", "sky_view_pitch", "traversal_audio_enabled", "traversal_volume_db", "fog_opacity", "volume_density", "fog_retreat_distance", "fog_curl_strength", "cloud_bank_scale", "cloud_bank_density_ratio", "wisp_opacity", "wisp_depth_bulge", "building_atmosphere_enabled", "building_light_gain", "fog_self_emission", "mist_light_response", "mist_light_threshold", "building_edge_softness_pixels", "building_edge_blur_strength", "emission_fog_enabled", "emission_fog_strength", "emission_fog_radius", "emission_fog_max_lights", "emission_fog_refresh_seconds", "spotlight_energy", "spotlight_fog_energy"],
	"environment_lantern.gd": ["fill_shadows_enabled"],
	"scene_combat_binding.gd": ["configuration"],
	"scene_combat_configuration.gd": ["equipment_bonuses_enabled", "ricochet_rules", "sword_rules", "population_rules", "pursuit_throttle_threshold", "spawn_shadow_settings", "waves", "max_active_enemies", "endless_mode", "storm_damage", "storm_attack_interval", "crowd_clearance_distance"],
	"wave_spawn_shadow_settings.gd": ["enabled", "warning_seconds", "fade_seconds", "shadow_opacity", "rim_opacity", "footprint_scale", "footprint_depth_ratio", "contraction"],
	"aurora_sky.gd": ["enabled", "sky_strength", "reflection_strength", "flow_speed", "green_color", "blue_color", "purple_color", "pink_color", "reflection_regions"],
	"ricochet_camera_settings.gd": ["orbit_shot_enabled", "orbit_shot_offset_ratio", "orbit_shot_pitch_degrees", "orbit_enter_magnification", "orbit_hold_magnification", "orbit_closeup_enter_seconds", "orbit_closeup_exit_hold_seconds", "orbit_closeup_exit_seconds", "orbit_shot_seconds", "orbit_shot_interval", "orbit_exit_minimum_seconds", "orbit_focus_enabled", "orbit_lead_retention", "orbit_focus_weight", "orbit_focus_max_distance", "orbit_settle_seconds", "orbit_pullback_ratio", "combat_beat_enabled", "combat_beat_pixels", "combat_beat_seconds", "combat_beat_interval", "combat_pullback_ratio", "flight_speed_camera_enabled", "flight_charge_focus_enabled", "flight_charge_focus_ratio", "flight_reference_speed", "flight_pullback_ratio", "flight_pitch_drop", "flight_speed_smoothing", "impact_shot_enabled", "impact_split_enabled", "impact_punch_pixels", "impact_punch_seconds", "impact_shot_curve", "impact_shot_seconds", "impact_shot_offset_ratio", "impact_shot_yaw_degrees", "impact_shot_roll_degrees", "impact_shot_pullback_ratio", "impact_reference_speed", "enabled", "charge_tremor_enabled", "charge_tremor_pixels", "charge_tremor_start_hz", "charge_tremor_full_hz", "charge_tremor_release_seconds", "charge_focus_enabled", "charge_zoom_ratio", "charge_onset_ratio", "charge_focus_seconds", "charge_release_seconds", "charge_cancel_seconds", "charge_full_shake_enabled", "charge_full_shake_pixels", "charge_full_shake_seconds", "charge_staging_enabled", "charge_pitch_drop", "charge_arc_ratio", "charge_full_punch_ratio", "charge_release_handoff_enabled", "charge_release_burst", "charge_direction_bias_ratio", "charge_release_pitch_seconds", "charge_release_framing_seconds", "launch_lag_seconds", "lookahead_ratio", "lead_settle_seconds", "bounce_inertia_seconds", "return_seconds", "max_offset_ratio", "impact_shake_pixels"],
	"damage_numbers.gd": ["enabled", "number_styles", "number_stack_columns", "number_stack_spacing", "number_idle_limit"],
	"damage_number_style.gd": ["number_font", "number_font_size", "number_color", "number_lifetime", "rise_pixels", "drift_pixels", "pop_scale"],
	"ricochet_storm.gd": ["enabled", "damage", "attack_interval", "trigger_radius", "spread_radius", "max_propagation_radius", "spread_layers", "targets_per_layer", "layer_interval", "skill_definition", "effect_scene"],
	"ricochet_storm_effect.gd": ["pixel_size", "arc_duration", "reveal_seconds", "sky_height", "effect_energy", "arc_energy_multiplier", "effect_opacity", "impact_frames", "patch_enabled", "patch_duration", "patch_opacity", "patch_height"],
	"player_flight_trail_settings.gd": ["bounce_rhythm_enabled", "bounce_echo_rebuild_seconds", "bounce_echo_fade_seconds", "enabled", "flight_echo_count", "flight_echo_spacing", "flight_trail_color", "flight_echo_saturation", "flight_echo_brightness", "flight_trail_max_length", "flight_trail_lifetime", "flight_trail_opacity", "flight_trail_energy"],
	"sword_ribbon_visual.gd": ["ribbon_hilt_enabled", "ribbon_hilt_offset", "ribbon_hilt_width_ratio", "ribbon_height_offset", "ribbon_orbit_enabled", "ribbon_orbit_secondary_strength", "ribbon_orbit_secondary_offset", "ribbon_layered_enabled", "ribbon_brush", "ribbon_noise", "ribbon_flow_speed", "ribbon_distortion", "ribbon_wake_strength", "ribbon_spark_strength", "ribbon_view_tilt", "ribbon_width", "ribbon_degrees", "ribbon_inner_ratio", "ribbon_pixel_size", "ribbon_blade_color", "ribbon_middle_color", "ribbon_tail_color", "ribbon_emission", "ribbon_blade_enabled", "ribbon_trail_enabled", "ribbon_tail_seconds"],
	"player_sword_rules.gd": ["normal_slash_alignment_enabled", "normal_attack_frame_breaks", "normal_stationary_enabled", "normal_windup_seconds", "ribbon_visual", "flight_ribbon_visual", "meowa_visibility_strength", "meowa_stretch_enabled", "meowa_stretch_strength", "enabled", "damage", "normal_interval", "flight_interval", "minimum_attack_interval", "normal_range", "flight_range", "normal_angle", "flight_angle", "effect_mode", "frames", "arc_width", "arc_trail_degrees", "meowa_body_opacity", "meowa_tail_spread", "meowa_tail_inner_ratio", "meowa_tail_seconds", "effect_height", "effect_tilt_degrees", "effect_opacity", "effect_energy"],
	"player_ricochet_rules.gd": ["orbit_speed_ratio", "orbit_enter_seconds", "orbit_exit_seconds", "eccentric_enabled", "eccentric_minimum_members", "eccentric_capture_margin", "eccentric_step_distance", "eccentric_edge_clearance", "eccentric_outward_sway", "eccentric_search_radius", "crowd_deflection_enabled", "crowd_arc_degrees", "crowd_arc_distance", "enemy_push_enabled", "crowd_contact_radius", "crowd_turn_distance", "crowd_exit_outward", "crowd_speed_retention", "crowd_release_clearance", "full_charge_seconds", "minimum_launch_speed", "maximum_launch_speed", "bounce_speed_retention", "minimum_bounce_speed", "flight_deceleration", "bounce_speed_cost", "push_radius", "push_initial_speed", "push_seconds", "push_stun_seconds", "push_group_link_distance", "push_group_search_radius", "push_group_edge_margin", "push_arrival_arc_degrees", "push_chain_layers", "push_chain_speed_retention", "push_chain_stun_retention", "push_chain_min_speed", "clockwise"],
	"player_action_visuals.gd": ["hurt_screen_enabled", "hurt_screen_opacity", "hurt_screen_seconds", "hurt_screen_color", "hurt_camera_enabled", "hurt_shake_pixels", "hurt_shake_seconds", "hurt_orbit_shake_pixels", "hurt_orbit_shake_seconds", "hurt_shake_interval", "hurt_particles_enabled", "hurt_particle_count", "hurt_particle_seconds", "hurt_particle_spread_pixels", "hurt_particle_size_pixels", "hurt_particle_color", "speed_flow_mode", "speed_flow_texture_region", "surface_wave_texture", "speed_flow_enabled", "speed_flow_texture", "speed_flow_opacity", "speed_flow_length", "speed_flow_lifetime", "speed_flow_radius", "surface_wave_enabled", "surface_wave_radius", "surface_wave_seconds", "surface_wave_energy", "speed_rim_enabled", "speed_rim_strength", "speed_rim_width_pixels", "speed_rim_min_speed", "speed_rim_color", "sword_hit_impact_enabled", "sword_hitstop_seconds", "sword_hit_impact_interval", "sword_hit_shake_seconds", "sword_hit_shake_pixels", "hit_debris_speed_multiplier", "kill_slash_enabled", "kill_slash_texture", "kill_slash_seconds", "kill_slash_interval", "hit_debris_enabled", "hit_debris_count", "hit_debris_seconds", "hit_debris_interval", "kill_impact_enabled", "kill_hitstop_seconds", "kill_hitstop_interval", "kill_slow_tail_seconds", "kill_shake_seconds", "kill_shake_pixels", "kill_shot_enabled", "kill_shot_seconds", "kill_shot_zoom_scale", "kill_shot_minimum_kills", "kill_shot_group_window", "kill_shot_enter_seconds", "kill_shot_interval", "charge_wind_body_clearance_pixels", "charge_wind_layers", "charge_wind_trail_span", "charge_wind_funnel_enabled", "charge_wind_bottom_radius_pixels", "charge_wind_width_pixels", "charge_wind_turns", "charge_wind_full_speed_multiplier", "charge_wind_enabled", "charge_wind_texture", "charge_wind_radius_pixels", "charge_wind_height_pixels", "charge_wind_opacity", "charge_wind_cycle_seconds", "enemy_hit_silhouette_enabled", "enemy_hit_silhouette_seconds", "enemy_hit_silhouette_strength", "enemy_hit_silhouette_interval", "enemy_hit_silhouette_color", "feedback_prewarm_deaths", "feedback_prewarm_contacts", "enemy_hit_reaction_enabled", "enemy_hit_lean_degrees", "enemy_hit_recovery_seconds", "combat_readability_enabled", "combat_contact_frames", "combat_contact_seconds", "combat_sword_body_opacity", "combat_residue_opacity", "combat_death_focus_seconds", "motion_feedback_enabled", "flight_lean_degrees", "motion_reference_speed", "impact_lean_hold", "impact_lean_turn", "lean_return_seconds", "departure_airflow_enabled", "departure_airflow_texture", "departure_airflow_seconds", "departure_airflow_lifetime", "departure_airflow_spacing", "departure_airflow_opacity", "normal_attack", "charge", "flight", "flight_attack", "recovery", "bounce", "show_bounce_effect", "bounce_frames", "bounce_particles_enabled", "bounce_particle_count", "bounce_particle_speed", "bounce_particle_seconds", "bounce_anchor_pixels", "bounce_duration", "bounce_opacity", "bounce_energy", "bounce_height", "fire_trail_flow_enabled", "fire_trail_brush", "fire_trail_brush_region", "fire_trail_flow_speed", "fire_trail_spark_height", "fire_trail_spark_spacing", "fire_trail_flow_strength", "fire_trail_spark_amount", "fire_trail_body_clearance_pixels", "show_fire_trail", "fire_trail_width", "fire_trail_fresh_seconds", "fire_trail_burn_seconds", "fire_trail_ember_seconds", "fire_trail_energy", "fire_trail_pixels_per_meter", "melee_death_enabled", "melee_death_seconds", "melee_death_distance", "melee_death_height", "melee_death_spin_degrees", "melee_death_near_distance", "melee_death_reference_speed", "melee_death_min_strength", "melee_death_storm_retention", "melee_death_hit_pause", "melee_death_air_seconds", "melee_death_impact_frames", "melee_death_impact_seconds", "melee_death_trail_enabled", "melee_death_landing_enabled", "melee_death_bounce_height", "melee_death_slide_distance", "melee_death_cluster_enabled", "show_charge_effect", "show_aim_guide", "charge_radius_pixels", "charge_effect_opacity", "charge_effect_energy", "charge_dynamic_enabled", "charge_ring_contraction", "charge_mote_speed_gain", "charge_mote_count", "charge_full_settle_seconds", "preview_show_target", "preview_bounces", "preview_distance", "preview_followup_distance", "preview_color", "preview_opacity", "preview_line_width_pixels"],
	"leaf_charger_definition.gd": ["health", "attack_damage", "move_speed", "trigger_distance", "charge_speed", "charge_distance", "windup_seconds", "recovery_seconds", "attack_interval", "max_alive"],
	"lantern_spitter_definition.gd": ["health", "attack_damage", "shooting_range", "retreat_distance", "projectile_speed", "projectile_distance", "windup_seconds", "attack_interval", "max_alive"],
	"pot_brood_definition.gd": ["health", "move_speed", "attack_damage", "child_enemy_id", "split_delay", "max_alive"],
	"bell_frog_definition.gd": ["health", "move_speed", "boost_radius", "speed_multiplier", "boost_seconds", "windup_seconds", "attack_interval", "max_alive"],
	"ground_dressing_region.gd": ["enabled", "area_size", "density_multiplier", "extra_asset_manifest", "extra_density", "extra_scale"],
	"game_audio.gd": ["enabled", "balance", "max_voices", "important_reserve", "merge_window", "far_distance", "combat_volume_db", "music_volume_db"],
	"combat_audio_balance.gd": ["gains_db", "priorities", "intervals", "voice_limits"],
	"environment_dynamics.gd": ["enabled", "style_wind", "style_wind_tempo", "style_fireflies", "night_firefly_size", "region_wind", "region_fireflies", "region_blend_width", "transition_seconds", "battle_fireflies_enabled"],
	"spawn_visual_sample.gd": ["style", "independent_weather", "runtime_switch_enabled", "style_key", "original_light_refinement_enabled", "original_light_preset", "pixel_art_enabled", "color_ramps_enabled", "color_palette", "grass_variation_enabled", "grass_variation_strength", "grass_variation_size", "value_sample_enabled", "value_sample_profile", "fog_post_enabled", "fog_post_presets"],
	"follow_camera.gd": ["follow_enabled", "follow_max_speed", "follow_max_lag", "edge_pan_speed", "edge_pan_margin", "distance", "pitch_degrees", "fov", "dof_amount", "focus_height", "ricochet_camera_settings"],
	"art_direction.gd": ["street_fill_shadows_enabled", "exposure", "contrast", "saturation", "bloom", "moon_energy", "ambient_energy", "hemisphere_fill_enabled", "hemisphere_sky_color", "hemisphere_ground_color", "fog_begin", "fog_end", "fog_curve", "fog_amount", "low_fog", "volumetric_density", "bloom_threshold", "bloom_floor", "vignette", "vignette_radius", "shadow_lift", "split_toning", "wet_surface_enabled", "wet_surface_minimum", "wet_surface_coverage", "wet_surface_roughness", "wet_surface_reflectivity", "wet_surface_ripple_strength", "wet_surface_ripple_speed"],
	"weather.gd": ["weather_mode", "rain_intensity", "ground_rain_enabled", "ground_splash_size", "ground_splash_density", "ground_splash_strength", "wind_strength", "blink_plant_strength", "blink_rain_strength", "rain_volume_db", "wind_volume_db"],
	"player.gd": ["speed", "blink_distance", "blink_cooldown", "jump_height", "ricochet_rules", "action_visuals", "sword_rules", "flight_trail_settings", "crowd_clearance_distance"],
	"fan_auto_attack.gd": ["damage", "attack_range", "attack_interval", "fan_angle", "effect_opacity", "skill_definition", "audio_enabled", "audio_volume_db", "hit_sound_limit"],
	"mirror_mark_auto_attack.gd": ["damage", "attack_range", "attack_interval", "flight_speed", "mark_duration", "reflection_limit", "match_player_pixel_density", "skill_definition"],
	"run_buffs.gd": ["definitions"],
	"run_growth_rules.gd": ["epic_every", "orbit_damage_reduction", "sword_heal_fraction", "sword_heal_cap", "speed_damage_low", "speed_damage_high", "strike_speed_thresholds", "maximum_strikes"],
	"growth_buff_definition.gd": ["epic", "bonus_per_level", "max_level", "bonus_cap", "diminishing_after", "breakthrough_every", "breakthrough_multiplier", "required_levels", "extra_effects"],
	"growth_buff_effect.gd": ["attribute", "bonus_per_level", "bonus_cap"],
	"combat_skill_definition.gd": ["levels"],
	"combat_skill_level.gd": ["parameters"],
	"wave_enemy_definition.gd": ["health", "move_speed", "attack_damage", "experience_reward", "health_growth_enabled"],
	"wave_melee_enemy_definition.gd": ["enemy_id", "health", "move_speed", "attack_damage", "experience_reward", "health_growth_enabled", "body_radius", "contact_distance", "knockback_multiplier", "population_cost", "max_alive"],
	"wave_population_rules.gd": ["simulation_mode", "simulation_enemy_count", "simulation_skills", "first_active_limit", "max_active", "max_wave_enemies", "max_population_cost", "role_limits", "surround_start_wave", "surround_max_fronts"],
	"simulation_skill_entry.gd": ["skill_definition", "skill_level"],
	"wave_spawn_entry.gd": ["mixed_horde", "enemy", "count", "batch_size", "start_delay", "interval", "spawn_zone_ids"],
	"wave_health_growth_rules.gd": ["start_wave", "bonus_per_wave", "minimum_multiplier", "maximum_multiplier"],
	"wave_prototype.gd": ["enemy_catalog", "population_rules", "health_growth_rules", "pursuit_throttle_threshold", "enemy_occlusion_outline_enabled", "waves", "endless_mode", "endless_enemies_per_wave", "endless_max_enemies", "endless_interval_reduction", "endless_min_spawn_interval", "max_active_enemies", "retry_key", "show_ui"],
	"wave_hud.gd": ["enabled", "font_size", "hint_font_size", "top_margin", "text_color"],
	"battle_area.gd": ["core_size", "loop_width", "opening_spawn_offset", "core_density", "edge_density"],
	"ground_dressing.gd": ["grass_density", "flower_density", "stable_shadows"],
	"terrain.gd": ["data", "paint_palette"],
	"bgm.gd": ["music_enabled", "music_volume_db", "playlists", "music_transition_time", "music_fade_time"],
	"bgm_track.gd": ["track_id", "track_title", "stream", "volume_db", "loop_crossfade"],
	"bgm_playlist.gd": ["context_id", "tracks", "play_order"],
	"experience_rules.gd": ["first_level_experience", "per_level_increase", "level_cap"],
	"loadout_ui.gd": ["player_access_enabled", "ui_scale", "font_size"],
	"skill_hud.gd": ["slot_size", "slot_spacing", "screen_margin", "glow_strength"],
	"attribute_hud.gd": ["bar_width", "screen_margin", "glow_strength"],
	"experience_hud.gd": ["track_width", "follow_attributes", "attribute_gap", "background_opacity", "show_values", "flow_enabled", "flow_strength", "glint_strength"],
	"experience_pickup.gd": ["medium_threshold", "large_threshold", "gem_height", "bob_amplitude", "trail_length", "trail_brightness"],
	"item_quickbar.gd": ["slot_size", "slot_spacing", "background_opacity"],
	"ui_audio.gd": ["sounds", "volume_db", "action_intervals"],
	"ui_sound_bank.gd": ["actions", "gains_db", "select", "confirm", "cancel", "page_turn"],
	"game_settings_ui.gd": ["ui_sounds"],
	"core_feedback_audio.gd": ["charge_wind_audio_enabled", "charge_wind_gain_db", "charge_wind_energy_duck_db", "charge_wind_fade_out_seconds", "enabled", "action_volume_db", "bounce_gain_db", "death_impact_gain_db", "common_hit_enabled", "hit_material_layer_enabled", "hit_material_gain_db", "charge_energy_audio_enabled", "charge_progress_audio_enabled", "charge_start_gain_db", "charge_full_gain_db", "charge_start_pitch", "charge_full_pitch", "charge_ready_gain_db", "launch_release_audio_enabled", "launch_full_gain_db", "launch_wind_entry_seconds", "launch_wind_start_gain_db", "flight_audio_enabled", "flight_gain_db", "flight_low_speed_gain_db", "flight_reference_speed", "flight_volume_smoothing", "flight_fade_out_seconds", "enemy_volume_db", "feedback_volume_db", "sounds"],
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
	if filename == "run_growth_rules.gd": return "战斗与成长"
	if filename in ["run_score.gd", "run_score_rules.gd"]: return "战斗与成长"
	if filename == "sword_ribbon_visual.gd": return "人物"
	if filename == "wave_spawn_shadow_settings.gd": return "视觉"
	if filename == "world_entry_settings.gd" and group == "穿雾声音": return "声音"
	if filename == "charge_presentation.gd": return "声音" if group == "蓄力声音退让" else "视觉"
	if filename in ["world_entry.gd", "world_entry_settings.gd", "wave_presentation.gd", "wave_presentation_settings.gd"]: return "视觉"
	if filename == "scene_combat_configuration.gd": return "人物" if group == "人物基础战斗" else "战斗与成长"
	if filename == "scene_combat_binding.gd": return "战斗与成长"
	if filename == "aurora_sky.gd": return "视觉"
	if filename == "building_occlusion.gd": return "视觉"
	if filename in ["core_feedback_audio.gd", "core_sound_bank.gd", "kill_audio_rules.gd", "kill_feedback_audio.gd", "combat_audio_balance.gd"]: return "声音"
	if filename == "ricochet_camera_settings.gd": return "视觉"
	if filename in ["damage_numbers.gd", "damage_number_style.gd"]: return "战斗与成长"
	if filename.begins_with("ricochet_storm"): return "战斗与成长"
	if filename in ["leaf_charger_definition.gd", "lantern_spitter_definition.gd", "pot_brood_definition.gd", "bell_frog_definition.gd", "creature_enemy.gd", "leaf_charger.gd", "lantern_spitter.gd", "pot_brood.gd", "bell_frog.gd", "mini_slime.gd"]: return "战斗与成长"
	if filename in ["environment_dynamics.gd", "environment_lantern.gd"]: return "视觉"
	if filename in ["game_audio.gd", "bgm.gd", "bgm_track.gd", "bgm_playlist.gd", "player_movement_audio.gd", "movement_sound_bank.gd", "ui_audio.gd", "ui_sound_bank.gd"] or "声音" in group or "音效" in group or "风声" in group: return "声音"
	if filename in ["character_skill_manager.gd", "player.gd", "player_blink.gd", "player_ricochet_rules.gd", "player_action_visuals.gd", "player_sword_rules.gd", "player_flight_trail_settings.gd", "character_lighting.gd", "character_spotlight.gd"]: return "人物"
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
	if filename == "wave_prototype.gd": return property in ["enemy_catalog", "default_enemy", "population_rules", "health_growth_rules", "growth_rules", "spawn_shadow_settings", "waves", "endless_mode", "max_active_enemies", "batch_crowd_enabled", "pursuit_throttle_threshold", "native_chase_enabled", "slime_ground_movement_enabled"]
	if filename == "follow_camera.gd": return property == "ricochet_camera_settings"
	if filename == "run_growth.gd": return property in ["progression_rules", "rules", "cards_per_draw", "rerolls_per_run"]
	if filename == "run_buffs.gd": return property == "definitions"
	if filename == "damage_numbers.gd": return property == "number_styles"
	if filename == "loadout_ui.gd": return property == "equipment_bonuses_enabled"
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
	if filename == "character_lighting.gd":
		label = {"lighting_enabled": "人物场景受光适配", "light_wrap": "人物侧光柔和度", "top_light_response": "人物顶部受光比例",
			"back_rim_strength": "人物真实背光亮边", "local_light_response": "人物路灯／点光响应强度", "normal_mapping_enabled": "人物逐帧法线开关", "normal_mapping_strength": "人物法线起伏强度"}.get(property, label)
	if filename == "character_spotlight.gd":
		label = {"fill_enabled": "人物重点补光开关", "fill_color": "人物补光颜色", "fill_energy": "人物补光强度",
			"fill_height": "人物补光高度", "fill_front_offset": "人物补光前侧距离", "fill_side_offset": "人物补光左右偏移",
			"fill_target_height": "人物补光对准高度", "fill_angle": "人物补光锥角"}.get(property, label)
	if filename == "wave_spawn_shadow_settings.gd":
		label = {"enabled":"落点剪影预告开关", "warning_seconds":"出怪前剪影预告时长", "fade_seconds":"出怪后剪影消散时间",
			"shadow_color":"落点剪影颜色", "rim_color":"落点剪影细边颜色", "shadow_opacity":"落点剪影透明度", "rim_opacity":"落点剪影细边透明度",
			"footprint_scale":"落点剪影尺寸", "footprint_depth_ratio":"落点剪影贴地纵深比例", "contraction":"落点剪影收束幅度"}.get(property, label)
	if filename == "kill_audio_rules.gd" and property == "enabled": label = "击杀声音反馈开关"
	if filename == "charge_presentation.gd" and property == "enabled": label = "蓄力场景反馈开关"
	if filename == "building_occlusion.gd" and property == "enabled": label = "人物遮挡物淡化开关"
	if filename == "ricochet_camera_settings.gd" and property == "flight_reference_speed": label = "滑行镜头满效果参考速度"
	if filename == "kill_audio_rules.gd" and property == "music_duck_db": label = "群杀音乐退让"
	if filename == "kill_audio_rules.gd" and property == "ambience_duck_db": label = "群杀风雨退让"
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
