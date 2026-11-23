'use strict'

function request(opts) {
  return new Promise(function (resolve, reject) {
    wx.request({
      url: opts.url,
      method: opts.method || 'GET',
      data: opts.data,
      header: opts.header || {},
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
