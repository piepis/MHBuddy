'use strict'

const fs = require('fs')
const path = require('path')
const { Resvg } = require('@resvg/resvg-js')

const root = path.resolve(__dirname, '..')
const icons = path.join(root, 'node_modules', 'lucide-static', 'icons')
const out = path.join(root, 'miniprogram', 'icons')
fs.mkdirSync(out, { recursive: true })

const names = { home: 'house', wiki: 'book-open', builds: 'shield', me: 'user' }
const colors = { '': '#B2B3B2', '-on': '#C4C4DC' }

for (const key of Object.keys(names)) {
  const svgPath = path.join(icons, names[key] + '.svg')
  const raw = fs.readFileSync(svgPath, 'utf8')
  for (const suffix of Object.keys(colors)) {
    const svg = raw.replace(/currentColor/g, colors[suffix]).replace('width="24"', 'width="81"').replace('height="24"', 'height="81"')
    const png = new Resvg(svg, { fitTo: { mode: 'width', value: 81 }, background: 'rgba(0,0,0,0)' }).render().asPng()
    fs.writeFileSync(path.join(out, key + suffix + '.png'), png)
  }
}
