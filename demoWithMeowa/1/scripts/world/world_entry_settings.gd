class_name WorldEntrySettings
extends Resource

@export_group("入场播放")
@export var enabled := true
@export_range(0.0, 12.0, 0.1, "suffix:s") var duration_seconds := 6.4
@export var allow_skip := true
## 前段用于穿雾运镜，余下时间在原有取景中散雾显露人物。
@export_range(0.35, 0.85, 0.01) var arrival_ratio := 0.56
@export_group("穿雾环绕镜头")
## 未绑定建筑路线时，从正常镜头后方远空推进；最后恢复地图原有取景，不改基础镜头参数。
@export_range(50.0, 180.0, 1.0, "suffix:m") var sky_extra_distance := 95.0
@export_range(8.0, 45.0, 1.0, "suffix:m") var sky_extra_height := 18.0
@export_range(-25.0, 25.0, 0.5, "suffix:m") var sky_lateral_offset := 8.0
@export_range(-5.0, 8.0, 0.5) var sky_view_pitch := 3.0
@export_range(0.0, 160.0, 1.0, "suffix:°") var camera_sweep_degrees := 110.0
## 左右侧倾；限制在 55° 内，不倒置画面。
@export_range(0.0, 55.0, 1.0, "suffix:°") var camera_bank_degrees := 36.0
@export_group("穿雾声音")
@export var traversal_audio_enabled := true
@export var traversal_sound: AudioStream
@export_range(-40.0, 0.0, 0.5, "suffix:dB") var traversal_volume_db := -8.0
@export_group("空间云雾")
## 雾团整体强度；没有全屏颜色遮罩，浓淡由空间密度、噪声与相机穿行决定。
@export_range(0.0, 0.95, 0.01) var fog_opacity := 0.94
@export var fog_color := Color(0.60, 0.64, 0.69)
@export_range(0.0, 2.0, 0.05) var fog_flow_speed := 0.65
@export_range(0.0, 1.0, 0.005) var volume_density := 0.22
@export_range(10.0, 70.0, 1.0, "suffix:m") var fog_retreat_distance := 42.0
@export_range(0.0, 2.0, 0.05) var fog_curl_strength := 1.0
## 体积云团提供主体厚度，云片只补掠过细节；各地图独立选择比例。
@export_range(0.2, 1.0, 0.05) var cloud_bank_scale := 1.0
@export_range(0.0, 1.0, 0.05) var cloud_bank_density_ratio := 0.75
@export_range(0.0, 1.0, 0.02) var wisp_opacity := 1.0
@export_range(0.0, 2.0, 0.1, "suffix:m") var wisp_depth_bulge := 0.0
@export_group("建筑透雾与轮廓")
## 只在入场借用外围城市的材质；退出后还原，其他地图默认沿用原外观。
@export var building_atmosphere_enabled := false
## 只加强已有发光区域，不把整栋建筑提亮或增加灯源。
@export_range(1.0, 4.0, 0.1) var building_light_gain := 2.2
## 中性自发光过高会盖住真实灯光的冷暖；不改变云团密度。
@export_range(0.0, 3.0, 0.05) var fog_self_emission := 2.0
@export_range(0.0, 0.6, 0.01) var mist_light_response := 0.28
@export_range(0.2, 2.0, 0.05) var mist_light_threshold := 0.55
## 仅柔化物体轮廓；墙身细节由空间浓雾遮蔽，源贴图不改。
@export_range(0.5, 6.0, 0.25, "suffix:px") var building_edge_softness_pixels := 2.5
@export_range(0.0, 0.8, 0.02) var building_edge_blur_strength := 0.4
@export_group("建筑发光散射")
## 跟随建筑发光材质的原开关、颜色与强度，只在开场向雾散射。
@export var emission_fog_enabled := false
@export_range(0.0, 2.0, 0.05) var emission_fog_strength := 0.45
@export_range(0.5, 5.0, 0.1, "suffix:m") var emission_fog_radius := 2.0
@export_range(1, 48, 1) var emission_fog_max_lights := 16
@export_range(0.05, 0.5, 0.05, "suffix:s") var emission_fog_refresh_seconds := 0.1
@export_group("人物聚光")
@export var spotlight_color := Color(1.0, 0.86, 0.65)
@export_range(0.0, 12.0, 0.1) var spotlight_energy := 4.0
@export_range(0.0, 12.0, 0.1) var spotlight_fog_energy := 3.0
@export_range(4.0, 14.0, 0.5, "suffix:m") var spotlight_height := 9.0
@export_range(5.0, 18.0, 0.5) var spotlight_angle := 10.0
