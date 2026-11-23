'use strict'

const { resolveRequest } = require('./api')

async function login(deps) {
  const wxApi = deps.wx
  let loginRes
  try {
    loginRes = await wxApi.login()
  } catch (err) {
    return { ok: false, code: 'WX_LOGIN_FAILED' }
  }
  const code = loginRes && loginRes.code
  if (!code) return { ok: false, code: 'WX_LOGIN_FAILED' }
  const gate = resolveRequest(deps.config, '/v1/auth/wechat')
  if (!gate.ok) return { ok: false, code: gate.code, host: gate.host }
  let res
  try {
    res = await deps.request({
      url: gate.url,
      method: 'POST',
      data: { code: code },
      header: { 'content-type': 'application/json' }
    })
  } catch (err) {
    return { ok: false, code: 'NETWORK' }
  }
  const data = res.data || {}
  if (res.statusCode === 503 && data.code === 'WECHAT_NOT_CONFIGURED') {
    return { ok: false, code: 'WECHAT_NOT_CONFIGURED' }
  }
  if (res.statusCode !== 200 || !data.token) {
    return { ok: false, code: data.code || 'LOGIN_FAILED', status: res.statusCode }
  }
  return {
    ok: true,
    userId: data.userId,
    displayName: data.displayName,
    token: data.token,
    mode: data.mode,
    expiresIn: data.expiresIn
  }
}

module.exports = { login }
