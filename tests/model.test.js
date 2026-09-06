const test = require("node:test")
const assert = require("node:assert/strict")
const { Model } = require("./load")

function msg(overrides) {
  return Object.assign({
    id: "m1", time: 1000, topic: "alerts", title: "", message: "hello",
    priority: 3, tags: [], click: "", unread: true, attachment: null, actions: []
  }, overrides || {})
}

test("clampPriority keeps 1 to 5 and defaults to 3", () => {
  assert.equal(Model.clampPriority(4), 4)
  assert.equal(Model.clampPriority("5"), 5)
  assert.equal(Model.clampPriority(0), 1)
  assert.equal(Model.clampPriority(99), 5)
  assert.equal(Model.clampPriority("x"), 3)
  assert.equal(Model.clampPriority(undefined), 3)
})

test("priorityName and urgencyFor follow ntfy levels", () => {
  assert.equal(Model.priorityName(1), "min")
  assert.equal(Model.priorityName(3), "default")
  assert.equal(Model.priorityName(5), "urgent")
  assert.equal(Model.priorityName("junk"), "default")
  assert.equal(Model.urgencyFor(1), "low")
  assert.equal(Model.urgencyFor(2), "low")
  assert.equal(Model.urgencyFor(3), "normal")
  assert.equal(Model.urgencyFor(4), "critical")
  assert.equal(Model.urgencyFor(5), "critical")
})

test("priorityGlyph gives distinct glyphs for urgent, high and min", () => {
  const glyphs = [1, 4, 5].map(Model.priorityGlyph)
  assert.equal(new Set(glyphs).size, 3)
  assert.equal(Model.priorityGlyph(2), Model.priorityGlyph(3))
  assert.notEqual(Model.priorityGlyph(3), Model.priorityGlyph(5))
})

test("splitTags separates emoji tags from plain tags", () => {
  const out = Model.splitTags(["warning", "backup", " ", "fire", ""])
  assert.deepEqual(out.emoji, ["⚠️", "🔥"])
  assert.deepEqual(out.plain, ["backup"])
})

test("splitTags tolerates non-array input", () => {
  assert.deepEqual(Model.splitTags(null), { emoji: [], plain: [] })
  assert.deepEqual(Model.splitTags("warning"), { emoji: [], plain: [] })
})

test("normalizeServer adds https and strips trailing slashes", () => {
  assert.equal(Model.normalizeServer("ntfy.example.com"), "https://ntfy.example.com")
  assert.equal(Model.normalizeServer("https://ntfy.example.com///"), "https://ntfy.example.com")
  assert.equal(Model.normalizeServer("http://10.0.0.5:8080/ntfy/"), "http://10.0.0.5:8080/ntfy")
  assert.equal(Model.normalizeServer("  ntfy.sh  "), "https://ntfy.sh")
  assert.equal(Model.normalizeServer(""), "")
  assert.equal(Model.normalizeServer(null), "")
})

test("parseTopics splits on commas and whitespace, dedupes and validates", () => {
  assert.deepEqual(Model.parseTopics("alerts, home  backups,alerts"), ["alerts", "home", "backups"])
  assert.deepEqual(Model.parseTopics("ok_topic-1,bad/topic,bad.topic"), ["ok_topic-1"])
  assert.deepEqual(Model.parseTopics(["a", "b"]), ["a", "b"])
  assert.deepEqual(Model.parseTopics(""), [])
  assert.deepEqual(Model.parseTopics(null), [])
  assert.deepEqual(Model.parseTopics("x".repeat(65)), [])
  assert.deepEqual(Model.parseTopics("x".repeat(64)), ["x".repeat(64)])
})

test("validTopic rejects anything that could change the request path", () => {
  assert.equal(Model.validTopic("alerts"), true)
  assert.equal(Model.validTopic("a/b"), false)
  assert.equal(Model.validTopic("a?x=1"), false)
  assert.equal(Model.validTopic("../etc"), false)
  assert.equal(Model.validTopic(""), false)
  assert.equal(Model.validTopic(null), false)
})

test("authHeader builds bearer and basic headers", () => {
  assert.equal(Model.authHeader("token", " tk_abc "), "Bearer tk_abc")
  assert.equal(Model.authHeader("bearer", "tk_abc"), "Bearer tk_abc")
  assert.equal(Model.authHeader("token", ""), "")
  assert.equal(Model.authHeader("basic", "", "user", "pass"), "Basic " + Buffer.from("user:pass").toString("base64"))
  assert.equal(Model.authHeader("password", "", "user", ""), "Basic " + Buffer.from("user:").toString("base64"))
  assert.equal(Model.authHeader("basic", "", "", "pass"), "")
  assert.equal(Model.authHeader("none", "tk", "user", "pass"), "")
  assert.equal(Model.authHeader(undefined, "tk"), "")
})

test("sinceParam prefers the cursor and falls back to the backfill window", () => {
  assert.equal(Model.sinceParam(1700000000.9, "12h"), "1700000000")
  assert.equal(Model.sinceParam(0, "12h"), "12h")
  assert.equal(Model.sinceParam(0, ""), "all")
  assert.equal(Model.sinceParam(0, undefined), "all")
  assert.equal(Model.sinceParam(0, "none"), "")
  assert.equal(Model.sinceParam(0, "0"), "")
  assert.equal(Model.sinceParam("bad", "3d"), "3d")
})

test("subscribeUrl joins topics and encodes since", () => {
  assert.equal(Model.subscribeUrl("https://ntfy.sh", ["a", "b"], "12h"), "https://ntfy.sh/a,b/json?since=12h")
  assert.equal(Model.subscribeUrl("https://ntfy.sh", ["a"], ""), "https://ntfy.sh/a/json")
  assert.equal(Model.subscribeUrl("https://x", ["a"], "a&b"), "https://x/a/json?since=a%26b")
})

test("normalizeMessage drops non-message events and messages without id", () => {
  assert.equal(Model.normalizeMessage({ event: "open" }), null)
  assert.equal(Model.normalizeMessage({ event: "keepalive", id: "x" }), null)
  assert.equal(Model.normalizeMessage({ event: "message" }), null)
  assert.equal(Model.normalizeMessage(null), null)
})

test("normalizeMessage produces the inbox shape with safe defaults", () => {
  const out = Model.normalizeMessage({ event: "message", id: 42, topic: "alerts", message: "hi" })
  assert.deepEqual(out, {
    id: "42", time: 0, expires: 0, topic: "alerts", title: "", message: "hi", priority: 3,
    tags: [], click: "", icon: "", contentType: "", attachment: null, actions: [], unread: true
  })
})

test("normalizeMessage keeps attachments, clamps priority and honours unread flag", () => {
  const out = Model.normalizeMessage({
    event: "message", id: "a", time: 1700000000, priority: 9, tags: ["warning", 7],
    click: "https://example.com", content_type: "text/markdown",
    attachment: { name: "pic.png", url: "https://x/pic.png", type: "image/png", size: "1234", expires: 1 }
  }, false)
  assert.equal(out.priority, 5)
  assert.deepEqual(out.tags, ["warning", "7"])
  assert.equal(out.contentType, "text/markdown")
  assert.equal(out.unread, false)
  assert.deepEqual(out.attachment, { name: "pic.png", url: "https://x/pic.png", type: "image/png", size: 1234, expires: 1 })
  assert.equal(Model.normalizeMessage({ event: "message", id: "b", attachment: { name: "x" } }).attachment, null)
})

test("normalizeMessage keeps at most three view or http actions", () => {
  const out = Model.normalizeMessage({
    event: "message", id: "a", actions: [
      { action: "broadcast", label: "nope" },
      { action: "VIEW", url: "https://a" },
      { action: "http", url: "https://b", method: "put", headers: { "X-A": "1" }, body: 5, clear: true },
      { action: "http", url: "https://c", headers: "junk" },
      { action: "view", url: "https://d" }
    ]
  })
  assert.equal(out.actions.length, 3)
  assert.deepEqual(out.actions[0], { action: "view", label: "Open", url: "https://a", method: "POST", headers: {}, body: "", clear: false })
  assert.deepEqual(out.actions[1], { action: "http", label: "Run", url: "https://b", method: "PUT", headers: { "X-A": "1" }, body: "5", clear: true })
  assert.deepEqual(out.actions[2].headers, {})
  assert.equal(out.actions[2].url, "https://c")
})

test("mergeMessage inserts newest first, replaces duplicates and enforces the cap", () => {
  const list = [msg({ id: "c", time: 300 }), msg({ id: "a", time: 100 })]
  const merged = Model.mergeMessage(list, msg({ id: "b", time: 200 }), 200)
  assert.deepEqual(merged.map(m => m.id), ["c", "b", "a"])
  const top = Model.mergeMessage(merged, msg({ id: "d", time: 400 }), 200)
  assert.equal(top[0].id, "d")
  const replaced = Model.mergeMessage(top, msg({ id: "b", time: 250, message: "edited" }), 200)
  assert.equal(replaced.filter(m => m.id === "b").length, 1)
  assert.equal(replaced.find(m => m.id === "b").message, "edited")
  const capped = Model.mergeMessage(replaced, msg({ id: "e", time: 500 }), 2)
  assert.deepEqual(capped.map(m => m.id), ["e", "d"])
  assert.equal(Model.mergeMessage([], msg(), "junk").length, 1)
})

test("hasMessage and countUnread", () => {
  const list = [
    msg({ id: "a", priority: 5 }),
    msg({ id: "b", topic: "home", priority: 4 }),
    msg({ id: "c", unread: false, priority: 5 }),
    null
  ]
  assert.equal(Model.hasMessage(list, "b"), true)
  assert.equal(Model.hasMessage(list, "zzz"), false)
  assert.deepEqual(Model.countUnread(list, ""), { unread: 2, urgent: 2 })
  assert.deepEqual(Model.countUnread(list, "home"), { unread: 1, urgent: 1 })
  assert.deepEqual(Model.countUnread([], ""), { unread: 0, urgent: 0 })
})

test("displayTitle, toastTitle and toastBody", () => {
  assert.equal(Model.displayTitle(msg({ title: " Disk full " })), "Disk full")
  assert.equal(Model.displayTitle(msg({ title: "" })), "alerts")
  assert.equal(Model.displayTitle(msg({ title: "", topic: "" })), "Message")
  assert.equal(Model.displayTitle(null), "")
  assert.equal(Model.toastTitle(msg({ title: "Backup", tags: ["tada", "nightly"] })), "🎉 Backup")
  assert.equal(Model.toastTitle(msg({ title: "Backup", tags: ["nightly"] })), "Backup")
  assert.equal(Model.toastBody(msg({ title: "T", message: "body" })), "body")
  assert.equal(Model.toastBody(msg({ message: "" })), "")
})

test("truncate keeps short text and ends long text with an ellipsis", () => {
  assert.equal(Model.truncate("short", 10), "short")
  const out = Model.truncate("a".repeat(50), 10)
  assert.equal(out.length, 10)
  assert.ok(out.endsWith("…"))
  assert.equal(Model.truncate(null, 5), "")
})

test("fileSize formats bytes", () => {
  assert.equal(Model.fileSize(0), "")
  assert.equal(Model.fileSize(512), "512 B")
  assert.equal(Model.fileSize(2048), "2 KB")
  assert.equal(Model.fileSize(1.5 * 1024 * 1024), "1.5 MB")
  assert.equal(Model.fileSize("junk"), "")
})

test("isImageAttachment uses content type then file name", () => {
  assert.equal(Model.isImageAttachment({ url: "https://x/f", type: "image/png" }), true)
  assert.equal(Model.isImageAttachment({ url: "https://x/f.JPG", type: "" }), true)
  assert.equal(Model.isImageAttachment({ url: "https://x/f.webp?token=1", type: "" }), true)
  assert.equal(Model.isImageAttachment({ url: "https://x/f", name: "shot.gif" }), true)
  assert.equal(Model.isImageAttachment({ url: "https://x/f.pdf", type: "application/pdf" }), false)
  assert.equal(Model.isImageAttachment({ type: "image/png" }), false)
  assert.equal(Model.isImageAttachment(null), false)
})

test("relativeTime steps from now to minutes, hours, clock, yesterday, weekday and date", () => {
  const now = new Date(2026, 8, 9, 12, 0, 0)
  const nowMs = now.getTime()
  const at = shift => (nowMs - shift) / 1000
  assert.equal(Model.relativeTime(0, nowMs), "")
  assert.equal(Model.relativeTime("junk", nowMs), "")
  assert.equal(Model.relativeTime(at(20000), nowMs), "now")
  assert.equal(Model.relativeTime(at(5 * 60000), nowMs), "5m")
  assert.equal(Model.relativeTime(at(3 * 3600000), nowMs), "3h")
  assert.equal(Model.relativeTime(at(7 * 3600000), nowMs), "05:00")
  assert.equal(Model.relativeTime(at(30 * 3600000), nowMs), "Yesterday 06:00")
  assert.equal(Model.relativeTime(at(3 * 86400000), nowMs), "Sun 12:00")
  assert.equal(Model.relativeTime(at(10 * 86400000), nowMs), "30 Aug")
  assert.equal(Model.relativeTime(at(-3600000), nowMs), "now")
})

test("absoluteTime renders a local date", () => {
  const d = new Date(2026, 8, 6, 9, 5, 0)
  assert.equal(Model.absoluteTime(d.getTime() / 1000), "6 Sep 2026 09:05")
  assert.equal(Model.absoluteTime(0), "")
})

test("muteLabel", () => {
  const nowMs = 1_000_000_000
  assert.equal(Model.muteLabel(0, nowMs), "")
  assert.equal(Model.muteLabel(-1, nowMs), "Muted")
  assert.equal(Model.muteLabel(nowMs + 30 * 60000, nowMs), "Muted 30m")
  assert.equal(Model.muteLabel(nowMs + 1000, nowMs), "Muted 1m")
  assert.equal(Model.muteLabel(nowMs + 150 * 60000, nowMs), "Muted 3h")
})

test("filterMessages by topic and case insensitive query", () => {
  const list = [
    msg({ id: "a", title: "Disk Full", message: "server one", topic: "alerts" }),
    msg({ id: "b", title: "", message: "door open", topic: "home", tags: ["Camera"] }),
    msg({ id: "c", title: "Backup", message: "done", topic: "alerts" }),
    null
  ]
  assert.deepEqual(Model.filterMessages(list, "home", "").map(m => m.id), ["b"])
  assert.deepEqual(Model.filterMessages(list, "", "disk").map(m => m.id), ["a"])
  assert.deepEqual(Model.filterMessages(list, "", "CAMERA").map(m => m.id), ["b"])
  assert.deepEqual(Model.filterMessages(list, "", "alerts").map(m => m.id), ["a", "c"])
  assert.deepEqual(Model.filterMessages(list, "alerts", "done").map(m => m.id), ["c"])
  assert.deepEqual(Model.filterMessages(list, "", "  ").map(m => m.id), ["a", "b", "c"])
})

test("safeHttpUrl only passes http and https", () => {
  assert.equal(Model.safeHttpUrl("https://example.com/x?y=1"), "https://example.com/x?y=1")
  assert.equal(Model.safeHttpUrl("  http://10.0.0.1  "), "http://10.0.0.1")
  assert.equal(Model.safeHttpUrl("javascript:alert(1)"), "")
  assert.equal(Model.safeHttpUrl("file:///etc/passwd"), "")
  assert.equal(Model.safeHttpUrl("ftp://x"), "")
  assert.equal(Model.safeHttpUrl("example.com"), "")
  assert.equal(Model.safeHttpUrl(""), "")
  assert.equal(Model.safeHttpUrl(null), "")
})

test("parseStreamLine classifies ntfy stream lines", () => {
  assert.deepEqual(Model.parseStreamLine(""), { kind: "empty" })
  assert.deepEqual(Model.parseStreamLine("   "), { kind: "empty" })
  assert.deepEqual(Model.parseStreamLine("not json"), { kind: "invalid", raw: "not json" })
  assert.deepEqual(Model.parseStreamLine("42"), { kind: "invalid", raw: "42" })
  assert.deepEqual(Model.parseStreamLine("null"), { kind: "invalid", raw: "null" })
  assert.deepEqual(Model.parseStreamLine('{"event":"open"}'), { kind: "open" })
  assert.deepEqual(Model.parseStreamLine('{"event":"keepalive"}'), { kind: "keepalive" })
  assert.deepEqual(Model.parseStreamLine('{"event":"pigeon_exit","http":"401"}'), { kind: "exit", http: 401 })
  assert.deepEqual(Model.parseStreamLine('{"event":"pigeon_exit"}'), { kind: "exit", http: 0 })
  const message = Model.parseStreamLine('{"event":"message","id":"a"}')
  assert.equal(message.kind, "message")
  assert.equal(message.data.id, "a")
  assert.equal(Model.parseStreamLine('{"code":40301,"http":403,"error":"forbidden"}').kind, "error")
  assert.equal(Model.parseStreamLine('{"error":"x"}').kind, "error")
  assert.equal(Model.parseStreamLine('{"event":"poll_request"}').kind, "other")
})

test("describeHttpError turns codes into hints", () => {
  assert.equal(Model.describeHttpError(401, '{"error":"unauthorized"}'), "Unauthorized: unauthorized (check token / credentials)")
  assert.equal(Model.describeHttpError(401, ""), "Unauthorized (check token / credentials)")
  assert.equal(Model.describeHttpError(403, "junk"), "Forbidden (no read access to this topic)")
  assert.equal(Model.describeHttpError(404, ""), "Not found (check the server URL)")
  assert.equal(Model.describeHttpError(429, ""), "Rate limited by the server")
  assert.equal(Model.describeHttpError(502, ""), "Server error 502")
  assert.equal(Model.describeHttpError(418, '{"error":"teapot"}'), "HTTP 418: teapot")
  assert.equal(Model.describeHttpError(0, '{"error":"dns"}'), "dns")
  assert.equal(Model.describeHttpError(0, ""), "Connection failed")
  assert.equal(Model.describeHttpError("abc", ""), "Connection failed")
})

test("toList copies array-likes and rejects everything else", () => {
  assert.deepEqual(Model.toList([1, 2]), [1, 2])
  assert.deepEqual(Model.toList({ length: 2, 0: "a", 1: "b" }), ["a", "b"])
  assert.deepEqual(Model.toList("ab"), [])
  assert.deepEqual(Model.toList(null), [])
  assert.deepEqual(Model.toList(5), [])
})

test("fitWidths keeps natural widths when they fit and shares the rest when they do not", () => {
  assert.deepEqual(Model.fitWidths([], 300, 4), [])
  assert.deepEqual(Model.fitWidths([50, 60, 70], 300, 4), [50, 60, 70])
  const out = Model.fitWidths([30, 120, 120, 30], 200, 4)
  assert.equal(out[0], 30)
  assert.equal(out[3], 30)
  assert.equal(out[1], out[2])
  assert.ok(out[1] < 120)
  assert.ok(out.reduce((a, b) => a + b, 0) + 12 <= 200)
  const all = Model.fitWidths([100, 100], 100, 10)
  assert.deepEqual(all, [45, 45])
})

test("fitLabel returns the full label when it fits and truncates the name otherwise", () => {
  assert.equal(Model.fitLabel("traefik", "  2", 80, 80, 12), "traefik  2")
  assert.equal(Model.fitLabel("traefik", "", 80, 120, 12), "traefik")
  assert.equal(Model.fitLabel("traefik", "", 0, 10, 12), "traefik")
  const cut = Model.fitLabel("Media-Server", "  3", 120, 80, 12)
  assert.ok(cut.endsWith("…  3"))
  assert.ok(cut.length < "Media-Server  3".length)
  assert.ok(cut.startsWith("Media"))
  const tiny = Model.fitLabel("Media-Server", "  3", 120, 30, 12)
  assert.ok(!tiny.endsWith("3"))
  assert.ok(tiny.endsWith("…"))
  assert.equal(Model.fitLabel("ab", "", 40, 20, 12), "a…")
})
