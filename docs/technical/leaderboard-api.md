# 自建排行榜接口

服务代码在 `services/leaderboard/`，独立于 Godot，提供成绩存储与查询接口。World 已接通匿名试玩榜的结算自动提交、个人最好成绩与分页查询；赛季、奖励、TapTap 登录和正式成绩审核仍待确定。试玩榜明确标记为客户端上报，不代表已经完成反作弊。

## Godot 局内计分与 HUD

正式战斗通过 `WavePrototype/RunScore` 订阅真实死亡与清波事件，数值来自 `demoWithMeowa/1/data/score/default_score.tres`。规则在开局复制，本局不受中途编辑影响；重试清零，休整与升级保留，死亡／撤退保留实际已得分。没有按等待时间或空反弹奖励分数。

| 项目 | 当前参数（score_v2） |
| --- | ---: |
| 普通怪 | 10 |
| 特殊怪、裂瓷壶兽本体 | 20 |
| 分裂幼体 | 2；不受连杀倍率影响，不推进或维持连杀、成片奖励 |
| 完整清波 | 100，每波仅一次 |
| 连杀 5／15／30 只 | 后续攻击倍率 ×1.25／×1.5／×2，上限 ×2 |
| 连杀空窗 | 宽限 4 秒，之后每秒降一档；受伤不降档 |
| 同刀／同片击杀 5／10／20 只 | 固定额外 25／50／100，只补到最高档，不吃连杀倍率 |

基础击杀分接受全部真实致死来源，普攻、弹射挥剑与技能共享连杀进度；落地、换一次弹射和反弹不清空。计时读取现有波次战斗时钟，在出手／击杀事件中惰性更新，不增加逐帧回调或定时器；升级冻结与安全休整不消耗宽限。四秒空窗后逐档回落，回落只改变后续倍率，不追回已得分。清波分保持固定，不叠加连杀或最终结算倍率。

基础剑术每刀、奔雷每片共用一个 `score_attack_batch.gd` 纯数据上下文；`RunScore.begin_attack()` 创建上下文，通过伤害参数 `score_batch` 传到真实致死事件。倍率在批次第一次有效击杀时锁定，后续目标沿用，避免死亡顺序改变同批收益；同帧预收集多刀仍能依实际结算顺序承接倍率。成片奖励即时补到最高档，例如同刀从 5 杀升到 10 杀只再补 25 分，累计 50 分。升级冻结后恢复原批次，不重新领奖；奔雷不同片独立统计，落地后的真实尾伤仍按所属片计算。其它攻击仍获得基础分和共享连杀倍率；后续接入同批奖励只需传递此上下文，不增加怪群分析或空间搜索。上下文只随现有攻击和命中引用存活，没有全局攻击历史表。

每次乘算使用千分整数与局内余量，避免 10 ×1.25 因逐只取整长期少给分。每个怪物实例去重，异常移除与重试清理不记分；分裂仍沿用先登记幼体再结束母体的既有流程。有限最后一波在结算快照冻结前补齐清波分，避免既有 `run_ended` 早于 `wave_cleared` 的顺序漏分。结束只冻结已经入账的分数，不追加结算奖励。

巨量怪潮模拟不计分，HUD 明确显示“模拟 · 不计分”。异常中断保留本地已得分，但标记不可提交。`RunScore.state.snapshot()` 提供总分、基础击杀分、连杀额外分、成片奖励、清波分、规则版本与结果资格；旧 `performance_score` 字段保留为连杀额外分与成片奖励之和。匿名提交保存这些精简分项，不上传逐只击杀历史。规则版本标记为 `score_v2`；本次不迁移或清空现有试玩榜，正式版本分榜仍需服务端配置配套。本地资格标记不代替服务端审核。

右上 `WavePrototype/ScoreHUD` 使用现有 Press Start 2P 字体，奶油白数字与短暖金下划线。连续入账默认 0.3 秒合并为一次 `+N`，计数过渡 0.22 秒，变化位提亮并上弹 2.4 逻辑像素后收束；整块面板保持固定。暂不显示连杀文字、倍率或“一片倒下”等奖励名，只更新总分和原有加分数字，保留地图独立的清波提示。真实计分立即生效，不等待动效。表现参数可在该节点 Inspector 调整；计分参数位于参数总览「战斗与成长 → WavePrototype/RunScore → 规则资源」，连杀、成片奖励各有开关与门槛。个人最好成绩保存在服务端，本机保存设备身份和待上传成绩队列；有效结算自动上传，当前没有赛季或奖励。

[已确认参考图](../references/score-ui/score-hud-direction-v1.png) · [实际数字动效，演示数值](../media/score-ui-preview/score-counter.webp) · [声音设置](../media/score-ui-preview/settings-audio.png) · [环绕设置](../media/score-ui-preview/settings-orbit.png)

`tests/test_run_score.gd` 检查基础计分、去重和结算资格；`test_run_score_combo.gd` 检查倍率、固定奖励、批次隔离、余量与懒更新；`test_run_score_clock.gd` 检查跨波、冻结和无逐帧处理。剑术、奔雷及正式地图用例覆盖真实伤害传递、冻结恢复和隐藏奖励名，联网用例检查分项快照与幂等提交。界面观感与整场 CPU 开销仍由正式地图人工验收，逻辑测试不能替代。

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

## 鉴权与匿名试玩榜

写入请求使用 `Authorization: Bearer <LEADERBOARD_API_TOKEN>`，Swagger 中通过 Authorize 填入密钥即可测试。未配置密钥时写入关闭并返回 503；密钥错误返回 401；明显的示例密钥或不足 32 字符的配置会拒绝启动。

当前密钥仅用于可信服务、管理和本机调试，**不能打包到 Godot／Android 客户端**。它既不证明玩家身份，也不能判断一份成绩是否真实。匿名试玩入口只提供设备凭证绑定及客户端成绩上报；正式上线仍需平台身份验证和成绩审核，现有榜单查询和存储层可继续复用。当前没有声称实现反作弊或正式玩家登录。

### 游戏内入口与设备凭证

主菜单有独立「排行榜」按钮；World 游戏内仍通过「设置 → 排行榜」查看，不额外添加游戏内独立按钮。页面可修改后续提交使用的昵称、查询个人最好及每页 20 条的排行，没有保存或提交成绩按钮。真实已结束且有资格的挑战自动提交，结算不强制弹出排行榜；战斗中、模拟和异常中断不生成新提交，City 不自动开启。游戏内页面只占用输入，不暂停场景。主菜单 Esc 关闭排行榜，游戏内 Esc 打开／关闭设置；改键捕获时先取消改键，同一次按键不会继续关闭设置、撤退或重置结算。

`LeaderboardClient` 是独立 autoload，无帧轮询。有效结算后立即自动提交；连接忙时排队，失败或超时保存在本机并按 2、4、8 秒逐步退避，最多每 60 秒重试。身份或请求校验错误保留数据和错误提示，不持续重试。没有待上传成绩时启动不请求网络；有待上传队列时启动自动补交。多局按先后顺序持久化，后一局低分不会覆盖断网期间的高分。同局 UUID、昵称和完整请求在首次发送前冻结，重试与重启均复用，不重复记分。后续改名用于下一份尚未冻结的提交；昵称留空时使用默认设备昵称。上传成功后刷新榜单与个人最好，失败重试不弹窗。

匿名设备在本机产生随机 UUID 和独立 256 位令牌，保存于 `user://leaderboard.cfg`。`POST /v1/demo/scores` 只接受 `device_id`、提交 UUID、非负整数成绩、昵称及附加信息；首次有效提交绑定身份，服务端仅存令牌 SHA-256。以后覆盖同一设备须匹配原令牌，不接受任意 `player_id` 或 `board_id`。它只写入 `LEADERBOARD_DEMO_BOARD_ID` 配置的试玩榜；默认关闭，且不会授予创建榜单、删除成绩或其它榜单写权限。服务端添加 `verification=client_reported`，客户端资格标记不构成反作弊。重装并丢弃本机凭证后不会自动找回旧身份。

连接参数集中在 `demoWithMeowa/1/data/network/leaderboard.tres`：HTTPS 地址、榜单 ID、证书名称与公开 CA。当前使用独立端口 `18443`，暂不使用 `xiuman.org`。Godot 使用 `TLSOptions.client` 校验 CA 和证书名称，未关闭 TLS 验证；CA 私钥离线保存，客户端仅带公开证书。浏览器未安装这份专用 CA 时不会默认信任该入口；这版用于原生 Godot Demo，Web 导出及平台登录另行接入。

迁移后可更新上述资源，或在本机 `user://leaderboard_server.cfg` 使用以下覆盖；证书仍须由同一可信 CA 签发，设备身份无需重建：

```ini
[connection]
endpoint="https://<new-server-ip>:18443"
```

## 实例部署、备份与迁移

正式部署保持原生 Python + PostgreSQL，不依赖阿里云 SDK、容器或常驻游戏房间服。采用单 API 进程、默认 3 个数据库连接、PostgreSQL 64MB shared_buffers 和 20 个总连接；实际容量仍需按玩家并发测量。

| 路径／单元 | 用途 |
| --- | --- |
| `/opt/hd2d-leaderboard/releases/<content-id>` | 内容摘要命名的代码和独立虚拟环境 |
| `/opt/hd2d-leaderboard/current` | 当前生效版本的符号链接 |
| `/opt/hd2d-leaderboard/python` | 独立 Python，不替换系统 Python |
| `/etc/hd2d-leaderboard/leaderboard.env` | 数据库地址、应用密码、管理密钥与试玩榜开关，root 私有 |
| `/etc/hd2d-leaderboard/server.crt`、`server.key` | HTTPS 证书与私钥，与代码版本分离 |
| `hd2d-leaderboard.service` | 非 root 账号运行，开机启动、失败重启、单进程与内存上限 |
| `/etc/nginx/conf.d/hd2d-leaderboard.conf` | 独立端口 HTTPS，试玩写入口和公开查询；管理写入口不向公网转发 |
| `/var/backups/hd2d-leaderboard/<UTC 时间>` | 数据库自包含备份及私有配置、证书；不公开、不提交 Git |

打包只取程序、依赖锁和部署脚本，排除 `.env`、数据库、凭证、运行缓存及测试文件：

```powershell
python services/leaderboard/deploy/package.py --output D:/.codexfile/work/leaderboard-release
```

在新 Ubuntu 实例上传并运行 `deploy/bootstrap-ubuntu.sh` 安装独立 Python 与 PostgreSQL 18；上传发布包并运行 `deploy/stage-release.sh /path/to/leaderboard-<id>.tar.gz`。初始化仅为新部署生成数据库应用账号及随机管理密钥，已有私有配置不会被替换；已有账号但遗失配置时直接停止，要求恢复原配置。准备阶段不会替换已运行版本；验证后再切换 `current`、安装 systemd 与 Nginx 配置、检测并重载入口。普通版本切换不自动迁移表结构，后续不兼容数据库变更须先补版本化迁移。

首次 HTTPS 证书由本机离线 CA 签发。CA 私钥在本机受限凭证目录，未上传服务器、未打入游戏或发布包；迁移时为新地址签发服务器证书，沿用客户端公开 CA。当前服务器证书有效期一年，需在到期前续签；这版尚未接证书自动续期。

本机离线 CA 保存在 `D:\.codexfile\credentials\hd2d-leaderboard-tls`，异机私有备份保存在 `D:\.codexfile\credentials\hd2d-leaderboard-backups`。迁移、清理磁盘或更换开发电脑时均须保留，不能放入项目发布包。

备份命令为 `bash /opt/hd2d-leaderboard/current/deploy/backup.sh`。备份包含数据库、设备令牌哈希、最好成绩、提交回执与外置配置；另保留发布包和离线 CA。已有数据迁移步骤：

1. 先在独立空数据库验证 `pg_restore`，确认榜单、最好成绩、设备身份与回执都存在。
2. 在新实例装好运行环境，恢复原 `leaderboard.env`，以其中的应用密码创建数据库角色及空库。不要让新部署提前生成另一套账号密码。
3. 用 `pg_restore --exit-on-error --no-owner --role=leaderboard --dbname=leaderboard` 恢复自包含备份；输入文件由管理员打开，数据库账号不需要读取系统私有文件。
4. 配置新服务器证书，启动 API、验证读写与重复提交，再更新客户端入口。最终切换时需安排写入窗口，避免新旧实例同时接受成绩造成数据分叉。

首版已做独立数据库备份恢复验证。上线持续运营前再配置定期异机备份、证书续期与迁移切换流程；当前不声称具备自动容灾。

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

示例中的 `/etc/leaderboard.env` 需事先创建并限制读取权限。常驻运行时由操作系统服务管理器启动这个 Python 命令。API 和数据库可以放在同一台小服务器上，数据库只对本机开放。正式实例已使用独立端口的 HTTPS 反向代理，暂不使用域名；证书与 CA 按上节分离维护。

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

Windows 本机默认使用 SQLite；Linux 部署已运行 PostgreSQL 18，并使用独立测试数据库执行同一套接口回归。界面排布与实机操作仍由人工验收。

有独立 PostgreSQL 测试数据库时，设置 `LEADERBOARD_TEST_DATABASE_URL` 与 `LEADERBOARD_TEST_DATABASE_PASSWORD` 再执行上述 pytest 命令，会额外把接口测试跑在 PostgreSQL 上。测试账号须有建 schema 权限；每个测试创建随机命名 schema，结束仅删除自己创建的 schema，不清空现有表。请使用专用测试数据库。
