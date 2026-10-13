# 正式连续地图

在 Godot 的「地图切换」中选择「正式连续地图」并运行。入口为 `world.tscn`，独立于视觉测试场景。

南侧挑战现为[无尽波次](../../../../docs/endless-waves.md)：开场 18／28／40 只，后续持续递增；清波休整后按 F 继续，失败或 ESC 撤退结束，T 重试回到第一波。参数位于 `WavePrototype → 无尽波次`。

出生区使用错落的平整台地：房屋与前院位于中层，外出地块位于较低一层，西侧与后方为较高一层。三档地面高度为 0、0.8、1.6 米，仅在通行连接处设置坡道。

现有砖木住宅保留在 `HouseSite/Home`，位于 `(-4, 0.8, -4.8)`，正门朝 +Z 的院内方向。复用既有建筑和碰撞，目前尚未制作室内与开门交互；材质采用当前 Lumina 与统一像素美术样板。

训练小屋直接位于东侧的 `TrainingHut`，位置 `(7.2, 0, -4.8)`，正门朝 +Z。沿东侧坡道下到平地，靠近沙袋按 F 打开训练面板；生命、攻击、防御强化与角色配置共用存档。ESC 或 F 返回地图，Tab 查看角色总属性，详见 [训练小屋](../../../../docs/training-hut.md)。

完整连续地图使用 `data/world_terrain.tres`，原 `data/spawn_terrain.tres` 保留为出生区基准。复用 `Terrain` 组件生成平台顶面、侧壁、坡道和碰撞，当前铺设草地、卵石路、土岩侧壁与花草簇。`VisualSample` 默认使用更新后的 Lumina 黄金时段与统一像素素材。出生区的原有台地和建筑保持当前落位，南侧道路连接新战斗区域，详见 [南侧战斗区域](../../../../docs/battle-area-plan.md)。

`SpawnPoint` 是实际出生位置，运行时将人物放到此标记。WASD / 方向键移动，空格跳跃，Q/E 旋转，R 切四种光影／天气 Style，结算后 T 重试。Godot「参数总览」统一定位参数，见 [参数与 Style](../../../../docs/parameters-and-styles.md)。

房屋门口的低台阶可以直接行走上下，不需要跳跃。`Player → 台阶通行` 可开关自动迈步，并调整单级最大高度（默认 0.25 米）；高台地仍通过坡道或跳跃通行。

地表分布可在编辑器中手绘：选中 `Homestead`，打开右侧「地表画笔」并启用，选择草地或卵石道路后左键拖动。Shift+左键擦除道路，Ctrl+Z / Ctrl+Shift+Z 撤销或重做；使用「保存地表」或 Ctrl+S 保存。详见 [地表画笔](../../addons/terrain_painter/README.md)。

当前正式地图镜头为距离 28 米、俯角 32°、FOV 28°、焦点高度 0.9 米、死区 0.1 米、深度景深 0.065。Q/E 可以沿同一方向连续旋转任意圈数，保留加速、平滑收尾与每圈 15° 吸附。正式地图与 `VisualSample` 使用实际场景覆盖值，共享效果和四境视觉测试场景保留各自对照配置。

| 调节节点 | 参数与用途 |
| --- | --- |
| `HouseSite` | 位置与旋转；当前高度由地图脚本对齐所在台地 |
| `HouseSite/Home` | 房屋宽度、深度、屋檐高度、屋顶高度、纹理重复尺寸与粗糙度；尺寸变化同步重建建筑及碰撞 |
| `TrainingHut` | 位置、朝向、房屋尺寸和雨棚深度；「对齐建筑与出生点」也会将它对齐台地 |
| `TrainingUI` / `LoadoutUI → training_rules` | F 键交互距离、高差、界面缩放，以及基础属性、强化增量、点数、消耗和等级上限 |
| `TrainingUI → 交互提示美术` | Meowa 透明底像素键帽与训练徽标，支持替换纹理并调整图标尺寸、字号和提示高度 |
| `GroundDressing → excluded_areas` | 建筑与入口的花草留空区域，采用地形本地 X/Z 坐标 |
| `BattleArea` | 主战斗面、绕行带、景观缓冲、坡道、台地及花草密度；布局修改后可重建并保存地形 |
| `Homestead → data` | `cell_size` 为格子尺寸（当前 1.6 米），`layer_height` 为每档高差（当前 0.8 米）；地块轮廓与层级在独立数据中保存 |
| `Homestead → top_material` | 独立的 `materials/world/spawn_ground.tres`；当前使用 `wild_texture/tint` 草地和 `path_atlas/tint` 卵石路。石板与泥土槽位保留，但地图未铺设对应区域；各 `surface` 的 X/Y/Z 分别控制干燥粗糙度、金属度、受湿程度 |
| `Homestead → wall_material` | 独立的 `materials/world/spawn_cliff.tres`；`wall_texture` 为侧壁纹理，`tint/saturation` 为色调，`texel` 为单像素对应的米数，`lip_pixels/lip_shadow_pixels` 为边沿宽度与阴影宽度 |
| `Homestead → grass_transition / surface_edge_transition` | 草沿与铺装侧边衔接，当前均开启；控制台地边缘如何折到侧壁 |
| `WorldMap` | 调整标记位置后可按「对齐建筑与出生点」重新对齐台地高度；`spawn_lift` 是出生时脚底离地余量 |
| `MapEffects/ArtDirection` | 曝光、环境光、主光颜色/方向/阴影、雾与色调 |
| `MapEffects/Camera3D` / `VisualSample` | Camera3D 独立调镜头；VisualSample 切光影／天气、像素材质和色阶，不再重复控制镜头或布局 |

顶面沿用预览材质做法：按世界坐标铺设 64px 材质，道路/泥土使用 4×4 双网格过渡图集，`terrain_surface.gdshaderinc` 同时供顶面和侧壁取样；`cliff.gdshader` 处理草沿、铺装侧边及崖脚衔接。单格 1.6 米，像素密度保持一致。材质参数在正式地图中独立保存，不影响视觉测试地图。

天气与地面湿润参数由通用 `MapEffects` 同步到地形材质；调节雨量或湿润效果时使用既有天气与视觉调节节点。

地表与碰撞在编辑器和运行时生成，生成节点不保存。当前完整地形覆盖 104×123.2 米；南侧主战斗面约 32×32 米，外围活动范围约 48×48 米，其余部分用于出生区和镜头景观缓冲。
