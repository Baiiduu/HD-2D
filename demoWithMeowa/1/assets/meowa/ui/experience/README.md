# 经验 HUD 与拾取反馈素材

2026-10-13。Meowa 从经验 UI 参考提取的新增组件；升级选择仍复用已有卡片、图标槽、标题装饰和确认按钮，本目录没有这些组件的替代版本。

- frame.png：薄暖金边框和暗槽。
- fill.png：满长度青绿填充，运行时应裁切进度，不能把整条图片横向压缩。
- badge.png：等级底片，等级文字独立绘制。
- glint.png：端点微光。
- absorb.png：吸收闪光。
- shadow.png：柔和落地阴影。

source.png 为返回的 RGBA 总图。组件从原始总图裁切，保留低 alpha 边缘；尺寸见 components.json。素材外部透明，内部暗槽接近不透明，可用已有 `shaders/attribute_hud.gdshader` 的 background_opacity 单独淡化暗底，避免金属边框一起变淡。

已通过 `scenes/ui/experience_hud.tscn` 接入正式地图的成长节点。订阅 `RunGrowth.state.changed` 获取 level、experience、required_experience()；拾取脉冲监听 `experience_collected(amount)`。低进度、满进度、MAX 和重置都复用同一套外框与填充；数字、比例与卡片数量不写进图片。

默认放在血蓝条下方，跟随属性条位置和菜单显示状态，也支持独立位置；宽度、间距、暗槽透明度及光效强度可调。具体参数与实际运行截图见项目 `docs/experience-visuals.md`。
