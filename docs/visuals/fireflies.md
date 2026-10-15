# 萤火虫视觉调节

Godot 主场景选择 **ArtDirection → 萤火虫**，编辑器和运行时均即时应用到三个已有萤火虫区域。

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| Fireflies Enabled | 开 | 同时控制三个区域的可见性与发射 |
| Firefly Color | 原黄绿色 | 光点颜色，Alpha 也影响可见度 |
| Firefly Size | 0.045 米 | 包含柔和光晕的面片直径；实际亮核远小于此值 |
| Firefly Size Variation | 0.3 | 每个光点在基础尺寸的 0.7～1.3 倍之间随机；调整后影响后续新生粒子 |
| Firefly Energy | 2.6 | 亮度；越高越明亮，也更容易触发已有泛光 |
| Firefly Softness | 0.7 | 小亮核外柔和光晕的程度，0～1；不增加整屏模糊 |
| Firefly Pulse Strength | 0.55 | 缓慢明暗变化的幅度，0 关闭额外闪烁；原有生命周期淡入淡出仍保留 |
| Firefly Pulse Speed | 0.35 Hz | 约每 2.9 秒一次明暗循环，各光点的相位和速度略有不同 |

各区域的数量在对应 `World/Fireflies*` 粒子节点的 **Amount** 中设置，已有分布位置与漂浮运动继续使用当前配置。Local 参数按 Ctrl+S 保存；Remote 参数仅影响本次运行。

材质采用小亮核、圆形透明衰减和宽而淡的光晕，关闭全局 Glow 也不会显示方形面片。独立明暗相位使用实例编号，透明轮廓使用 UV 与 Alpha；内建变量和透明输出见 [Godot 空间着色器文档](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html)。

已验证三个区域接入、实时调节、开关与无泛光时的透明轮廓；8 个 Inspector 字段及编辑器实时调节通过检查。实机预览：[修改前](../media/firefly-preview/before.png)、[修改后](../media/firefly-preview/after.png)、[漂浮与明暗变化](../media/firefly-preview/fireflies.gif)。预览使用当前相机配置，暂时关闭镜头水滴便于观察光点。
