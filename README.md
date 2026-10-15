# HD-2D Godot 原型

当前开发项目在 **[demoWithMeowa/1](demoWithMeowa/1/README.md)**，使用 Godot 4.7.2。玩法方向是节奏舒缓、波次间可休整的生存游戏；具体内容以设计文档和已确认的实现范围为准。

## 开发入口

- 在 Godot 导入 [project.godot](demoWithMeowa/1/project.godot)。
- [正式连续地图](demoWithMeowa/1/scenes/world/world.tscn)：打开后按 F6 运行。
- [视觉测试地图](demoWithMeowa/1/scenes/previews/four_realms.tscn)：当前 F5 默认入口。
- [A02 美术预览](demoWithMeowa/1/scenes/previews/light_pierce_preview.tscn)：F6 运行，Q/E 旋转观察。
- Godot 的“地图切换”面板用于打开、运行和选择默认地图，“参数总览”面板用于调节现有功能。

## 目录

| 位置 | 内容 |
| --- | --- |
| [demoWithMeowa/1](demoWithMeowa/1/README.md) | 当前 Godot 项目、运行素材、场景、代码、配置和测试 |
| [docs](docs/README.md) | 玩法设计、功能说明、实机预览与参考图 |
| [benchmark/threejs](benchmark/threejs/README.md) | Three.js 视觉对照与实验 |
| [archive](archive/README.md) | 早期制作脚本、分析和原输出的归档 |
| `meowa-call-logs/` | 既有 Meowa 调用历史；当前记录暂停 |
| [AGENTS.md](AGENTS.md) | 项目工作约束与用户确认的范围 |

[总体玩法](docs/rpg-game-design.md) · [战斗核心设计](docs/combat-core-design.md) · [Godot 目录说明](demoWithMeowa/1/README.md)

新建的一次性脚本、下载、截图和分析数据放到 `D:\.codexfile\work\<任务名>`。Godot 自动生成的 `.godot/`、依赖和本地凭据不进入版本管理。
