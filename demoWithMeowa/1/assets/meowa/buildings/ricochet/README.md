# 弹射障碍物与同风格变种

六件基础场景加十二件同风格变种，均可独立拖入世界。复用广场道具的本地网格合批与贴地；旧木纹 `wood.png` 由 Meowa 生成，原生 64×64 RGBA，未重采样或再次像素化。墙身使用独立的 `../materials/masonry.png`，压顶与柱身使用 `../materials/limestone.png`，均为 Meowa 原生 64px 材质；金属复用已制作的 64px 铸铁／黄铜，不再用广场铺装作道具石材。材质约 40 像素／米。

| 道具 | 独立场景 | 弹射地编用途 |
| --- | --- | --- |
| 矮石墙 | `res://scenes/buildings/ricochet/low_wall.tscn` | 连续平面与端部转角，分隔战斗通路 |
| 铁艺围栏 | `res://scenes/buildings/ricochet/iron_fence.tscn` | 石基、横杆和竖杆分别碰撞；细射线可穿过实际空隙 |
| 木箱堆 | `res://scenes/buildings/ricochet/crate_stack.tscn` | 三只高低不同、朝向不同的箱体，形成错开的反射面 |
| 木桶组 | `res://scenes/buildings/ricochet/barrel_cluster.tscn` | 三只大小不同的木桶；圆柱腹部提供径向法线，上下收口单独贴合碰撞 |
| 方形石柱 | `res://scenes/buildings/ricochet/stone_pillar.tscn` | 占地小、四向平面、阶梯底座，适合通路中间点状障碍 |
| L 形挡墙 | `res://scenes/buildings/ricochet/corner_wall.tscn` | 两个垂直内侧面支持连续反射，内部没有实心包围盒 |

十二件变种位于 `res://scenes/buildings/ricochet/variants/`，保留同一套石材、木纹与金属，通过结构改变弹射路线：

| 类别 | 独立场景 | 用途 |
| --- | --- | --- |
| 矮墙 | `short_wall.tscn` | 1.75 米短隔墙，便于组合错位墙与宽通道 |
| 矮墙 | `angled_wall.tscn` | 默认 45° 折角，斜面将正向射线转向侧面 |
| 围栏 | `fence_passage.tscn` | 两段石基与铁栏，中间默认留 2.2 米真实通行开口 |
| 围栏 | `folded_fence.tscn` | 默认 60° 折角，两段共用中柱，细杆之间仍可穿过细射线 |
| 木箱 | `diagonal_crate.tscn` | 45° 单箱，小占地的斜向平面 |
| 木箱 | `crate_row.tscn` | 三只落地箱错开朝向与位置，提供连续但不齐平的侧面 |
| 木桶 | `single_barrel.tscn` | 单只圆桶，放置于通路边缘引导径向反射 |
| 木桶 | `barrel_row.tscn` | 三只横排圆桶，保留各自腹部与上下收口碰撞 |
| 石柱 | `round_pillar.tscn` | 圆形高柱，反射方向随命中位置连续变化 |
| 石柱 | `octagonal_pillar.tscn` | 八角矮柱，八个真实平面供不同方向弹射 |
| 挡墙 | `u_wall.tscn` | 4.2×3.2 米开口墙，三面内部反射，正面可进出 |
| 挡墙 | `obtuse_wall.tscn` | 默认 135° 内角，比直角墙形成更开阔的反射口 |

在 Godot「地图切换 → 六种弹射障碍物预览」运行，也可直接打开 `res://scenes/previews/ricochet_props_preview.tscn` 按 F6。预览读取当前世界的镜头、光影和天气；Q/E 旋转、R 切风格，人物可走动观察。样板位于 `CurrentWorld/RicochetSamples`，不写人物存档，不改变世界中已有摆放。

新变种使用「地图切换 → 弹射建筑变种预览」，或打开 `res://scenes/previews/ricochet_variants_preview.tscn` 按 F6。十二件分四组三件陈列，沿广场向东或向南可走到下一组；沿用正式场景当前镜头、光照和天气。所有新增样板位于 `CurrentWorld/RicochetVariantSamples`，仅在这个预览中摆放。

将六件场景从文件系统拖进 `world.tscn`，选根节点整体移动、绕 Y 旋转、复制。Inspector 的 `dimensions` 为宽／高／深，修改后只重建当前道具；「贴合地面」对齐所在地表。移动不重建道具网格，也不重建地形或全图草花。

变种按同样方式放置。Inspector「同风格变种」的 `layout_variant` 按类别显示三个结构名称；`passage_width` 调开口围栏通路，`turn_angle_degrees` 调斜墙、折角围栏与钝角墙，钝角内角为 90° 加此值。开口最终受总宽度限制。`dimensions` 是构件尺寸，转折与旋转后外接范围会相应增大，布置通路时以可见几何和实际碰撞为准。

「独立道具石材」的 `stone_texture` 与 `cap_texture` 分别控制砌石面与整石压顶／石柱。两者可各自替换，石材 UV 按各贴图原生宽度保持 40 像素／米，编辑只重建当前实例。

碰撞沿用世界的第 1 层。根节点属于 `ricochet_obstacles`，碰撞体属于 `ricochet_surfaces`，可供后续弹射攻击查找。每件模型使用自己的材质和复合碰撞，静止时没有逐帧逻辑。现阶段准备障碍物与实际反射表面，弹射攻击规则按后续玩法设计接入。
