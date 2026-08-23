// Loads a plugin .js file (which must stay free of undeclared globals so
// QML can evaluate it) and exposes its named functions to Node tests.
'use strict'
const fs = require('fs')
const path = require('path')

function loadPluginJs(relPath, exportNames) {
  const source = fs.readFileSync(path.join(__dirname, '..', '..', relPath), 'utf8')
  const factory = new Function(source + `\nreturn {${exportNames.join(', ')}}`)
  return factory()
}

module.exports = { loadPluginJs }
