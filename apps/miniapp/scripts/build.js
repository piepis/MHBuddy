'use strict'

const fs = require('fs')
const path = require('path')

const miniRoot = path.resolve(__dirname, '..')
const repoRoot = path.resolve(miniRoot, '../..')
const dataDir = path.join(miniRoot, 'miniprogram', 'data')
const fixtures = path.join(repoRoot, 'content', 'fixtures')

function copy(from, to) {
  fs.mkdirSync(path.dirname(to), { recursive: true })
  fs.copyFileSync(from, to)
}

copy(path.join(fixtures, 'catalog-world.json'), path.join(dataDir, 'catalog-world.json'))
copy(path.join(fixtures, 'catalog-wilds.json'), path.join(dataDir, 'catalog-wilds.json'))
copy(path.join(fixtures, 'events.json'), path.join(dataDir, 'events.json'))
copy(path.join(fixtures, 'public-builds.json'), path.join(dataDir, 'public-builds.json'))
copy(path.join(fixtures, 'manifests', 'world.json'), path.join(dataDir, 'manifest-world.json'))
copy(path.join(fixtures, 'manifests', 'wilds.json'), path.join(dataDir, 'manifest-wilds.json'))

const pub = fs.readFileSync(path.join(fixtures, 'keys', 'fixture-ed25519.pub'), 'utf8').trim()
fs.writeFileSync(path.join(miniRoot, 'miniprogram', 'logic', 'fixture-key.js'),
  "'use strict'\n\n// 夹具验签公钥，不是生产信任锚。来源 content/fixtures/keys/fixture-ed25519.pub\nmodule.exports = { fixturePublicKeyHex: " + JSON.stringify(pub) + " }\n")

const naclSrc = path.join(miniRoot, 'node_modules', 'tweetnacl', 'nacl-fast.js')
const naclOut = path.join(miniRoot, 'miniprogram', 'vendor', 'tweetnacl.js')
if (fs.existsSync(naclSrc)) {
  let src = fs.readFileSync(naclSrc, 'utf8')
  src = src.replace(
    "  } else if (typeof require !== 'undefined') {\n    // Node.js.\n    crypto = require('crypto');",
    "  } else if (typeof require !== 'undefined') {\n    // Node.js. The mini program has require, but not Node's crypto module.\n    try { crypto = require('crypto'); } catch (e) { crypto = null; }"
  )
  fs.mkdirSync(path.dirname(naclOut), { recursive: true })
  fs.writeFileSync(naclOut, '// Vendored from tweetnacl 1.0.3 (Unlicense). The crypto require is guarded so WeChat can load verify().\n' + src)
  copy(path.join(miniRoot, 'node_modules', 'tweetnacl', 'LICENSE'), path.join(miniRoot, 'miniprogram', 'vendor', 'tweetnacl.LICENSE'))
}

const lucideDir = path.join(miniRoot, 'node_modules', 'lucide-static', 'icons')
if (fs.existsSync(lucideDir) && fs.existsSync(path.join(miniRoot, 'node_modules', '@resvg', 'resvg-js'))) {
  require('./icons')
  copy(path.join(miniRoot, 'node_modules', 'lucide-static', 'LICENSE'), path.join(miniRoot, 'miniprogram', 'icons', 'lucide.LICENSE'))
}

const app = JSON.parse(fs.readFileSync(path.join(miniRoot, 'miniprogram', 'app.json'), 'utf8'))
for (const page of app.pages) {
  for (const ext of ['.js', '.json', '.wxml', '.wxss']) {
    const file = path.join(miniRoot, 'miniprogram', page + ext)
    if (!fs.existsSync(file)) {
      console.error('missing ' + file)
      process.exit(1)
    }
  }
}
const project = JSON.parse(fs.readFileSync(path.join(miniRoot, 'project.config.json'), 'utf8'))
const runtime = require(path.join(miniRoot, 'miniprogram', 'config.js'))
if (project.appid !== 'touristappid' || runtime.appId !== 'touristappid' || runtime.apiBase) {
  console.error('committed config must keep the placeholder appid and an empty apiBase')
  process.exit(1)
}
console.log('miniapp-build: ok')
console.log('appid: touristappid (placeholder, not a registered mini program)')
console.log('apiBase: empty')
console.log('preview and upload need WECHAT_APPID and WECHAT_UPLOAD_KEY; this build did not upload')
