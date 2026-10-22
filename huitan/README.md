# 回弹

当前目录 `huitan/` 即完整项目，使用 Godot 4.7.2。玩法方向是节奏舒缓、波次间可休整的生存游戏；具体内容以设计文档和已确认的实现范围为准。

## 开发入口

- 在 Godot 导入 [project.godot](project.godot)。
- [正式地图](scenes/world/world.tscn)：当前 F5 默认入口，玩法试玩统一使用此场景。
- [视觉测试地图](scenes/previews/four_realms.tscn)：保留作视觉对照，打开后按 F6 运行。
- [A02 雷光贯穿](docs/gameplay/light-pierce.md)：技能与美术接入说明，正式地图中验证实际效果。
- Godot 的“地图切换”面板用于打开、运行和选择默认地图，“参数总览”面板用于调节现有功能。
- 游戏右上「设置 → 画质与显示」调整全屏、渲染分辨率、抗锯齿与光影；[参数解释与用法](docs/technical/parameters-and-styles.md#画质参数的含义)。

## 目录

| 位置 | 内容 |
| --- | --- |
| `project.godot`、`assets/`、`scenes/`、`scripts/`、`data/` | Godot 工程入口、运行素材、场景、代码和配置；[工程说明](GODOT.md) |
| `tests/`、`tools/` | 无界面回归、资源制作与打包工具 |
| [docs](docs/README.md) | 玩法设计、功能说明、实机预览与参考图 |
| [services/leaderboard](services/leaderboard/README.md) | 独立排行榜后端与接口；游戏内已计分，上传审核与平台登录待定 |
| [native/swarm](native/swarm/README.md) | 可回退的原生 CPU 原型、构建说明与接入限制 |
| [benchmark/threejs](benchmark/threejs/README.md) | Three.js 视觉对照与实验 |
| [archive](archive/README.md) | 早期制作脚本、分析和原输出的归档 |
| `deliverables/` | 已交付的离线试听页、音效包与音乐试听文件 |
| `dist/` | 本机导出包体，不进入 Git |
| `meowa-call-logs/` | 既有 Meowa 调用历史；当前记录暂停 |
| `mcp.json`、`.codex/config.toml` | 通用 MCP 配置及 Codex 入口，不绑定开发电脑路径 |
| [AGENTS.md](AGENTS.md) | 项目工作约束与用户确认的范围 |

[总体玩法](docs/rpg-game-design.md) · [战斗核心设计](docs/combat-core-design.md) · [Godot 目录说明](GODOT.md)

新建的一次性脚本、下载、截图和分析数据放到 `D:\.codexfile\work\<任务名>`。Godot 自动生成的 `.godot/`、依赖和本地凭据不进入版本管理。

仓库根目录仅保留 `.git/` 与 `huitan/`。上述文档、后端、发布文件、原生与对照实验目录以 `.gdignore` 隔离，不参与 Godot 资源扫描或正式导出；历史制作日志与归档中的旧绝对路径仅作为原始记录保留。

## MCP

在 Codex 或其他 MCP 客户端中以 `huitan/` 为工作目录。准备 Node.js 20+ 与 `npx`，Codex 使用 `.codex/config.toml`，其他客户端可导入 `mcp.json` 的 `mcpServers` 配置；支持命令、参数和工作目录的配置规则见 [OpenAI MCP 文档](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)。

Godot 加入系统 PATH，或在本机环境中设置 `GODOT_PATH` 指向引擎可执行文件；临时目录及 npm 缓存位置由本机 `TEMP`、`TMP`、`npm_config_cache` 提供，不将电脑安装路径写入仓库。配置不自动安装或覆盖项目插件，保留现有开发桥，导出与无界面测试仍不启用桥。

可重复使用的测试和诊断入口位于项目 `tests/`、`tools/`；CPU 用无界面或固定低画质、GPU 用空场或少怪分别定位，最终恢复完整负载验收，见 [CPU 与 GPU 性能优化](docs/gameplay/attack-performance.md)。自动验证使用无界面模式；窗口、画质与手感由实际试玩验收。
