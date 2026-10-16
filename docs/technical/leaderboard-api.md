# 自建排行榜接口

服务代码在 `services/leaderboard/`，独立于 Godot，提供成绩存储与查询接口。正式地图已接入本地计分与 HUD，尚未向 HTTP 接口上传；赛季、奖励、TapTap 登录和客户端成绩审核仍待确定。

## Godot 局内计分与 HUD

正式战斗通过 `WavePrototype/RunScore` 订阅真实死亡与清波事件，数值来自 `demoWithMeowa/1/data/score/default_score.tres`。规则在开局复制，本局不受中途编辑影响；重试清零，休整与升级保留，死亡／撤退保留实际已得分。没有按等待时间或空反弹奖励分数。

| 项目 | 首版参数 |
| --- | ---: |
| 普通怪 | 10 |
| 特殊怪、裂瓷壶兽本体 | 20 |
| 分裂幼体 | 2；不累计弹射连杀档位 |
| 完整清波 | 100，每波仅一次 |
| 同次弹射击杀 3／6／10 只 | 累计额外 5／10／20；晋档只补差额 |

同次弹射最多 20 点表现分，持续绕群与反弹不重置档位。基础击杀分接受全部真实致死来源，表现分仅计入该次弹射剑术及仍在该次飞行内命中的奔雷。奔雷保存触发发射编号，落地后的尾伤与上一发残留雷潮只给基础分；剑术连续路径保留实际飞行段编号，避免飞行末帧漏算。每个怪物实例去重，异常移除与重试清理不记分；分裂仍沿用先登记幼体再结束母体的既有流程。有限最后一波在结算快照冻结前补齐清波分，避免既有 `run_ended` 早于 `wave_cleared` 的顺序漏分。

巨量怪潮模拟不计分，HUD 明确显示“模拟 · 不计分”。异常中断保留本地已得分，但标记不可提交。`RunScore.state.snapshot()` 提供总分、击杀／清波／表现分拆分、规则版本与结果资格，后续结算和联网复用；本地资格标记不代替服务端审核。

右上 `WavePrototype/ScoreHUD` 使用现有 Press Start 2P 字体，奶油白数字与短暖金下划线。连续入账默认 0.3 秒合并为一次 `+N`，计数过渡 0.22 秒，变化位提亮并上弹 2.4 逻辑像素后收束；整块面板保持固定。清波与弹射档位提示有优先级，结束时刷新待显示分数；真实计分立即生效，不等待动效。以上表现参数可在该节点 Inspector 调整。当前没有最高分存档、赛季、奖励或自动上传。

[已确认参考图](../references/score-ui/score-hud-direction-v1.png) · [实际数字动效，演示数值](../media/score-ui-preview/score-counter.webp) · [声音设置](../media/score-ui-preview/settings-audio.png) · [环绕设置](../media/score-ui-preview/settings-orbit.png)

`tests/test_run_score.gd` 检查计分去重、规则快照、封顶、旧发射尾伤、幼体、模拟和最终清波；`tests/test_score_settings.gd` 使用正式地图与真实怪物死亡检查计分接入、最终 HUD、设置页、试听切换、ESC 不撤退和小窗口滚动。

新增计分与设置共 38 项断言通过；基础剑术、人物弹射、调音与环绕诊断的相关回归通过。仓库旧雷潮测试仍有两处固定“10 经验升级”的断言，与现行首级 12 经验门槛不符；临时副本改为读取实际所需经验后 110 项通过，未改经验数值或原用例。音效独立测试退出时仍出现资源释放告警，未据此宣称全项目退出告警已消除。

正式部署选用 **FastAPI + PostgreSQL 18 + SQLAlchemy／psycopg 3**，直接运行 Python 服务并连接原生 PostgreSQL，本地开发保留 SQLite。先用一个 API 进程与一个数据库，无需增加 Redis 或常驻游戏房间服。PostgreSQL 18 处于正式支持周期，后续小版本更新按维护流程进行。[官方版本状态](https://www.postgresql.org/support/versioning/)

## 本地启动

需要 Python 3.13 或更新版本。在仓库根目录运行：

```powershell
& .\services\leaderboard\start.ps1
```

脚本安装依赖后以前台方式启动，Ctrl+C 停止；再次运行复用原数据库与密钥。默认地址：

- 交互文档与接口调试：<http://127.0.0.1:8080/docs>
- OpenAPI 协议：<http://127.0.0.1:8080/openapi.json>
- 存活与数据库连接检查：<http://127.0.0.1:8080/health>

本机文件集中在 D 盘：

| 路径 | 用途 |
| --- | --- |
| `D:\.codexfile\work\leaderboard-api\local.env` | 本机数据库地址及首次启动生成的随机写入密钥 |
| `D:\.codexfile\work\leaderboard-api\leaderboard.sqlite3` | 本地 SQLite 数据，运行时可能另有 WAL／SHM 文件 |
| `D:\.codexfile\cache\leaderboard-api\venv` | 独立 Python 环境 |
| `D:\.codexfile\cache\leaderboard-api\pycache` | Python 编译缓存 |
| `D:\.codexfile\cache\pip` | 包缓存 |

可用 `-Port 8081`、`-ConfigPath <配置文件>`、`-RuntimeDirectory <环境目录>` 调整启动参数。默认只监听本机；`-ListenAddress` 可调整监听地址。脚本尊重已设置的环境变量，环境变量优先于配置文件。

## 接口

所有成绩均为调用方已经算好的整数，服务不推导波次或击杀分。创建榜单时确定高分优先 `desc` 或低分优先 `asc`，之后不允许改排序规则。榜单 ID 可自行隔离玩法、版本或未来赛季，当前不预置业务榜单。

| 方法与路径 | 用途 | 权限 |
| --- | --- | --- |
| `GET /health` | 服务与数据库是否可用 | 公开 |
| `POST /v1/leaderboards` | 创建榜单 | 服务端密钥 |
| `GET /v1/leaderboards?limit=100&offset=0` | 列出榜单 | 公开 |
| `POST /v1/leaderboards/{board_id}/scores` | 提交成绩并更新个人最好成绩 | 服务端密钥 |
| `GET /v1/leaderboards/{board_id}/scores?limit=20&offset=0` | 分页榜单与排名 | 公开 |
| `GET /v1/leaderboards/{board_id}/players/{player_id}` | 个人最好成绩及排名 | 公开 |
| `DELETE /v1/leaderboards/{board_id}/players/{player_id}/score` | 撤除一条最好成绩 | 服务端密钥 |

分页上限为每页 100 条，offset 为 0～10000。榜单及个人查询不存在时返回 404，空榜单返回空数组。业务错误使用 `detail.code` 与 `detail.message`，字段校验错误返回 422。

### 创建榜单

```json
{
  "id": "demo-score-v1",
  "title": "开发测试榜",
  "sort_order": "desc"
}
```

`id` 长度 1～64，只允许小写字母、数字、下划线与连字符，首字符须为字母或数字；`title` 为 1～100 字符。同 ID 再次创建返回 409。

### 提交成绩

```json
{
  "submission_id": "ad0cd4cd-7204-4c59-99e9-c5cc5966328a",
  "player_id": "local:test-player",
  "display_name": "测试玩家",
  "score": 1200,
  "metadata": {"example": "optional data, not a scoring rule"}
}
```

- `submission_id` 是调用方生成并保存的 UUID。一次提交重试时复用；新的成绩生成新的 UUID。唯一性范围为同一个榜单。
- `player_id` 是不绑定平台的稳定标识，长度 1～128，允许 ASCII 字母、数字、`_`、`:`、`.`、`-`，首字符为字母或数字，区分大小写。后续由真实登录身份映射，不能直接信任客户端自由填写。
- `score` 是严格整数，范围为 ±9007199254740991，保证 Godot 与 JavaScript JSON 互通时精确。浮点数、布尔值与超范围值会拒绝。
- `display_name` 可省略，最多 48 字符；去除两端空白后不得为空，不接受控制字符。
- `metadata` 可省略，须为 JSON 对象，UTF-8 序列化后最多 8192 字节，不允许 NaN 或无穷数。可保存以后确认的附加信息，不参与排名。内容会随榜单公开，不应放入私密资料。

成功响应示例：

```json
{
  "board_id": "demo-score-v1",
  "submission_id": "ad0cd4cd-7204-4c59-99e9-c5cc5966328a",
  "player_id": "local:test-player",
  "submitted_score": 1200,
  "personal_best": 1200,
  "best_updated": true,
  "replayed": false
}
```

仅更优成绩替换榜单条目，较差或相同成绩保留原昵称、附加数据与达成时间。相同 UUID 与相同内容重试返回首次提交结果，`replayed=true`；UUID 被不同内容复用则返回 409。`personal_best` 是首次处理该提交时的最好成绩快照，重试不会改成后来更新的分数。

### 排名与撤除

同分并列，采用 `1、1、3` 排名。同分展示依次按服务端达成时间、玩家 ID 排序；时间统一 UTC，接口返回带 `Z` 的时间。同一次分页查询的条目、总数与排名读取同一事务快照；跨页期间有人提交时，offset 分页可能变化，后续若需要冻结榜单再扩展。

撤除成绩保留提交回执，旧 UUID 的重试不能恢复已撤除的成绩；新的 UUID 仍可提交，不等同封禁账号。暂未加入封禁、榜单删除、历史成绩浏览或赛季结算。

## 本机调用示例

以下例子只访问自己刚启动的本地服务，不输出密钥。重复使用同一个榜单 ID 时，创建步骤会返回 409；可以换一个 ID。

```powershell
$configPath = 'D:\.codexfile\work\leaderboard-api\local.env'
$tokenLine = (Select-String -LiteralPath $configPath -Pattern '^LEADERBOARD_API_TOKEN=').Line
$headers = @{ Authorization = 'Bearer ' + $tokenLine.Split('=', 2)[1] }
$baseUri = 'http://127.0.0.1:8080/v1/leaderboards'

$boardBody = @{ id = 'demo-score-v1'; title = '开发测试榜'; sort_order = 'desc' } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri $baseUri -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($boardBody))

$scoreBody = @{
    submission_id = [guid]::NewGuid().ToString()
    player_id = 'local:test-player'
    display_name = '测试玩家'
    score = 1200
    metadata = @{}
} | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "$baseUri/demo-score-v1/scores" -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($scoreBody))
Invoke-RestMethod -Uri "$baseUri/demo-score-v1/scores"
Invoke-RestMethod -Uri "$baseUri/demo-score-v1/players/local:test-player"
```

## 鉴权与后续 Godot 接入

写入请求使用 `Authorization: Bearer <LEADERBOARD_API_TOKEN>`，Swagger 中通过 Authorize 填入密钥即可测试。未配置密钥时写入关闭并返回 503；密钥错误返回 401；明显的示例密钥或不足 32 字符的配置会拒绝启动。

当前密钥仅用于可信服务、管理和本机调试，**不能打包到 Godot／Android 客户端**。它既不证明玩家身份，也不能判断一份成绩是否真实。后续确定账号与上线审核方案后，再增加玩家凭证验证、结算审核与客户端提交入口；现有榜单查询和存储层可继续使用。当前没有声称实现反作弊或正式玩家登录。

## PostgreSQL 部署

在主机安装 Python 3.13+ 和 PostgreSQL 18，创建应用账号 `leaderboard` 及其拥有的同名数据库。API 只使用应用账号，不需要数据库超级用户权限。管理员通过 PostgreSQL 自带工具执行，例如：

```sh
createuser --pwprompt --no-superuser --no-createdb --no-createrole leaderboard
createdb --owner=leaderboard leaderboard
```

这些命令须以有建角色和建库权限的数据库管理员身份运行，已有账号和数据库时跳过。数据库由 PostgreSQL 原生服务维护，数据保存在其配置的数据目录。

将服务目录的 `.env.example` 复制为本机私有配置文件，填入真实应用账号密码和随机 API 密钥：

```dotenv
LEADERBOARD_DATABASE_URL=postgresql+psycopg://leaderboard@127.0.0.1:5432/leaderboard
LEADERBOARD_DATABASE_PASSWORD=<database password>
LEADERBOARD_API_TOKEN=<random server token of at least 32 characters>
```

Windows 上先准备好配置文件，例如 `D:\.codexfile\work\leaderboard-api\postgres.env`，然后启动：

```powershell
& .\services\leaderboard\start.ps1 -ConfigPath 'D:\.codexfile\work\leaderboard-api\postgres.env'
```

其他系统在服务目录建立 Python 虚拟环境，安装依赖后直接运行：

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m uvicorn leaderboard.app:app --host 127.0.0.1 --port 8080 --env-file /etc/leaderboard.env
```

示例中的 `/etc/leaderboard.env` 需事先创建并限制读取权限。常驻运行时由操作系统服务管理器启动这个 Python 命令。API 和数据库可以放在同一台小服务器上，数据库只对本机开放。公开访问前接入 HTTPS 反向代理；域名、证书和真实服务器尚未配置。

密码通过单独变量注入，避免密码里的特殊字符破坏 URL。`postgresql://` 也会自动选用 psycopg 3 驱动。进程需要已有数据库及建表权限。启动时只创建缺失表，不自动迁移已有字段；后续改结构前补版本化迁移。本地 SQLite 与正式 PostgreSQL 连接由配置选择，不自动搬迁数据。

存储分为榜单、个人最好成绩和提交回执三张表。PostgreSQL 写入使用 READ COMMITTED 并先锁定对应榜单行，后续查询能看到上一个写入者已提交的成绩；分页／个人查询使用 REPEATABLE READ 保持排名快照。SQLite 写入使用 `BEGIN IMMEDIATE`，读取显式开启事务。最好成绩与回执原子更新，查询按榜单与分数索引排序。该方案适合轻量服务，单榜单大量并发写入时再评估更细锁粒度。回执当前不自动清理，后续留存策略确定前保留幂等保障。[SQLAlchemy PostgreSQL 事务隔离说明](https://docs.sqlalchemy.org/en/20/dialects/postgresql.html#transaction-isolation-level)

## 验证

自动化测试涵盖鉴权、成绩更新、并列排名、分页、重复与冲突提交、删除后重试、重启持久化、并发提交及字段限制。测试在临时 SQLite 上运行，另检查 PostgreSQL 建表、行锁 SQL 编译与连接配置。

```powershell
$env:TEMP = 'D:\.codexfile\tmp'
$env:TMP = $env:TEMP
$env:PYTHONPYCACHEPREFIX = 'D:\.codexfile\cache\leaderboard-api\pycache'
$python = 'D:\.codexfile\cache\leaderboard-api\venv\Scripts\python.exe'
& $python -m pip install -r .\services\leaderboard\requirements-dev.txt
Push-Location .\services\leaderboard
try {
    & $python -m pytest tests -q -o cache_dir=D:/.codexfile/cache/leaderboard-api/pytest --basetemp D:/.codexfile/work/leaderboard-api/tests
} finally { Pop-Location }
```

当前本机没有 PostgreSQL 服务；本机实测使用 SQLite。PostgreSQL 实际连库仍需在安装数据库后验收。

有独立 PostgreSQL 测试数据库时，设置 `LEADERBOARD_TEST_DATABASE_URL` 与 `LEADERBOARD_TEST_DATABASE_PASSWORD` 再执行上述 pytest 命令，会额外把接口测试跑在 PostgreSQL 上。测试账号须有建 schema 权限；每个测试创建随机命名 schema，结束仅删除自己创建的 schema，不清空现有表。请使用专用测试数据库。
