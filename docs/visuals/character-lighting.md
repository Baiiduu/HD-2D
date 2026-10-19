# 主角受光适配

当前主角是固定 Y 轴朝向相机的 Sprite3D。原生平面法线在背光时失去直接漫反射，而草地已有朝上受光与背光响应，二者容易脱节。

主角材质柔化侧光截止、加入少量世界朝上的受光响应，并按透明轮廓产生窄背光亮边。所有直接光使用现有灯光颜色、距离衰减和阴影遮挡，不增加光源或常态自发光。人物走入建筑阴影时，主光贡献随真实遮挡减弱；原场景环境光继续保留。水面倒影共享同样参数。

正式 World 的 `assets/finalart/` 人物通过 `assets/surface_normals/manifest.json` 绑定与各动画帧对应的独立法线，覆盖待机、行走、普攻与弹射。法线以原轮廓生成克制的体积起伏，尺寸和透明度与原帧一致，不修改颜色图、动画、像素密度或脚底锚点。命中与清波演出的短暂剪影仍使用各自开关，与常态场景受光独立。

## Godot 参数

打开 `scenes/world/world.tscn`，选择 `Player → Sprite → 人物受光`，或在参数总览「人物」中调整。下表为共享材质默认值；World 保留自身的侧光 0.45、顶部受光 0.55、背光亮边 0.08。亮边只在真实光照到轮廓时出现，仍受阴影遮挡。

| 参数 | 默认 | 含义 |
| --- | --- | --- |
| Lighting Enabled | 开 | 开启适配；关闭恢复原生 Sprite3D 材质 |
| Light Wrap | 0.30 | 扩大侧光的柔和过渡；越大越柔，过高会削弱明暗对比 |
| Top Light Response | 0.40 | 接住上方灯光，让人物与地面受光颜色更一致；过高会显平 |
| Back Rim Strength | 0.12 | 背光照到轮廓时的窄亮边；0 关闭 |
| Local Light Response | 1.0（World：1.25） | 只调当前人物接收的全向灯和聚光灯强度，1 为原强度，0 关闭；仍遵守真实范围、衰减和阴影，不改变方向光与环境光 |

参数可用 Inspector 的恢复默认值操作逐项恢复。该材质目前只接到主角，不改变 NPC、灯光、地形或水面材质参数。

人物法线的地图开关与强度沿用 `VisualSample → 边缘衔接与独立法线 → Character Normals Enabled / Character Normal Strength`，默认开启、强度 0.4。更换动作帧后运行 `tools/build_surface_normals.py --world-character-only` 更新对应法线；该选项保留其他地表、建筑及人物的法线和导入 UID。

World 的 `MapEffects/WorldEnvironment` 默认开启 SSAO、SSIL、SSR；游戏「设置 → 画质」保存的本机选择会覆盖这些默认值。人物使用 Alpha Scissor 裁切参与不透明深度与法线通路，接收环境遮蔽与间接光，也作为湿地面 SSR 可读取的可见物体。SSR 的反射强弱仍由湿地面的材质控制，人物本身保持粗糙像素材质。水池已有的平面镜像继续独立运行，镜像人物同步局部光响应。三个屏幕空间效果由当前视口统一计算，不增加人物专属全屏处理或重复灯光；屏幕外、被不透明物体挡住的部分无法由 SSR 完整反映。[Godot 环境效果](https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html)、[透明材质与 Alpha Scissor](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html#transparency)。

## 验证与预览

- D3D12 / Forward+ 实际运行无脚本或着色器编译报错。
- 零环境光测试：背面灯光可以照到主角；关灯或加入遮挡后主角变暗。
- 26 个动画帧的左右翻转、材质开关、参数设为 0、水面倒影同步、保存重开通过检查。
- 同一位置的相机 -45°、0°、45° 对照中，绘制调用数分别仍为 346、311、308。后台编辑器负载变化较大，不以当前帧耗时推断性能百分比；新增开销主要是轮廓的四次邻近透明度采样。

预览：[原效果](../media/character-lighting-preview/before.png)、[适配后](../media/character-lighting-preview/after.png)、[旋转预览](../media/character-lighting-preview/orbit.gif)。预览暂停雨与粒子、关闭景深并固定水面时间，以便观察受光差异；运行默认效果保留。

这是二维贴片的受光近似。人物各部位的精确体积、材质粗糙度与自遮挡，仍需要对应的角色法线或真正的三维几何。
