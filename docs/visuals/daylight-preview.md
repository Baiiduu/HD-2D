# 慢速日照演示

打开 Godot 主场景，选择 `DaylightPreview`。该试作现已默认关闭并保留作对照；当前默认视觉使用 `AtmosphericLight` 的局部空气光。手动开启日照时，暖色方向光缓慢往返，移动云影与草丛、灯杆、建筑投影共同落到地形上。复用原有 `Moon` 方向光，路灯、人物受光适配和水面倒影继续生效。

## 播放与对照

| 参数 | 默认 | 含义 |
| --- | --- | --- |
| Enabled | 关 | 总开关；关闭恢复 ArtDirection 的月光、环境光和天空参数 |
| Playing | 开 | 自动演示；关闭同时暂停日光与云影，再拖动 Progress 对照 |
| Progress | 0.35 | 起点 0 到终点 1；可在编辑器或运行时远程 Inspector 调节 |
| Travel Seconds | 180 秒 | 从起点到终点的时间；完整往返为 360 秒，两端缓停 |
| Animate In Editor | 关 | 编辑器自动播放；默认编辑器保持静止，手动拖进度即预览 |

运行时按 L 选择旧光照预设，会关闭演示并交还光照控制。重新开启 Enabled 即回到日照。暂停后拖动进度，再恢复 Playing 会从当前时刻继续。

## 光影参数

| 参数 | 默认 | 含义 |
| --- | --- | --- |
| Azimuth Range | -65° 到 65° | 主光扫过的世界方位；不跟随 QE 镜头 |
| Low / Peak Elevation | 20° / 38° | 起止与中段的俯照角；角度低时投影更长 |
| Warm / Noon Color | 暖金 / 浅暖白 | 起止时刻与中段的光色 |
| Sun Energy | 1.5 | 主光强度；中段最强，起止为其 75% |
| Shade Color / Energy | 冷蓝 / 0.32 | 阴影里的填充光；降低强度可强化明暗交错 |
| Sun Softness | 1.2° | 主光角直径；越大越柔，过高会增加原生软阴影颗粒感 |
| Sun Shadow Opacity | 0.75 | 主光阴影深浅，同时影响云影与物体投影；路灯阴影独立 |
| Sky Blend | 0.5 | 现有天空向浅蓝与暖地平线的过渡程度 |
| Cloud Shadows | 开 | 云影独立开关 |
| Cloud Coverage | 0.45 | 云层噪声的遮挡阈值；0 无云、1 满覆盖，中间值不是精确面积百分比 |
| Cloud Size | 9 米 | 云团尺度，大于细小草影 |
| Cloud Velocity | (0.12, 0.05) 米/秒 | 世界 X/Z 方向速度；暂停时不移动 |
| Cloud Offset | (0, 0) 米 | 手动平移云影，便于固定日光时刻调试 |

月光恢复值增加了 ArtDirection 的 Moon Softness、Moon Shadow Opacity、Moon Glow Color，避免保存编辑器日照预览后丢失月光基线。参数可逐项用 Inspector 恢复默认值。

## 实现、验证与预览

云层为一张不显示本体、仅投影的程序化高空面。使用 [Godot 原生阴影](https://docs.godotengine.org/en/4.7/classes/class_geometryinstance3d.html)，不把明暗画进地面颜色。云影、人物、地形与倒影共享场景灯光遮挡。没有新增光源、反射摄像机或外部美术资产。新增一张细分云层面，复用既有方向光阴影通道；移动主光还会更新阴影与现有天空反射，开销不等同于静止月光。

实际 D3D12 / Forward+ 运行验证了暂停/继续、0/1 进度、平滑往返、0 值、关闭恢复、保存重开、L 预设切换和 QE 世界方向稳定。移动云层时，固定视角的地表采样存在亮度变化；原有水面高光参数保持原值。阴影仍受原生阴影分辨率、滤波和贴片几何近似限制，未以后台编辑器负载下的帧耗时推断性能百分比。

脚本与着色器检查通过。使用 `--quit-after` 强制结束默认场景时仍有 4 个 ObjectDB 实例释放警告；相同退出方式运行接入前的场景也有同样警告，本次没有扩大该问题。

[原月光](../media/daylight-preview/before.png) · [日照](../media/daylight-preview/after.png) · [日光扫过](../media/daylight-preview/sun-sweep.gif) · [固定光位的云影移动](../media/daylight-preview/cloud-drift.gif)

动态预览加速了时间，隐藏雨和粒子、固定水面与人物动画、关闭景深，便于看清阴影变化。正式场景保留原来的天气与公共路灯金色颗粒。
