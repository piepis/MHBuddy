'use strict'

const { textOf } = require('./catalog')
const { resolveRequest } = require('./api')

function followLocal(existing, event, locale, nowIso, token) {
  const list = existing || []
  for (let i = 0; i < list.length; i++) {
    if (list[i].eventId === event.id) return { reminders: list, already: true, row: list[i] }
  }
  const row = {
    eventId: event.id,
    title: textOf(event.titles, locale),
    gameId: event.gameId,
    startsAt: event.startsAt,
    endsAt: event.endsAt,
    timezone: event.timezone || '',
    verifiedAt: event.verifiedAt || '',
    revokeToken: token,
    where: 'local',
    serverId: '',
    createdAt: nowIso
  }
  return { reminders: list.concat([row]), already: false, row: row }
}

function markSynced(reminders, eventId, serverId) {
  return (reminders || []).map(function (row) {
    if (row.eventId !== eventId) return row
    return Object.assign({}, row, { where: 'account', serverId: serverId })
  })
}

function dueReminders(reminders, nowMs) {
  return (reminders || []).filter(function (row) {
    const start = Date.parse(row.startsAt)
    const end = Date.parse(row.endsAt)
    if (!start || !end) return false
    return start - nowMs <= 30 * 60 * 1000 && end > nowMs
  })
}

function calendarText(event, locale) {
  const lines = [
    textOf(event.titles, locale),
    (event.startsAt || '') + ' – ' + (event.endsAt || ''),
    event.timezone || '',
    'UID:' + event.id + '@mhbuddy',
    event.verifiedAt ? '核实 ' + event.verifiedAt : '',
    event.fixture ? '夹具日程，不是官方时间。' : ''
  ]
  return lines.filter(Boolean).join('\n')
}

async function subscribe(deps) {
  const gate = resolveRequest(deps.config, '/v1/reminders/subscriptions')
  if (!gate.ok) return { ok: false, code: gate.code }
  const headers = { 'content-type': 'application/json' }
  if (deps.token) headers.Authorization = 'Bearer ' + deps.token
  const res = await deps.request({
    url: gate.url,
    method: 'POST',
    data: {
      eventId: deps.event.id,
      platformId: deps.event.platformId || 'pc',
      kind: 'start',
      endpoint: 'miniprogram',
      revokeToken: deps.revokeToken
    },
    header: headers
  })
  if (!res || res.statusCode !== 201) {
    return { ok: false, code: (res && res.data && res.data.code) || 'REMINDER_FAILED', status: res && res.statusCode }
  }
  return { ok: true, id: res.data.id }
}

module.exports = { followLocal, markSynced, dueReminders, calendarText, subscribe }
