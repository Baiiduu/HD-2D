# 广场路灯与环球雕塑

参考城市广场概念图制作的两件独立 Godot 立体道具。深蓝灰铸铁 `graphite.png` 与黄铜 `brass.png` 由 Meowa 纹理生成，均保留原生 64×64 RGBA；网格在编辑器和运行时生成，不重采样素材。雕塑花坛壁使用独立砌石 `../materials/masonry.png`，雕刻基座使用 `../materials/limestone.png`，盆内使用 `../materials/compost.png`，均为 Meowa 原生 64px，不复用地表铺装。材质每块覆盖 1.6 米，约 40 像素／米。

- `res://scenes/buildings/plaza_streetlamp.tscn`：阶梯底座、深色立柱、横臂、双灯头及四角灯框。实际照明、阴影、水面照明、暖光晕和金色漂浮粒子复用已有路灯框架；地面光束关闭。
- `res://scenes/buildings/armillary_monument.tscn`：蓝黑金属球、四组倾斜黄铜轨道、球面刻线、石质阶梯基座、八角花坛、花草与两盏短灯。球体和轨道均为真实三维网格，四个轨道节点具有克制的辉光。

Godot「地图切换 → 广场路灯与环球雕塑预览」运行当前世界中的样板；也可直接打开 `res://scenes/previews/plaza_landmarks_preview.tscn` 后按 F6。Q/E 旋转，R 切光影／天气，人物可走近观察。预览读取当前世界，不写人物存档，不运行挑战；样板位于独立 `LandmarkSamples` 节点，保留世界中已经摆放的建筑。

从文件系统将两件建筑场景拖入 `world.tscn`，选择根节点整体移动、绕 Y 旋转、复制，Inspector「贴合地面」对齐当前地表。根节点原点为地面底部；雕塑 +Z 侧为铭牌正面，路灯横臂沿本地 X。移动只改变当前道具的变换与碰撞，不重建地形或全图花草。

路灯可调高度、横臂宽度、灯色、能量、照明范围、光晕和阴影；灯光参数调整不重建模型。雕塑可调球体半径与高度、轨道间距与粗细、金属粗糙度、基座半径、花草／短灯开关和亮点辉光。公共路灯粒子继续通过 MapEffects/ArtDirection 管理，花草风摆跟随当前 Weather。几何参数修改只重建所选道具；关闭花草后停止雕塑的风摆更新。

雕塑的 `stone_texture` 和 `cap_texture` 分别控制花坛砌石与整石基座，替换材质只重建当前道具。
