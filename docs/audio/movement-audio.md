# 人物脚步、起跳与落地

采用已确认的轻柔自然拟音。草地是短促的叶片摩擦，卵石路是温润的触地声；石板、泥土、木板、金属保留各自的质感。起跳以衣料摩擦和很轻的蹬地声为主，落地使用实际承重面的声音，并随下落速度调节力度。

正式地图、视觉测试地图和房屋预览已接入 `Player/MovementAudio`。声音来自 Meowa，原始 MP3 保留在 `demoWithMeowa/1/assets/meowa/audio/movement/source/`；游戏使用经过高频柔化、响度平衡和首尾淡化的单声道 WAV。现有背景音乐、风雨和相机配置继续沿用。

## 地表过渡与节奏

- 跑步音效跟随 8 帧动画的第 0、4 帧触地，动画速度取实际移动速度。停步、空中、顶墙不持续播放脚步。
- 地面查询先确定人物实际站立的碰撞面，再识别 Terrain 的底材和覆盖层。道路与泥土使用和着色器一致的 4×4 图集索引、透明阈值和覆盖顺序。
- 台地边缘的垂直射线若落空，使用身体真实的脚下碰撞点；不会因为脚下射线落空短暂插入默认石面声。
- 脚下中心与四周共五次采样，在可见的材质边缘混合两种声音；权重再按时间平滑。每一步采用等功率混合，保持过渡时的响度。
- 同类多条素材避免连续重复，并添加很小的音高和音量变化。两次脚步可以保留彼此的短尾音。
- 起跳、落地各触发一次。出生点下落安置不播放落地声；跳到另一种地面时，落地直接读取新的材质。
- Q/E 旋转镜头不会改变人物音效的音量和地表判断。

## Godot 参数

在地图中选中 `Player/MovementAudio` 即可调节。要修改所有地图的通用默认值，打开 `scenes/audio/player_movement_audio.tscn`。

| 参数 | 默认值 | 含义 |
|---|---:|---|
| Enabled | 开启 | 动作音效开关 |
| Volume Db | -8 dB | 人物动作音效总音量 |
| Step Volume Db | 0 dB | 脚步相对于总音量的增益 |
| Footprint Radius | 0.22 米 | 脚下混合采样半径；越大，材质过渡区域越宽 |
| Surface Blend Time | 0.18 秒 | 材质权重的平滑时间常数；约三倍时间接近新材质的 95%；0 立即跟随采样 |
| Contact Frames | 0、4 | 跑步触地帧；更换动画时可调整 |
| Minimum Step Interval | 0.12 秒 | 防止快速转向造成重复踏步；实际也按移动速度限制间隔 |
| Pitch Variation | 0.04 | 音高上下变化约 4% |
| Volume Variation Db | 0.6 dB | 每一步的轻微音量变化 |
| Jump Volume Db | -4 dB | 起跳衣料声相对于总音量的增益 |
| Landing Volume Db | +1.5 dB | 落地声相对于总音量的增益 |
| Landing Reference Speed | 5.6 米/秒 | 普通跳跃的落地力度基准；较高落差最多增加约 3 dB |
| Landing Pitch | 0.88 | 落地触地声的音高，略低于跑步 |
| Audio Bus | Master | 输出总线，可指定项目中其他音效总线 |
| Sounds | movement_sounds.tres | 各种材质和起跳素材列表，可展开替换或增加同类变体 |

地表声音对应也可逐项调整，默认城市底材为卵石、赛博底材为金属、古风底材为石板、自然底材为草地。道路覆盖层为卵石，泥土覆盖层为泥土，桥面为木板。未标记的普通碰撞面使用 Fallback Surface，默认石板。

其他独立碰撞地面可在碰撞体或具体 `CollisionShape3D` 的元数据中添加整数 `movement_surface`：`0` 石板、`1` 卵石、`2` 草地、`3` 泥土、`4` 木板、`5` 金属。房屋门廊已标记木板，台阶标记石面；建筑几何未修改。

## 验证

`tests/test_movement_audio.gd` 检查六类素材、真实道路图集边缘的混合、硬边界下的时间平滑、出生安置静音、跑步、停步、顶墙、起跳、空中静音、落地和开关。运行方式：

```powershell
& 'D:\Project\godot\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'D:\Project\HD-2DMap\demoWithMeowa\1' --script res://tests/test_movement_audio.gd
```

另在原生 Forward+ 正式地图中按实际开发相机参数检查跑动、材质过渡、台地边缘、跳跃和 Q/E 旋转；[实际游戏音效试听](../media/movement-audio-preview/gameplay.wav) 单独录制了人物声音，便于辨认变化。录音约 9.8 秒，包含卵石路到草地的跑步、走下台地、起跳与落地；中间安静的一段是停步后旋转镜头。正式地图、视觉测试地图和房屋预览的场景加载检查均通过。
