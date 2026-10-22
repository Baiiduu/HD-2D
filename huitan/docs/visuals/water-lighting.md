# Godot 水面灯光效果

2026-10-10，当前项目 `huitan`，对照用户提供的 three.js benchmark 水面截图。

## 实现

沿用已有两水位平面反射、流水纹理和岸线泡沫，在水面材质中补充随细密水纹变化的横向碎光。用户反馈第一版缺少波光粼粼质感后，完成第二版；随后修正第二版削弱人物倒影的问题。

- 平面反射沿用 `benchmark/threejs/src/water.js` 的亮度抑制和 Fresnel 混合：压低暗处雾色，保留 HDR 灯头和光晕。波纹对倒影的扰动略增强。
- 第二版提高贴图驱动的倒影扰动至 benchmark 使用的量级，叠加随水流移动、横向拉长的细密波面法线；取消第一版稀疏随机遮罩，降低平滑宽亮斑占比，让反光分散到许多小波面上。直接高光继续使用 GGX，并读取 Godot 的真实灯光颜色、能量、衰减和阴影。
- 流动相位改为 benchmark 的双相 0.6 周期速度，保留半周期错相和交叉混合；`flow` 的长度继续控制流速，方向控制流向。水体底色压暗，让碎光与水体形成更清晰的对比。
- 纹理采样沿用 benchmark 的像素边缘抗锯齿方法，近处保持像素轮廓，远处使用连续 UV 的导数选择 mip，保留原有两相流动。
- 保留现有岸线、接触和瀑布落点泡沫，并在泡沫处减弱清水高光。

## 人物倒影与波光同时保留

第二版把强烈的细密波面扰动施加到整张反射纹理，同时沿用 benchmark 的低亮度反射抑制；人物的普通反射因此被打散、压暗。最终版对此做了以下修正：

- 普通场景辐射使用轻微、连续的倒影扰动，不再按亮度压暗人物和其他普通物体。
- HDR 超出 1.0 的高亮部分继续使用细密强扰动，从基础采样中扣除后重新加入，避免灯光能量叠加两次。
- 场景倒影的 Fresnel 使用平均水面朝向，避免细小波面法线使整个角色倒影突然变淡；混合下限校准为 0.22，以保留原有角色可见度。
- 第二版的细密法线、直接灯光 GGX 碎光和阴影计算保持不变。未调整灯位、相机、人物贴图或灯光强度。

用两个固定河岸位置对比增强波光前的原材质、第二版和最终版；冻结水纹、光晕、瀑布和人物动画，只隐藏人物反射面片生成对照。最终版的人物倒影图像差分对比度为原材质的约 100.5% / 104.0%，第二版对应约 48.4% / 37.3%。该数值验证两个机位的人物可见度，不代表所有位置的通用比例。直接高光、阴影和 R 键验证也通过。

临时脚本、截图和结果位于 `D:/.codexfile/work/water-reflection-balance/`。

同机位局部对比，左为第二版，右为最终版：

这是参考效果的 Godot 适配。两引擎的灯光衰减、泛光、曝光不同，未声称逐像素一致。地图、灯位、相机、整体光照和美术资源未因本次修改而调整。

## 调节

主场景 `ArtDirection` 节点的“水面”分组：

| 参数 | 默认值 | 作用 |
| --- | --- | --- |
| `water_highlight_strength` | 1.0 | 直接灯光高光强度；0 关闭直接高光，保留平面倒影 |
| `water_highlight_roughness` | 0.22 | 宽高光粗糙度；提高后反光更宽、更柔和 |
| `water_glint_strength` | 0.8 | 波纹碎光强度；0 保留宽高光 |
| `water_wave_strength` | 0.08 | 原有水纹法线和倒影扰动 |

原有反射质量、反射强度和 R 键倒影开关继续有效。编辑器材质预览可看直接高光，平面倒影须运行场景。

当前正式相机俯角为 10°。第二版最终预览使用原相机俯角和 11 m 距离，人物位于东侧河岸 `(24.5, 2.5)`，关闭景深和天气干扰；主场景相机、天气和灯位没有修改。金色亮斑出现的位置取决于灯位和视角。

## 验证与产物

实际使用 Godot 4.7.2 / D3D12 / Forward+ 渲染；主场景、两水位倒影和近景截图均完成，无 shader 编译或运行错误。隔离验证冻结水纹，关闭泛光和平面倒影，使用临时真实暖灯检查高光开关、灯能量、阴影遮挡、ArtDirection 参数和 R 键开关。临时灯与遮挡物只存在于验证进程。

第二版还实际运行了 three.js benchmark，检查了其渲染截图与编译后的 water fragment shader。发现第一版 Godot 的倒影 UV 扰动量过小、细光只存在于稀疏遮罩之内；本次分别修正。两者使用的水纹贴图 SHA-256 相同，没有新增或替换美术资产。

第二版隔离验证通过：864 个水面采样点，关闭直接高光后的平均亮度下降约 0.125，关闭测试灯后下降约 0.222，阴影遮挡后下降约 0.011。这些数值用于检查功能响应，不是与参考图的相似度评分。检查器参数和 R 键两次切换通过。连续捕获 24 帧，确认碎光随水纹变化。

临时脚本、编译后 shader、验证 JSON 和渲染帧位于 `D:/.codexfile/work/water-lighting/`。没有测量第二版材质的性能开销。

第二版波光演示（人物倒影修正前，最终对比见上）：

 · 。两张对比固定水面 shader 的时间为 0.75 秒；其他动态元素不是逐像素冻结。

实现入口：`huitan/shaders/water/water.gdshader`、`huitan/scripts/world/art_direction.gd`。

Shader 坐标及真实灯光衰减依据：[Godot spatial shader 文档](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)。

## 当前战区湿地面与灯光反射（2026-10-14）

用户确认常态保留雨后湿地，晴雨只改变强弱；石板和道路反射明显，草地克制。正式地图的既有 Terrain 顶面现增加一层材质湿膜，路灯以及其他点光源自动影响附近地表。原石板、道路、手绘铺装和材质数据保留，不增加覆盖平面或改动碰撞。

湿膜在世界坐标中固定分布，边缘柔和；根据画笔的湿润响应、当前湿润度与雨后下限改变覆盖。湿膜降低局部粗糙度，原材质法线逐渐过渡到贴合真实地面朝向的小波面；细碎波纹随已有地表时钟推进，雨滴法线进一步扰动倒影。波纹不只是画在地面上的亮色环，实际改变镜面受光和反射方向。原地面雨纹继续保留。

直接高光沿用 Godot 的真实光源和原生材质受光，读取灯光颜色、强度、距离衰减、Specular 和阴影；没有新增一套装饰点光源。物体与灯头倒影沿用正式地图已有 SSR，湿膜法线同时扰动该倒影。SSR 只能使用画面中可见的表面，画外或被挡住的物体倒影会缺失；光源的直接镜面高光仍由真实灯光计算。相关边界见 [Godot Environment / SSR](https://docs.godotengine.org/en/stable/classes/class_environment.html#class-environment-property-ssr-enabled)。

### 调节与恢复

正式地图 `MapEffects/ArtDirection → 湿地面与灯光反射` 默认开启。关闭 `Wet Surface Enabled` 恢复本轮前的原地表受光，保留原湿润、雨纹和原有 SSR；不关闭地图所有反射。R 切 Style 保留这组独立设置，普通视觉预览默认关闭新增湿膜。

| 参数 | 默认 | 含义 |
| --- | --- | --- |
| `Wet Surface Minimum` | 0.65 | 晴天保留的湿膜湿润下限；已有天气湿润度更高时采用较高值 |
| `Wet Surface Coverage` | 0.68 | 分布覆盖；0 关闭新增湿膜，位置保持固定 |
| `Wet Surface Patch Size` | 2.4 米 | 湿膜斑块尺度，与草地深浅变化独立 |
| `Wet Surface Roughness` | 0.10 | 较低使倒影清楚，较高使亮带更宽、更柔和 |
| `Wet Surface Reflectivity` | 0.85 | 湿膜镜面受光强度，继续受真实灯光与阴影约束 |
| `Wet Surface Ripple Strength` | 0.045 | 倒影扰动；0 保留平滑湿膜，原地面雨纹继续播放 |
| `Wet Surface Ripple Speed` | 0.65 | 连续细波推进速度；0 停止额外细波，雨滴仍由天气控制 |
| `Wet Surface Grass Response` | 0.04 | 草地相对硬质表面的湿膜响应；0 保留原草地受光 |

参数总览可搜索「湿地面」「湿膜」「倒影波纹」。硬质表面仍读取各画笔的 `Wet Response` 与已有粗糙度图。当前用户关闭了天气，常态反射和细波仍运行；本轮没有修改该天气开关、雨量、声音、主光或灯位。

### 当前镜头实机

以下采用本轮读取到的实际场景配置：FOV 28°、距离 15 米、俯角 25.414°、焦点 0.75 米、景深关闭，1280×800。四种 Style 的前后仅切湿膜开关，人物、镜头、主光与曝光一致。雨滴、粒子和环境动态自然推进，截图原样保留；该镜头是当前场景保存值，不改写历史水体预览的相机记录。

![夜晚路灯与点光源湿地倒影](../media/wet-surface-preview/night-after.png)

![湿地倒影原生动态](../media/wet-surface-preview/motion.webp)

| Style | 原地表 | 湿膜开启 |
| --- | --- | --- |
| 原始增强 | [之前](../media/wet-surface-preview/original-before.png) | [之后](../media/wet-surface-preview/original-after.png) |
| 黄金 | [之前](../media/wet-surface-preview/golden-before.png) | [之后](../media/wet-surface-preview/golden-after.png) |
| 细雨光影 | [之前](../media/wet-surface-preview/rain-before.png) | [之后](../media/wet-surface-preview/rain-after.png) |
| 夜晚 | [之前](../media/wet-surface-preview/night-before.png) | [之后](../media/wet-surface-preview/night-after.png) |

[临时开启实际降雨](../media/wet-surface-preview/rain-enabled.png) · [西侧路灯与草地](../media/wet-surface-preview/west-lamp.png) · [旋转 90°](../media/wet-surface-preview/orbit-90.png) · [180°](../media/wet-surface-preview/orbit-180.png) · [270°](../media/wet-surface-preview/orbit-270.png)。降雨验证只存在于验证进程，正式场景的天气开关保留。

### 验证

Godot 4.7.2 / D3D12 / Forward+，RTX 3050。新增实际场景检查 146 项通过，确认四种 Style、全部参数绑定、关闭恢复、天气关闭时细波时钟、独立镜头、法线、簇影、地形与画笔数据保持。新增原生像素检查 9 项通过，确认真实点光源 Specular、颜色、开关、遮挡、波纹推进／停止、覆盖归零和草地独立恢复；使用生产 Terrain 着色器与当前镜头参数。

隔离像素检查中，关闭点光源或用仅投影的遮挡物挡住灯光后，采样区高亮像素均为 0；停止波纹的两帧差异为 0。战区基础 157 项、地表材质图 127 项与参数索引通过。最终原生截图和验证日志无 Shader、解析或运行错误。

本轮没有新增反射相机、Viewport 或灯光，也没有增加逐帧地图／光源扫描。复用既有 SSR，未声称测量全部驱动或密集战斗下的性能。实现入口为 `shaders/includes/wet_surface.gdshaderinc`、`shaders/terrain/terrain.gdshader` 和 `scripts/world/art_direction.gd`。中间副本、验证日志与原生帧位于 `D:\.codexfile\work\wet-surface-20261014`。
