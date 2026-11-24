'use strict'

function isLoopback(hostname) {
  return hostname === 'localhost' || hostname === '127.0.0.1' || hostname === '::1' || hostname === '[::1]'
}

function resolveRequest(config, path) {
  const cfg = config || {}
  const base = String(cfg.apiBase || '').replace(/\/$/, '')
  if (!base) return { ok: false, code: 'API_BASE_MISSING' }
  let url
  try {
    url = new URL(base)
  } catch (err) {
    return { ok: false, code: 'API_BASE_INVALID' }
  }
  if (url.username || url.password || (url.pathname !== '/' && url.pathname !== '')) {
    return { ok: false, code: 'API_BASE_INVALID' }
  }
  if (url.protocol !== 'https:') {
    const dev = cfg.allowInsecureDev === true && url.protocol === 'http:' && isLoopback(url.hostname)
    if (!dev) return { ok: false, code: 'HTTPS_REQUIRED', host: url.host }
  }
  const suffix = path.charAt(0) === '/' ? path : '/' + path
  return { ok: true, url: url.origin + suffix, host: url.host, protocol: url.protocol }
}

function domainChecklist(host) {
  return {
    request: [host],
    uploadFile: [host],
    downloadFile: [host],
    socket: [],
    console: 'https://mp.weixin.qq.com → 开发管理 → 开发设置 → 服务器域名',
    rule: '只填主机名。不要写路径、端口、IP 或 http。每月可改次数有限。'
  }
}

module.exports = { resolveRequest, domainChecklist, isLoopback }
