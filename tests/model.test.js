// Node test shim: loads Model.js (which must stay free of undeclared
// globals for QML) and exports its functions via eval.
// Usage: node -e 'const M = require("./tests/model.test.mjs"); ...'
const fs = require("fs")
const path = require("path")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
const factory = new Function(source + "\nreturn { parseReleases, filterIssues, weekLabel, formatPulls, feedUrl, daysUntil, cleanText }")
module.exports = factory()
