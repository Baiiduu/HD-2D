# 独立道具材质

三张 Meowa 原生 64×64 RGBA 不透明贴图，保留生成像素，不重采样或再次像素化。

| 文件 | 用途 |
| --- | --- |
| `masonry.png` | 青灰小块砌石，用于墙身、围栏石基与花坛壁 |
| `limestone.png` | 低对比细孔整石，用于压顶、石柱、雕塑基座与水钵 |
| `compost.png` | 深色细粒栽培土，含少量碎树皮，用于花盆、花车与树池内部 |

默认石材每块覆盖 1.6 米，约 40 像素／米。`RicochetProp`、其城镇细节派生物与环球雕塑通过 `stone_texture`、`cap_texture` 分别替换砌石与整石；树池具有同名材质参数和独立 `wood_texture`。木材仍用 `../ricochet/wood.png`，金属用 `../plaza_landmarks/graphite.png` 与 `brass.png`，陶土用 `../town_details/terracotta.png`。

这些材质只用于非房屋道具。房屋材质与地表资源独立保留；共用网格工具按照实际石材的原生宽度计算 UV，房屋原有的贴图及 UV 尺度保持原样。材质修改不影响碰撞、布局或地图手绘数据。
