'use strict'

function request(opts) {
  var header = Object.assign({}, opts.header || {})
  if (!header.Origin && !header.origin) header.Origin = 'https://servicewechat.com'
  return new Promise(function (resolve, reject) {
    wx.request({
      url: opts.url,
      method: opts.method || 'GET',
      data: opts.data,
      header: header,
      dataType: opts.dataType || 'json',
      responseType: opts.responseType || 'text',
      success: function (res) {
        resolve({ statusCode: res.statusCode, data: res.data, header: res.header })
      },
      fail: function (err) { reject(err) }
    })
  })
}

function login() {
  return new Promise(function (resolve, reject) {
    wx.login({ success: resolve, fail: reject })
  })
}

module.exports = { request, login }
