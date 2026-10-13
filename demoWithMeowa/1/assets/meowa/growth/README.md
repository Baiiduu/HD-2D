# 经验宝石素材

2026-10-13。按经验 UI 参考的三种外形，通过 Meowa 像素通用生成制作，原样裁切为 cyan.png、violet.png、amber.png。三件都是独立透明 PNG，原图像素保留，不再像素化或缩小重制；尺寸见 components.json。

现已接入 `scenes/growth/experience_pickup.tscn`。颜色与外形不决定实际经验奖励；依据节点的 `amount` 切换视觉，默认紫色／暖金阈值为 10／30，可配置，合并经验后同步刷新。

使用最近邻过滤，青蓝世界高度默认 0.32 米，其余两档逐档放大 15%；高度、漂浮、阴影和尾迹均可调。落地阴影与吸收微光位于 `assets/meowa/ui/experience`，保持独立。参数与当前开发镜头实机图见项目 `docs/experience-visuals.md`。
