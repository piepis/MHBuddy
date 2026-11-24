# MH伙伴助手微信小程序

小程序还没有注册，也没有上传，更没有线上版本。`project.config.json` 里的 `touristappid` 是微信开发者工具的游客占位，不是 AppID。仓库里没有公网 HTTPS 地址。

## 方案

用微信原生小程序，不用 Taro，也不用 uni-app。

推广目标只有微信。原生小程序直接调用现有 `/v1` 接口，用 `wx.login` 拿 code，由 Go 服务兑换成现有会员账户。官方的 `miniprogram-ci` 负责预览和上传。Taro 适合一套代码出多个端，这个仓库的界面是 Flutter Web，换到 Taro 也复用不了页面，只会多一层编译。uni-app 的编译器和部分组件由 DCloud 分发，商用边界不如原生小程序加上 MIT 的上传工具清楚。

默认外观是浅色羊皮纸。底栏仍是黑底，「首页、百科、配装、我的」。地图和活动从首页进去。荒野不显示地图卡。百科、地图、公开配装和活动提醒先读随包夹具，配好 HTTPS 之后再拉服务器。

## 目录

```text
apps/miniapp/
  project.config.json          占位 AppID touristappid，urlCheck 打开
  miniprogram/
    app.json                   页面和底栏
    config.js                  apiBase 为空
    pages/                     首页、百科、地图、公开配装、活动、我的、离线
    logic/                     请求、登录、同步、验签、缓存
    data/                      由 make miniapp-build 从 content/fixtures 复制
    icons/                     Lucide 线标，底栏用
    vendor/tweetnacl.js        验 Ed25519，Unlicense
  scripts/build.js
  scripts/upload.js            没有凭据就退出码 2
  test/logic.test.js
```

网页路由、Flutter 页面和原来的 cookie 登录响应没有改。新增的只有 `POST /v1/auth/wechat`、Bearer 会话，以及 `wechat_identities` 表。

## 命令

在仓库根目录：

```bash
make miniapp-build
make miniapp-test
make miniapp-preview
make miniapp-upload
```

`miniapp-build` 复制夹具、刷新夹具公钥，并确认提交进仓库的配置仍是占位。它不上传。

`miniapp-test` 先构建，再跑节点测试：百科筛选、地图分层、配装撤回、登录缺口、会员同步、提醒、SHA-256 和夹具签名。

`miniapp-preview` 和 `miniapp-upload` 调用 `miniprogram-ci`。下面任一缺失就退出码 2，不会假装已经上传：

- 环境变量 `WECHAT_APPID` 是真实 AppID
- `project.config.json` 的 `appid` 与它相同，不能还是 `touristappid`
- 环境变量 `WECHAT_UPLOAD_KEY` 指向本机的代码上传私钥，文件不能提交

上传版本默认 `0.1.0`，可用 `WECHAT_VERSION` 覆盖。上传成功只表示代码到了微信的开发版本，不是审核通过，也不是发布。

本地连 `make dev` 时，开发者可以临时把 `miniprogram/config.js` 改成：

```js
apiBase: 'http://127.0.0.1:8080',
allowInsecureDev: true
```

并在微信开发者工具里勾选「不校验合法域名」。不要把这两行提交。正式包只接受 `https://` 源站，且 `apiBase` 不能带路径。

## 登录和离线

`wx.login` 只拿到临时 code。小程序把它 `POST` 到 `/v1/auth/wechat`。服务端用 AppID 和 AppSecret 向 `https://api.weixin.qq.com/sns/jscode2session` 兑换 openid，再写入现有 `accounts`、额度和同步表。响应里的 `token` 放在本机存储，之后用 `Authorization: Bearer` 调用 `/v1/sync/push`、`/v1/sync/snapshot` 和 `/v1/me/entitlement`。session_key 不返回、不入库。

没有 AppID 或 AppSecret 时，这个接口返回 503 `WECHAT_NOT_CONFIGURED`。开发环境 `MH_DEV_AUTH=1` 且 code 以 `dev:` 开头时，绑定现有测试用户，便于没有微信凭据时验证同步。生产不要开 `MH_DEV_AUTH`。

资料包用清单里的 SHA-256 和 Ed25519 签名核对，公钥是夹具公钥，不是生产信任锚。修订号更旧的包不会覆盖已缓存的包。请求域名未配置时，百科、地图、活动和公开配装读随包夹具。提醒先记在手机里，接口可用之后再提交 `/v1/reminders/subscriptions`。

服务器域名要在微信公众平台配置，代码里检查不了白名单。`logic/api.js` 的 `domainChecklist` 列出 request、uploadFile、downloadFile 应填写的主机名。

## 工具

| 名称 | 版本 | 用途 | 许可证 |
| --- | --- | --- | --- |
| 微信原生小程序 | 基础库 3.6.6 | 页面、`wx.login`、本机存储 | 运行在微信客户端。本仓库页面代码随项目 |
| miniprogram-ci | 1.9.14 | 预览与上传 | MIT |
| lucide-static | 0.544.0 | 底栏线标 | ISC；Feather 衍生部分 MIT。声明在 `miniprogram/icons/lucide.LICENSE` |
| @resvg/resvg-js | 2.6.2 | 构建时把 SVG 画成 PNG，不打进小程序包 | MPL-2.0 |
| tweetnacl | 1.0.3 | 校验资料包签名 | Unlicense。声明在 `miniprogram/vendor/tweetnacl.LICENSE` |

## 所有者要做的事

这些都还没做。做完之前不要对外说小程序已上线。

### 1. 注册并拿到 AppID

1. 打开 https://mp.weixin.qq.com ，选择「立即注册」，类型选小程序。
2. 用一个没注册过微信开放平台的邮箱，按页面完成管理员扫码。个人主体可以做 `wx.login` 和资料查询。若类目要求企业资质，以公众平台当前可选类目为准。
3. 进入「开发管理 → 开发设置」，复制开发者 ID（AppID）。
4. AppSecret 只重置并保存到服务器环境变量 `WECHAT_APPSECRET`。不要写进小程序、不要提交 git、不要发到聊天记录。
5. 把 `apps/miniapp/project.config.json` 的 `appid` 改成这个 AppID。预览命令还要 `WECHAT_APPID` 与它一致。

### 2. 先有 HTTPS 后端，再配服务器域名

微信 request 合法域名必须是已备案或按微信当前规则可配置的 HTTPS 主机，不能是 IP、localhost 或自签证书。本仓库的 Web 也还没有公网地址。

1. 把现有 Go 服务部署到公网 HTTPS。不要设置 `MH_DEV_AUTH`。设置 `WECHAT_APPID` 和 `WECHAT_APPSECRET`。
2. 确认 `https://你的主机/healthz` 返回 `{"status":"ok"}`。这里不填写一个还不存在的主机名。
3. 把 `miniprogram/config.js` 的 `apiBase` 改成 `https://你的主机`，不要带 `/v1`。
4. 打开「开发管理 → 开发设置 → 服务器域名」。request 合法域名、uploadFile 合法域名、downloadFile 合法域名都填这个主机名，不要带路径和端口。socket 合法域名留空。
5. 保存。这个页面每月修改次数有限。开发者工具里的「不校验合法域名」只影响本地调试。

### 3. 上传代码

图形界面：

1. 安装微信开发者工具。官方安装包是 Windows 和 macOS，没有 Linux 版。
2. 导入目录 `apps/miniapp`。
3. 详情里确认 AppID 已换成注册得到的值。本地调试可以临时关闭域名校验。
4. 点「上传」，填写版本号和备注。上传后代码出现在公众平台的开发版本。

命令行：

1. 仍在「开发设置」里打开「小程序代码上传」，生成并下载私钥。
2. 把当前机器的公网 IP 加进密钥白名单。
3. 私钥放在仓库外，例如本机某个绝对路径。
4. 执行 `WECHAT_APPID=真实AppID WECHAT_UPLOAD_KEY=/绝对路径/private.key make miniapp-upload`。

### 4. 提交审核

1. 打开 https://mp.weixin.qq.com ，进入「管理 → 版本管理」。
2. 在开发版本中选刚上传的构建，点「提交审核」。
3. 类目按主体实际能选的工具或资讯填写。
4. 配置「用户隐私保护指引」：使用微信登录，收集 openid 用于会员同步；收藏、提醒和资料包存在用户手机。不要申请用不到的隐私接口。
5. 提审说明写明当前百科和活动是合成夹具，不是游戏实数，避免被当成已收录官方全库。
6. 等微信审核。审核中的版本不是线上版本。

### 5. 发布

1. 审核通过后，仍在「版本管理」里对审核通过的版本点「提交发布」。
2. 发布完成后，用户才能在微信里搜到已发布的小程序，或扫描该版本的码。
3. 小程序没有一条可代替审核的 https 网页地址。名称在「设置 → 基本设置」里另走审核。
4. 发布前把随包数据从夹具换成已审核的正式资料，并更换验签公钥。夹具公钥不能当生产信任锚。

## 已知限制

- 底栏文字是微信原生 tabBar，固定为简体。页面内的语言切换会改内容文案。
- 顶栏用微信自带返回。收藏星在百科正文里。
- 微信订阅消息模板还没有。提醒是打开小程序时的本地记录，加上现有 `/v1/reminders/subscriptions`。模板 ID 要所有者在公众平台申请后才能做服务通知。
- 没有在微信开发者工具里截图。这台环境是 Linux，官方开发者工具不能在这里启动，`miniprogram-ci` 预览也因没有 AppID 而停止。
