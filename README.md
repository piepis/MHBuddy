# MH伙伴助手

访客不用登录就能看百科、世界地图、活动和已经公开的配装。私稿只留在这台浏览器或登录后的账户里。

当前数据包是带 `fixture` 标记的合成夹具，不是游戏实数。商店版本和功能差异写在 `docs/execution/mh-mobile-parity.md`。

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

依赖：Flutter Web、Go、本机 PostgreSQL、Chrome。开发库默认 `postgres://ubuntu@127.0.0.1:5432/mhbuddy?sslmode=disable`。`make dev` 会打开测试登录（`MH_DEV_AUTH=1`）。不要在正式环境打开它。

预览路径：

- `/` 选择作品
- `/g/world/entries/monster/fixture-jagras` 百科
- `/g/world/maps/fixture-ancient-forest` 地图
- `/builds/pub-fixture-wilds-1` 公开配装

## 主题

默认羊皮纸浅色。深色在「我的」里可选。两套颜色不混在同一屏。说明见 `docs/execution/ui-style.md`。
