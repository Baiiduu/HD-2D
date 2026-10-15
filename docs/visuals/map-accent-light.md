# 地图局部光斑

正式地图当前关闭 `MapEffects/AtmosphericLight.enabled`，自动地面光斑和远景装饰灯均不参与照明；基础照明由方向光与环境光承担。旧参数和以下对照保留，重新勾选 Enabled 可对比，Style 切换不会自动开启该总开关。

正式地图使用“全局光维持氛围，局部暖光点缀”的组合。已撤回均匀照亮全图的暖色方向补光：草地、道路和花草之间保留暗部，局部亮斑继续使用原有的暖色、斑驳投影与柔和原生阴影。地表光的体积雾能量为零，远景空气光保持原来的独立配置。

实机效果：[出生点](../media/map-accent-preview/spawn.png) · [西侧草地](../media/map-accent-preview/west.png) · [东侧](../media/map-accent-preview/east.png) · [旋转视角](../media/map-accent-preview/east-qe.png) · [北侧](../media/map-accent-preview/north.png) · [南侧](../media/map-accent-preview/south.png)。

## 调节位置

在正式地图选中 **MapEffects → AtmosphericLight**。运行中可在 Remote Inspector 修改；保存配置请在本地场景 Inspector 修改。

| 参数 | 当前默认 | 含义 |
| --- | --- | --- |
| Map Accents Enabled | 开 | 在整张地图分布局部亮斑；关闭恢复原来的三个固定补光位置 |
| Follow Global Direction | 开 | 点缀光与 ArtDirection 的主光同方向。关闭后使用 AtmosphericLight 的 Azimuth / Elevation |
| Surface Energy | 2.2 | 亮斑强度，0 关闭全部地表点缀，远景保留 |
| Light Color | 暖金 | 地表点缀与远景空气光共用颜色 |
| Beam Width | 4.2 米 | 局部光斑的覆盖尺度，越小越集中 |
| Spacing | 11 米 | 地图中光斑的间隔，越大越稀疏；最低按 4 米计算，避免过度重叠 |
| Breakup Strength | 0.7 | 光斑内部的明暗变化；0 恢复平滑受光 |
| Shadows Enabled / Shadow Softness | 开 / 0.25 米 | 物体遮挡产生的真实阴影与软硬程度 |
| Source Height | 12 米 | 光源距所在台地的高度 |
| Accent Radius | 18 米 | 人物周围启用点缀光的范围，最后 6 米逐渐减弱 |
| Accent Fade Time | 0.8 秒 | 进入 / 离开区域时淡入淡出的时间 |
| Max Active Accents | 6 | 同时渲染的局部灯上限；需要降低阴影开销时可先尝试 3～4 |

全局方向仍在 **MapEffects → ArtDirection → Moon Azimuth / Moon Elevation** 调节。局部亮斑跟随这个方向，不额外改变主光颜色、能量、环境光或曝光。远景光束仍使用 AtmosphericLight 的独立方向，始终放在地图外。

建议先用 **Surface Energy、Beam Width、Spacing** 调节亮斑强度、大小和疏密，再调 **Breakup Strength / Shadow Softness**。全局光负责让暗部可读；提高局部亮度时无需一起提高环境亮度。

## 分布与性能

光斑位置由地图范围、AtmosphericLight 的 XZ 位置和 Spacing 确定，使用固定种子的轻微偏移打散规则排列；原来的庭院横排位置保留。每个光斑按 TerrainData 的台地高度放置，修改地图范围或高度会自动更新。人物移动只改变附近灯的启用状态和淡入淡出，QE 旋转不重排光位。建筑和花草通过原生阴影遮挡受光。

当前是按范围与台地自动分布，尚未根据道路、花丛或任务地点进行语义选点；后续可以通过位置与疏密继续调整构图。

灯光池按 Max Active Accents 限制数量，不为地图中每个候选光斑常驻一盏活动灯。旧光先淡出，再将已熄灭的灯分配到新位置；固定光位不重复更新 Transform。真实阴影仍有 GPU 开销，这次没有做稳定的性能基准或承诺性能提升。

视觉预览地图 `four_realms.tscn` 保留原来的三个固定局部光。正式地图通过 `scenes/shared/map_effects.tscn` 启用地图点缀模式。

## 验证

`tests/test_map_accents.gd` 验证了地图多区域启用、光源数量上限、固定世界坐标、台地高度、与主光同步、视角旋转、平滑过渡、零值和阴影开关、地图扩展及原局部模式恢复。

实际 D3D12 / Forward+ 预览使用正式地图、当前跟随相机与景深基准，检查了出生点、东南西北区域和 90° 旋转视角。未改变地表纹理、植被、建筑布局或相机基准。
