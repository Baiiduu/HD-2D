# 正式地图（战斗区）

在 Godot 的「地图切换」中选择「正式连续地图」并运行。入口为 `world.tscn`，独立于视觉测试场景。

主场景只保留现有 32×32 米战斗核心，外围非战斗绕行带与旧入口地块已移除。地形按原 1.6 米格子覆盖核心，实际为 21×21 格、33.6×33.6 米，人物与战斗范围均限制在核心内。出生、开战交互和撤退返回位置位于核心内的空地（X/Z 为 0／48），保留原 F 键开局流程。核心内的手绘地表、建筑摆放与光影参数保持。旧小院、住宅、训练小屋、东侧广场等原型资源继续保留。

`WorldDetails/BattleCourts` 集中布置城镇细节、树池、中心雕塑与弹射障碍，复用花车、长椅、告示牌、花盆、水钵、垃圾桶、托盘、麻袋、石墙、柱、围栏、箱桶与路灯。道具按各实例的缩放布置，树池底座与树冠可独立调节，保留原生像素素材。场内横穿与绕障通路保留，物件具有实际碰撞。

树池建筑样板可从「地图切换 → 树池建筑预览」查看。将 `scenes/buildings/tree_planter.tscn` 拖入世界，选择根节点整体移动、旋转、复制；Inspector「贴合地面」对齐高度，尺寸与花草／长椅／路灯独立可调。具体素材与放置方式见[树池说明](../../assets/meowa/buildings/tree_planter/README.md)。

参考图的双头路灯与中心环球雕塑见「地图切换 → 广场路灯与环球雕塑预览」。独立场景为 `scenes/buildings/plaza_streetlamp.tscn` 和 `scenes/buildings/armillary_monument.tscn`，可同样拖入世界整体放置；具体参数见[广场道具说明](../../assets/meowa/buildings/plaza_landmarks/README.md)。

六种非房屋弹射障碍物位于 `scenes/buildings/ricochet/`，从「地图切换 → 六种弹射障碍物预览」查看。包含矮石墙、铁艺围栏、木箱堆、木桶组、方形石柱与 L 形挡墙，均可整体放置，提供实际平面／圆柱／转角碰撞；用法见[障碍物说明](../../assets/meowa/buildings/ricochet/README.md)。

同风格新增十二件变种位于 `scenes/buildings/ricochet/variants/`，从「地图切换 → 弹射建筑变种预览」查看。短墙、斜墙、通行开口围栏、折栏、单箱／箱排、单桶／桶排、圆柱／八角柱、U 形／钝角墙可用于组合不同的反射路线，尺寸、开口和角度在各根节点调整。

八种城镇细节物件位于 `scenes/buildings/town_details/`，从「地图切换 → 城镇细节物件预览」查看。包含独立长椅、手推花车、告示牌、陶制花盆、石质水钵、街边垃圾桶、货运托盘和麻袋堆，可拖入正式地图，沿用现有弹射碰撞与整体放置方式；见[细节物件说明](../../assets/meowa/buildings/town_details/README.md)。

战区挑战使用[无尽波次](../../../../docs/gameplay/endless-waves.md)：开场 18／28／40 只，后续持续递增；清波休整后按 F 继续，失败或 ESC 撤退结束，T 重试回到第一波。参数位于 `WavePrototype → 无尽波次`。

战区地形使用 `data/world/world_terrain.tres`，当前战斗面为零层平地，取消原东西两侧的高台地与坡道；裁切后保留格子的原道路覆盖层、区域类型、高度与画笔编号。`data/world/world_surface.tres` 保留手绘地表与分隔带数据，仅上传落在战区内的绘制块。原 `data/world/spawn_terrain.tres` 保留为小院原型基准。`VisualSample` 使用场景当前保存的光影，三种 Lumina 与原始增强仍可按 R 比较；原始增强参数见[提亮、明暗交界与光向统一](../../../../docs/visuals/original-light-refinement.md)。

`SpawnPoint` 是实际出生位置，运行时将人物放到此标记。WASD / 方向键移动，空格跳跃，Q/E 连续旋转，R 切四种光影／天气 Style，结算后 T 重试。Godot「参数总览」统一定位参数，见 [参数与 Style](../../../../docs/technical/parameters-and-styles.md)。

`Player → 台阶通行` 可开关自动迈步，并调整单级最大高度（默认 0.25 米）；当前地图地面不需要登坡或跳台，建筑自身的体积与碰撞保留。

地表分布可在编辑器中手绘：选中 `Homestead`，打开右侧「地表画笔」并启用，选择草地或卵石道路后左键拖动。Shift+左键擦除道路，Ctrl+Z / Ctrl+Shift+Z 撤销或重做；使用「保存地表」或 Ctrl+S 保存。详见 [地表画笔](../../addons/terrain_painter/README.md)。

镜头恢复人物在画面中央附近的原有构图：FOV 28°、距离 25 米、俯角 30.627°、默认朝向 135°、焦点高度 0.75 米、垂直偏移 0 米，景深关闭；保留 Q/E 连续旋转、跟随与弹射反馈。`VisualSample` 不覆盖镜头，共享效果和四境视觉测试场景保留各自对照配置与旋转能力。

远景为 `assets/meowa/environment/distant_city/city_matte.png` 的原生 2048×1152 单幅雾城图，经天空材质按屏幕坐标等比裁切，只出现在地形、建筑后方。人物移动时图片位置不变，窗口比例变化时顶部对齐，不拉伸；画面背景与照明立方体分开，保持现有场景照明。旧环绕贴图与隐藏的 `CityBackdrop` 原型保留。

`WorldDetails/BattlePerimeter` 沿战区四周草地边沿放置 36 段现有铁艺栅栏，栏高 1 米，保留独立石座、金属栏杆及真实弹射碰撞。各实例可在编辑器单独调整，不改手绘铺装及场内原有建筑。

| 调节节点 | 参数与用途 |
| --- | --- |
| `WorldDetails/BattleCourts` | 小型道具的整体位置、朝向、缩放与真实碰撞 |
| `GroundDressing → excluded_areas` | 建筑与入口的花草留空区域，采用地形本地 X/Z 坐标 |
| `BattleArea` | 主战斗面、开战交互与花草密度；正式场景 `loop_width = 0`、`entry_inset = 19.2`、`terrace_levels = 0`，重建保留手绘地表，不恢复外围区域 |
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
