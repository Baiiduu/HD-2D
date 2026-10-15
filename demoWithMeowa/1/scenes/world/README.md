# 正式地图（战斗区）

在 Godot 的「地图切换」中选择「正式连续地图」并运行。入口为 `world.tscn`，独立于视觉测试场景。

主场景只保留现有 32×32 米战斗核心和 8 米宽外围绕行带，活动范围约 48×48 米，实际地形按格子裁成 49.6×49.6 米。出生与撤退位置均在战区入口。小院、住宅、训练小屋、东侧广场及独立花园城镇大地图已退出正式场景；保留它们可复用的原型资源。

`WorldDetails/BattleCourts` 集中布置 26 件细节与弹射障碍，复用花车、长椅、告示牌、花盆、水钵、垃圾桶、托盘、麻袋、石墙、柱、围栏、箱桶与路灯。普通道具使用原尺寸的 90%，树池底座也适当收小，树木原生像素尺度保持。中心横穿和外围绕行通路保留，物件具有实际碰撞。

树池建筑样板可从「地图切换 → 树池建筑预览」查看。将 `scenes/buildings/tree_planter.tscn` 拖入世界，选择根节点整体移动、旋转、复制；Inspector「贴合地面」对齐高度，尺寸与花草／长椅／路灯独立可调。具体素材与放置方式见[树池说明](../../assets/meowa/buildings/tree_planter/README.md)。

参考图的双头路灯与中心环球雕塑见「地图切换 → 广场路灯与环球雕塑预览」。独立场景为 `scenes/buildings/plaza_streetlamp.tscn` 和 `scenes/buildings/armillary_monument.tscn`，可同样拖入世界整体放置；具体参数见[广场道具说明](../../assets/meowa/buildings/plaza_landmarks/README.md)。

六种非房屋弹射障碍物位于 `scenes/buildings/ricochet/`，从「地图切换 → 六种弹射障碍物预览」查看。包含矮石墙、铁艺围栏、木箱堆、木桶组、方形石柱与 L 形挡墙，均可整体放置，提供实际平面／圆柱／转角碰撞；用法见[障碍物说明](../../assets/meowa/buildings/ricochet/README.md)。

同风格新增十二件变种位于 `scenes/buildings/ricochet/variants/`，从「地图切换 → 弹射建筑变种预览」查看。短墙、斜墙、通行开口围栏、折栏、单箱／箱排、单桶／桶排、圆柱／八角柱、U 形／钝角墙可用于组合不同的反射路线，尺寸、开口和角度在各根节点调整。

八种城镇细节物件位于 `scenes/buildings/town_details/`，从「地图切换 → 城镇细节物件预览」查看。包含独立长椅、手推花车、告示牌、陶制花盆、石质水钵、街边垃圾桶、货运托盘和麻袋堆，可拖入正式地图，沿用现有弹射碰撞与整体放置方式；见[细节物件说明](../../assets/meowa/buildings/town_details/README.md)。

战区挑战使用[无尽波次](../../../../docs/gameplay/endless-waves.md)：开场 18／28／40 只，后续持续递增；清波休整后按 F 继续，失败或 ESC 撤退结束，T 重试回到第一波。参数位于 `WavePrototype → 无尽波次`。

战区地形使用 `data/world/world_terrain.tres`，裁切保留范围内原有高度、道路、画笔编号和台地。`data/world/world_surface.tres` 保留手绘地表与分隔带数据，仅上传落在战区内的绘制块。原 `data/world/spawn_terrain.tres` 保留为小院原型基准。`VisualSample` 默认使用增强后的原始光影；三种 Lumina 仍可按 R 比较。原始增强可独立关闭，见[提亮、明暗交界与光向统一](../../../../docs/visuals/original-light-refinement.md)。

`SpawnPoint` 是实际出生位置，运行时将人物放到此标记。WASD / 方向键移动，空格跳跃，Q/E 旋转，R 切四种光影／天气 Style，结算后 T 重试。Godot「参数总览」统一定位参数，见 [参数与 Style](../../../../docs/technical/parameters-and-styles.md)。

`Player → 台阶通行` 可开关自动迈步，并调整单级最大高度（默认 0.25 米）；战区高台地仍通过坡道或跳跃通行。

地表分布可在编辑器中手绘：选中 `Homestead`，打开右侧「地表画笔」并启用，选择草地或卵石道路后左键拖动。Shift+左键擦除道路，Ctrl+Z / Ctrl+Shift+Z 撤销或重做；使用「保存地表」或 Ctrl+S 保存。详见 [地表画笔](../../addons/terrain_painter/README.md)。

镜头使用 `MapEffects/Camera3D` 当前保存的配置，布置和裁切不调整镜头。Q/E 可以沿同一方向连续旋转任意圈数，保留加速、平滑收尾与每圈 15° 吸附。`VisualSample` 不覆盖镜头，共享效果和四境视觉测试场景保留各自对照配置。

| 调节节点 | 参数与用途 |
| --- | --- |
| `WorldDetails/BattleCourts` | 小型道具的整体位置、朝向、缩放与真实碰撞 |
| `GroundDressing → excluded_areas` | 建筑与入口的花草留空区域，采用地形本地 X/Z 坐标 |
| `BattleArea` | 主战斗面、绕行带及花草密度；当前战区模式的重建只裁切数据，不重画手绘地表或恢复旧区域 |
| `Homestead → data` | `cell_size` 为格子尺寸（当前 1.6 米），`layer_height` 为每档高差（当前 0.8 米）；地块轮廓与层级在独立数据中保存 |
| `Homestead → top_material` | 草地、道路与手绘石板铺装；各 `surface` 的 X/Y/Z 分别控制干燥粗糙度、金属度、受湿程度 |
| `Homestead → wall_material` | 独立的 `materials/world/spawn_cliff.tres`；`wall_texture` 为侧壁纹理，`tint/saturation` 为色调，`texel` 为单像素对应的米数，`lip_pixels/lip_shadow_pixels` 为边沿宽度与阴影宽度 |
| `Homestead → grass_transition / surface_edge_transition` | 草沿与铺装侧边衔接，当前均开启；控制台地边缘如何折到侧壁 |
| `WorldMap` | 调整标记位置后可按「对齐建筑与出生点」重新对齐台地高度；`spawn_lift` 是出生时脚底离地余量 |
| `MapEffects/ArtDirection` | 曝光、环境光、主光颜色/方向/阴影、雾与色调 |
| `MapEffects/Camera3D` / `VisualSample` | Camera3D 独立调镜头；VisualSample 切光影／天气、像素材质和色阶，不再重复控制镜头或布局 |

顶面沿用预览材质做法：按世界坐标铺设 64px 材质，道路/泥土使用 4×4 双网格过渡图集，`terrain_surface.gdshaderinc` 同时供顶面和侧壁取样；`cliff.gdshader` 处理草沿、铺装侧边及崖脚衔接。单格 1.6 米，像素密度保持一致。材质参数在正式地图中独立保存，不影响视觉测试地图。

天气与地面湿润参数由通用 `MapEffects` 同步到地形材质；调节雨量或湿润效果时使用既有天气与视觉调节节点。

地表与碰撞在编辑器和运行时生成，生成节点不保存。运行回归检查可使用 `tests/test_battle_only_world.gd`，覆盖裁切范围、通路、障碍碰撞、Style 保持和真实波次启动。
