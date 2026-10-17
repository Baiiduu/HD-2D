# HD-2D Godot 原型

当前开发项目在 **[demoWithMeowa/1](demoWithMeowa/1/README.md)**，使用 Godot 4.7.2。玩法方向是节奏舒缓、波次间可休整的生存游戏；具体内容以设计文档和已确认的实现范围为准。

## 开发入口

- 在 Godot 导入 [project.godot](demoWithMeowa/1/project.godot)。
- [正式地图](demoWithMeowa/1/scenes/world/world.tscn)：当前 F5 默认入口，玩法试玩统一使用此场景。
- [视觉测试地图](demoWithMeowa/1/scenes/previews/four_realms.tscn)：保留作视觉对照，打开后按 F6 运行。
- [A02 雷光贯穿](docs/gameplay/light-pierce.md)：技能与美术接入说明，正式地图中验证实际效果。
- Godot 的“地图切换”面板用于打开、运行和选择默认地图，“参数总览”面板用于调节现有功能。
- 游戏右上「设置 → 画质与显示」调整全屏、渲染分辨率、抗锯齿与光影；[参数解释与用法](docs/technical/parameters-and-styles.md#画质参数的含义)。

## 目录

| 位置 | 内容 |
| --- | --- |
| [demoWithMeowa/1](demoWithMeowa/1/README.md) | 当前 Godot 项目、运行素材、场景、代码、配置和测试 |
| [docs](docs/README.md) | 玩法设计、功能说明、实机预览与参考图 |
| [services/leaderboard](services/leaderboard/README.md) | 独立排行榜后端与接口；游戏内已计分，上传审核与平台登录待定 |
| [native/swarm](native/swarm/README.md) | 可回退的原生 CPU 原型、构建说明与接入限制 |
| [benchmark/threejs](benchmark/threejs/README.md) | Three.js 视觉对照与实验 |
| [archive](archive/README.md) | 早期制作脚本、分析和原输出的归档 |
| `deliverables/` | 已交付的离线试听页、音效包与音乐试听文件 |
| `meowa-call-logs/` | 既有 Meowa 调用历史；当前记录暂停 |
| [AGENTS.md](AGENTS.md) | 项目工作约束与用户确认的范围 |

[总体玩法](docs/rpg-game-design.md) · [战斗核心设计](docs/combat-core-design.md) · [Godot 目录说明](demoWithMeowa/1/README.md)

新建的一次性脚本、下载、截图和分析数据放到 `D:\.codexfile\work\<任务名>`。Godot 自动生成的 `.godot/`、依赖和本地凭据不进入版本管理。

可重复使用的测试和诊断入口位于项目 `tests/`、`tools/`；CPU 用无界面或固定低画质、GPU 用空场或少怪分别定位，最终恢复完整负载验收，见 [CPU 与 GPU 性能优化](docs/gameplay/attack-performance.md)。自动验证使用无界面模式；窗口、画质与手感由实际试玩验收。
