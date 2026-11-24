'use strict'

const { resolveRequest } = require('./api')
const { verifyPack } = require('./integrity')

async function downloadPack(deps) {
  const query = '/v1/packs/latest?gameId=' + encodeURIComponent(deps.gameId) + '&clientVersion=' + encodeURIComponent(deps.clientVersion || '0.1.0')
  const gate = resolveRequest(deps.config, query)
  if (!gate.ok) return { ok: false, code: gate.code, host: gate.host }
  const manRes = await deps.request({ url: gate.url, method: 'GET', dataType: 'json' })
  if (!manRes || manRes.statusCode !== 200 || !manRes.data) {
    return { ok: false, code: 'PACK_FAILED', status: manRes && manRes.statusCode }
  }
  const manifest = manRes.data
  const fileGate = resolveRequest(deps.config, manifest.url)
  if (!fileGate.ok) return { ok: false, code: fileGate.code }
  const bodyRes = await deps.request({ url: fileGate.url, method: 'GET', dataType: 'text' })
  if (!bodyRes || typeof bodyRes.data !== 'string') return { ok: false, code: 'PACK_NOT_RAW' }
  const checked = verifyPack(manifest, bodyRes.data, deps.publicKeyHex, deps.nacl)
  if (!checked.ok) return checked
  return {
    ok: true,
    manifest: manifest,
    catalog: checked.catalog,
    hash: checked.hash,
    revisionNumber: checked.revisionNumber
  }
}

module.exports = { downloadPack }
