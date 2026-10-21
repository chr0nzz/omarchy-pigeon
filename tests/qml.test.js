const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const rootDir = path.join(__dirname, "..")

function qmlFiles(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(function(entry) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) return entry.name === "node_modules" || entry.name.startsWith(".") ? [] : qmlFiles(full)
    return entry.name.endsWith(".qml") ? [full] : []
  })
}

function textBlocks(src) {
  const blocks = []
  const opener = /(?:^|[\s:])(Text|TextEdit|TextArea|Label)\s*\{/g
  let match
  while ((match = opener.exec(src))) {
    let depth = 0
    let end = match.index + match[0].length - 1
    for (; end < src.length; end++) {
      if (src[end] === "{") depth++
      else if (src[end] === "}" && --depth === 0) break
    }
    const body = src.slice(match.index + match[0].length, end)
    let own = ""
    let nested = 0
    for (const ch of body) {
      if (ch === "{") nested++
      else if (ch === "}") nested--
      else if (nested === 0) own += ch
    }
    blocks.push({ line: src.slice(0, match.index).split("\n").length, own: own })
  }
  return blocks
}

test("every Text in the plugin renders plain text", () => {
  const missing = []
  for (const file of qmlFiles(rootDir)) {
    for (const block of textBlocks(fs.readFileSync(file, "utf8"))) {
      if (!/textFormat:\s*Text\.PlainText/.test(block.own)) missing.push(path.relative(rootDir, file) + ":" + block.line)
    }
  }
  assert.deepEqual(missing, [])
})
