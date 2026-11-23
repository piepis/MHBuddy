'use strict'

const { sha256Hex } = require('./sha256')

function bytesFromHex(hex) {
  const clean = String(hex || '').trim()
  if (clean.length % 2 !== 0) return null
  const out = new Uint8Array(clean.length / 2)
  for (let i = 0; i < out.length; i++) {
    const byte = parseInt(clean.substr(i * 2, 2), 16)
    if (Number.isNaN(byte)) return null
    out[i] = byte
  }
  return out
}

function bytesFromBase64(value) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  const clean = String(value || '').replace(/[^A-Za-z0-9+/]/g, '')
  const out = []
  for (let i = 0; i < clean.length; i += 4) {
    const a = alphabet.indexOf(clean.charAt(i))
    const b = alphabet.indexOf(clean.charAt(i + 1))
    const cChar = clean.charAt(i + 2)
    const dChar = clean.charAt(i + 3)
    const c = cChar ? alphabet.indexOf(cChar) : -1
    const d = dChar ? alphabet.indexOf(dChar) : -1
    if (a < 0 || b < 0) return null
    const n = (a << 18) | (b << 12) | ((c < 0 ? 0 : c) << 6) | (d < 0 ? 0 : d)
    out.push((n >> 16) & 255)
    if (cChar) out.push((n >> 8) & 255)
    if (dChar) out.push(n & 255)
  }
  return Uint8Array.from(out)
}

function verifyPack(manifest, bodyText, publicKeyHex, nacl) {
  if (!manifest || typeof bodyText !== 'string') return { ok: false, code: 'PACK_INVALID' }
  const hash = sha256Hex(bodyText)
  if (hash !== manifest.sha256) return { ok: false, code: 'HASH_MISMATCH', hash: hash }
  if (!manifest.signature) return { ok: false, code: 'BAD_SIGNATURE' }
  if (!nacl || !nacl.sign || !nacl.sign.detached) return { ok: false, code: 'BAD_SIGNATURE' }
  const key = bytesFromHex(publicKeyHex)
  const sig = bytesFromBase64(manifest.signature)
  if (!key || !sig) return { ok: false, code: 'BAD_SIGNATURE' }
  const message = new Uint8Array(hash.length)
  for (let i = 0; i < hash.length; i++) message[i] = hash.charCodeAt(i)
  let valid = false
  try {
    valid = nacl.sign.detached.verify(message, sig, key)
  } catch (err) {
    valid = false
  }
  if (!valid) return { ok: false, code: 'BAD_SIGNATURE', hash: hash }
  let catalog = null
  try {
    catalog = JSON.parse(bodyText)
  } catch (err) {
    return { ok: false, code: 'PACK_INVALID', hash: hash }
  }
  return { ok: true, hash: hash, catalog: catalog, revisionNumber: manifest.revisionNumber || 0 }
}

module.exports = { verifyPack, bytesFromHex, bytesFromBase64 }
