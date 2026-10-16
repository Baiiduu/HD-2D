# 排行榜接口

独立于 Godot 的 FastAPI 服务，提供榜单管理、最好成绩提交、分页榜单和个人排名。
正式部署选用 PostgreSQL 18，本地用 SQLite；未绑定计分公式、登录平台或游戏结算。

Windows 本地启动（Python 3.13+）：

```powershell
& .\services\leaderboard\start.ps1
```

打开 <http://127.0.0.1:8080/docs>。首次启动自动创建本机开发密钥及数据库，路径显示在终端，Ctrl+C 停止。

接口协议、调用示例、数据库与部署方式见 [排行榜接口说明](../../docs/technical/leaderboard-api.md)。
