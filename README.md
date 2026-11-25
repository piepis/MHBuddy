# MH伙伴助手

访客不用登录就能看百科、世界地图、活动和已经公开的配装。私稿只留在这台浏览器或登录后的账户里。

当前数据包是带 `fixture` 标记的合成夹具，不是游戏实数。商店版本和功能差异写在 `docs/execution/mh-mobile-parity.md`。

## 本机一键运行

Windows 和 macOS 只需要先安装 [Docker Desktop](https://www.docker.com/products/docker-desktop/)（自带 Compose v2）。不用单独安装 Flutter、Go 或 PostgreSQL。Windows 使用 Docker Desktop 的 WSL2 后端。第一次构建要联网，镜像会下载 Flutter 3.50.1 并编译 Web。

在仓库根目录执行：

```bash
docker compose up --build
```

浏览器打开 http://localhost:8080/ 。数据库只在 Compose 网络里，不映射到本机端口。这是本机开发栈：`MH_DEV_AUTH=1`，不要把它暴露到公网。

没有 `MH_AI_API_KEY`、微信 AppID/AppSecret 和正式游戏资料也能打开。启动时写入夹具活动、资讯和公开配装。条件配装求解在配装页里，用的是夹具目录。

开发管理员是 `hunter-a`（`MH_ADMINS=hunter-a`）：

1. 打开 http://localhost:8080/me ，或在底部点「我的」。
2. 点「登录以同步 hunter-a」。
3. 打开 http://localhost:8080/admin 。

`hunter-b` 是普通会员。访客不登录，或登录 `hunter-b` 后再打开 `/admin`，都是「没有这个页面」，看不到运营看板。

停止：在同一终端按 Ctrl+C，或另开终端执行 `docker compose down`。

## 命令

```bash
make doctor
make research-mh
make dev          # http://127.0.0.1:8080/
make dev-stop
make build
make verify
make check TASK=T04
make audit-data   # 没有正式资料时会失败，这是预期
```

`make dev` 仍要求本机已有 Flutter、Go 和 PostgreSQL。开发库默认 `postgres://ubuntu@127.0.0.1:5432/mhbuddy?sslmode=disable`。`make dev` 会打开测试登录（`MH_DEV_AUTH=1`）。不要在正式环境打开它。

预览路径：

- `/` 选择作品
- `/g/world/entries/monster/fixture-jagras` 百科
- `/g/world/maps/fixture-ancient-forest` 地图
- `/builds/pub-fixture-wilds-1` 公开配装

## 主题

默认羊皮纸浅色。深色在「我的」里可选。两套颜色不混在同一屏。说明见 `docs/execution/ui-style.md`。
