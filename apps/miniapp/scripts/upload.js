'use strict'

const fs = require('fs')
const path = require('path')

const mode = process.argv[2]
if (mode !== 'preview' && mode !== 'upload') {
  console.error('usage: node apps/miniapp/scripts/upload.js preview|upload')
  process.exit(2)
}

const appid = process.env.WECHAT_APPID || ''
const keyPath = process.env.WECHAT_UPLOAD_KEY || ''
const projectFile = path.join(__dirname, '../project.config.json')
const project = JSON.parse(fs.readFileSync(projectFile, 'utf8'))
const placeholder = !appid || appid === 'touristappid' || !keyPath || !fs.existsSync(keyPath) || project.appid === 'touristappid' || project.appid !== appid

if (placeholder) {
  console.error('miniapp-' + mode + ': blocked')
  console.error('没有可用的小程序 AppID 或代码上传密钥。这不是线上版本。')
  console.error('1. 打开 https://mp.weixin.qq.com 注册小程序，在开发管理 → 开发设置复制 AppID。')
  console.error('2. 把 apps/miniapp/project.config.json 的 appid 从 touristappid 改成该 AppID。不要把 AppSecret 写进仓库。')
  console.error('3. 在同一页生成并下载代码上传密钥，保存到本机。把密钥的 IP 白名单加上这台机器。')
  console.error('4. WECHAT_APPID=你的AppID WECHAT_UPLOAD_KEY=/绝对路径/private.key make miniapp-' + mode)
  process.exit(2)
}

let ci
try {
  ci = require('miniprogram-ci')
} catch (err) {
  console.error('先在 apps/miniapp 执行 npm install，再重试。')
  process.exit(2)
}

const setting = {
  es6: true,
  es7: true,
  minify: true,
  codeProtect: false,
  autoPrefixWXSS: true
}
const projectRef = new ci.Project({
  appid: appid,
  type: 'miniProgram',
  projectPath: path.join(__dirname, '..'),
  privateKeyPath: keyPath,
  ignores: ['node_modules/**/*', 'test/**/*', 'scripts/**/*']
})

const run = mode === 'preview'
  ? ci.preview({ project: projectRef, desc: 'MH伙伴助手预览', setting: setting, qrcodeFormat: 'image', qrcodeOutputDest: path.join(__dirname, '../preview-qr.png') })
  : ci.upload({ project: projectRef, version: process.env.WECHAT_VERSION || '0.1.0', desc: process.env.WECHAT_DESC || 'MH伙伴助手', setting: setting })

run.then(function () {
  console.log('miniapp-' + mode + ': submitted to WeChat. It is not published.')
}).catch(function (err) {
  console.error(err && err.message ? err.message : err)
  process.exit(1)
})
