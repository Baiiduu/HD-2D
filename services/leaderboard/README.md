# 排行榜接口

独立于 Godot 的 FastAPI 服务，提供榜单管理、最好成绩提交、分页榜单和个人排名。
正式部署选用 PostgreSQL 18，本地用 SQLite，独立于计分公式与登录平台。

World 已接入匿名试玩榜：结算后手动提交、查询个人最好成绩与分页排行，主菜单和游戏内「设置 → 排行榜」共用入口。客户端上报分数尚未做正式审核；设备凭证只允许写入自己的试玩成绩，不包含管理密钥。

Linux 部署、版本打包、备份和迁移工具在 `deploy/`，不依赖 ECS SDK 或 Workbench。公网入口为独立端口 HTTPS，API 和 PostgreSQL 只监听本机；配置、证书和数据库保留在版本目录之外。部署依赖使用 `requirements-linux.lock`，不替换系统 Python。

Windows 本地启动（Python 3.13+）：

```powershell
& .\services\leaderboard\start.ps1
```

打开 <http://127.0.0.1:8080/docs>。首次启动自动创建本机开发密钥及数据库，路径显示在终端，Ctrl+C 停止。

接口协议、调用示例、数据库与部署方式见 [排行榜接口说明](../../docs/technical/leaderboard-api.md)。
