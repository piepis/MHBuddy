'use strict'

const { chooseCatalog } = require('./cache')

const world = require('../data/catalog-world.json')
const wilds = require('../data/catalog-wilds.json')
const eventList = require('../data/events.json')
const builds = require('../data/public-builds.json')
const worldManifest = require('../data/manifest-world.json')
const wildsManifest = require('../data/manifest-wilds.json')

function bundledCatalog(gameId) {
  return gameId === 'wilds' ? wilds : world
}

function bundledPack(gameId) {
  const manifest = gameId === 'wilds' ? wildsManifest : worldManifest
  return {
    manifest: manifest,
    catalog: bundledCatalog(gameId),
    revisionNumber: manifest.revisionNumber,
    hash: manifest.sha256,
    fixture: true,
    source: 'bundle'
  }
}

function catalogFor(gameId, cached) {
  return chooseCatalog(bundledCatalog(gameId), cached)
}

function events() {
  return eventList
}

function publicBuilds() {
  return builds
}

module.exports = { bundledCatalog, bundledPack, catalogFor, events, publicBuilds }
