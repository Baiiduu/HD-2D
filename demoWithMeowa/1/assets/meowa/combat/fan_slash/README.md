# A01 斩击资源

美术来自 Meowa：透明起始斩光与受左／中／右姿态约束的八帧横扫。动画原尺寸为 640×640，原时长 0.8 秒；运行时按独立攻击组件的扫击时长播放。

`slash.png` 是原生帧组成的 4×2 RGBA 图集；`frames.tres` 提供非循环 `slash` 动画。原始图片与动画位于 `source/`，该目录使用 `.gdignore`，避免 Godot 将动画 WebP 当成静态纹理导入。运行时只读取 PNG 图集，显式按当前 AtlasTexture 区域采样。

参数、行为和验证见 [A01 自动扇击](../../../../../../docs/fan-auto-attack.md)。
