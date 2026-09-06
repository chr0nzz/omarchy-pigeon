const test = require("node:test")
const assert = require("node:assert/strict")
const { Emojis } = require("./load")

test("forTag maps known ntfy tags to emoji", () => {
  assert.equal(Emojis.forTag("warning"), "⚠️")
  assert.equal(Emojis.forTag("skull"), "💀")
  assert.equal(Emojis.forTag("100"), "💯")
})

test("forTag returns empty for unknown or missing tags", () => {
  assert.equal(Emojis.forTag("backup"), "")
  assert.equal(Emojis.forTag(""), "")
  assert.equal(Emojis.forTag(null), "")
  assert.equal(Emojis.forTag(undefined), "")
})

test("forTag ignores prototype keys", () => {
  assert.equal(Emojis.forTag("constructor"), "")
  assert.equal(Emojis.forTag("__proto__"), "")
})
