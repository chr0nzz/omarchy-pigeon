.pragma library
.import "Emojis.js" as Emojis

var PRIORITY_NAMES = { 1: "min", 2: "low", 3: "default", 4: "high", 5: "urgent" }

var LIMITS = {
  line: 65536,
  title: 256,
  message: 8192,
  url: 2048,
  name: 256,
  tags: 16,
  tag: 64,
  actions: 3,
  actionLabel: 64,
  actionBody: 4096,
  headers: 16,
  headerKey: 128,
  headerValue: 1024,
  errorText: 1024
}

function clip(value, max) {
  var s = String(value === undefined || value === null ? "" : value)
  return s.length > max ? s.slice(0, max) : s
}

function clipHeaders(headers) {
  var out = {}
  if (!headers || typeof headers !== "object" || Array.isArray(headers)) return out
  var keys = Object.keys(headers)
  for (var i = 0; i < keys.length && i < LIMITS.headers; i++) {
    var key = clip(keys[i], LIMITS.headerKey)
    if (!key) continue
    out[key] = clip(headers[keys[i]], LIMITS.headerValue)
  }
  return out
}

function toList(value) {
  if (!value || typeof value !== "object" || typeof value.length !== "number") return []
  var out = []
  for (var i = 0; i < value.length; i++) out.push(value[i])
  return out
}

function clampPriority(value) {
  var n = parseInt(value, 10)
  if (!isFinite(n)) return 3
  return Math.max(1, Math.min(5, n))
}

function priorityName(value) {
  return PRIORITY_NAMES[clampPriority(value)] || "default"
}

function urgencyFor(priority) {
  var p = clampPriority(priority)
  if (p <= 2) return "low"
  if (p === 3) return "normal"
  return "critical"
}

function priorityGlyph(priority) {
  var p = clampPriority(priority)
  if (p === 5) return "󱅫"
  if (p === 4) return "󰂞"
  if (p === 1) return "󰂛"
  return "󰍡"
}

function splitTags(tags) {
  var emoji = []
  var plain = []
  var list = toList(tags)
  for (var i = 0; i < list.length; i++) {
    var tag = String(list[i] || "").trim()
    if (!tag) continue
    var e = Emojis.forTag(tag)
    if (e) emoji.push(e)
    else plain.push(tag)
  }
  return { emoji: emoji, plain: plain }
}

function normalizeServer(value) {
  var s = String(value || "").trim()
  if (!s) return ""
  if (!/^https?:\/\//i.test(s)) s = "https://" + s
  return s.replace(/\/+$/, "")
}

function parseTopics(value) {
  var raw = typeof value === "string" ? value : toList(value).join(",")
  var out = []
  var seen = {}
  var parts = raw.split(/[,\s]+/)
  for (var i = 0; i < parts.length; i++) {
    var t = parts[i].trim()
    if (!t || seen[t]) continue
    if (!/^[-_A-Za-z0-9]{1,64}$/.test(t)) continue
    seen[t] = true
    out.push(t)
  }
  return out
}

function validTopic(value) {
  return /^[-_A-Za-z0-9]{1,64}$/.test(String(value || ""))
}

function authHeader(mode, token, username, password) {
  var m = String(mode || "none").toLowerCase()
  if (m === "token" || m === "bearer") {
    var t = String(token || "").trim()
    return t ? "Bearer " + t : ""
  }
  if (m === "basic" || m === "password") {
    var u = String(username || "")
    if (!u) return ""
    return "Basic " + Qt.btoa(u + ":" + String(password || ""))
  }
  return ""
}

function sinceParam(cursorTime, backfill) {
  var c = Number(cursorTime)
  if (isFinite(c) && c > 0) return String(Math.floor(c))
  var b = String(backfill || "").trim()
  if (!b) return "all"
  if (b === "none" || b === "0") return ""
  return b
}

function subscribeUrl(server, topics, since) {
  var url = server + "/" + topics.join(",") + "/json"
  if (since) url += "?since=" + encodeURIComponent(since)
  return url
}

function normalizeMessage(raw, unread) {
  if (!raw || raw.event !== "message") return null
  var id = String(raw.id || "")
  if (!id) return null
  var attachment = null
  if (raw.attachment && raw.attachment.url) {
    attachment = {
      name: clip(raw.attachment.name, LIMITS.name),
      url: clip(raw.attachment.url, LIMITS.url),
      type: clip(raw.attachment.type, LIMITS.name),
      size: Number(raw.attachment.size || 0),
      expires: Number(raw.attachment.expires || 0)
    }
  }
  var actions = []
  if (Array.isArray(raw.actions)) {
    for (var i = 0; i < raw.actions.length && actions.length < LIMITS.actions; i++) {
      var a = raw.actions[i] || {}
      var kind = String(a.action || "").toLowerCase()
      if (kind !== "view" && kind !== "http") continue
      actions.push({
        action: kind,
        label: clip(a.label || (kind === "view" ? "Open" : "Run"), LIMITS.actionLabel),
        url: clip(a.url, LIMITS.url),
        method: clip(String(a.method || "POST").toUpperCase(), 16),
        headers: clipHeaders(a.headers),
        body: clip(a.body, LIMITS.actionBody),
        clear: a.clear === true
      })
    }
  }
  var tags = []
  if (Array.isArray(raw.tags)) {
    for (var t = 0; t < raw.tags.length && tags.length < LIMITS.tags; t++) tags.push(clip(raw.tags[t], LIMITS.tag))
  }
  return {
    id: clip(id, LIMITS.name),
    time: Number(raw.time || 0),
    expires: Number(raw.expires || 0),
    topic: clip(raw.topic, LIMITS.tag),
    title: clip(raw.title, LIMITS.title),
    message: clip(raw.message, LIMITS.message),
    priority: clampPriority(raw.priority || 3),
    tags: tags,
    click: clip(raw.click, LIMITS.url),
    icon: clip(raw.icon, LIMITS.url),
    contentType: clip(raw.content_type, LIMITS.name),
    attachment: attachment,
    actions: actions,
    unread: unread !== false
  }
}

function mergeMessage(list, msg, cap) {
  var out = []
  var placed = false
  for (var i = 0; i < list.length; i++) {
    var m = list[i]
    if (!m || m.id === msg.id) continue
    if (!placed && m.time <= msg.time) {
      out.push(msg)
      placed = true
    }
    out.push(m)
  }
  if (!placed) out.push(msg)
  var limit = Math.max(1, parseInt(cap, 10) || 200)
  if (out.length > limit) out = out.slice(0, limit)
  return out
}

function hasMessage(list, id) {
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].id === id) return true
  return false
}

function countUnread(list, topic) {
  var unread = 0
  var urgent = 0
  for (var i = 0; i < list.length; i++) {
    var m = list[i]
    if (!m || !m.unread) continue
    if (topic && m.topic !== topic) continue
    unread++
    if (m.priority >= 4) urgent++
  }
  return { unread: unread, urgent: urgent }
}

function displayTitle(msg) {
  if (!msg) return ""
  var t = String(msg.title || "").trim()
  if (t) return t
  return msg.topic || "Message"
}

function toastTitle(msg) {
  var tags = splitTags(msg.tags)
  var title = displayTitle(msg)
  return tags.emoji.length ? tags.emoji.join("") + " " + title : title
}

function toastBody(msg) {
  return String(msg.message || "")
}

function toastSummary(count, titles) {
  var n = Math.max(1, parseInt(count, 10) || 1)
  var list = toList(titles).filter(function(t) { return String(t || "").trim() !== "" })
  var lines = list.slice(-3)
  var extra = n - lines.length
  if (extra > 0 && lines.length) lines.push("and " + extra + " more")
  return { title: n + " new " + (n === 1 ? "message" : "messages"), body: lines.join("\n") }
}

function truncate(text, max) {
  var s = String(text || "")
  if (s.length <= max) return s
  return s.slice(0, Math.max(0, max - 1)) + "…"
}

function fileSize(value) {
  var bytes = Number(value || 0)
  if (!bytes) return ""
  if (bytes < 1024) return bytes + " B"
  if (bytes < 1024 * 1024) return Math.round(bytes / 1024) + " KB"
  return (bytes / (1024 * 1024)).toFixed(1) + " MB"
}

function isImageAttachment(att) {
  if (!att || !att.url) return false
  if (/^image\//i.test(String(att.type || ""))) return true
  return /\.(png|jpe?g|gif|webp|bmp)(\?.*)?$/i.test(String(att.name || att.url))
}

function pad2(n) { return (n < 10 ? "0" : "") + n }

function relativeTime(unixSeconds, nowMs) {
  var t = Number(unixSeconds) * 1000
  if (!isFinite(t) || t <= 0) return ""
  var now = Number(nowMs) || Date.now()
  var diff = Math.max(0, now - t)
  var mins = Math.floor(diff / 60000)
  if (mins < 1) return "now"
  if (mins < 60) return mins + "m"
  var hours = Math.floor(mins / 60)
  if (hours < 6) return hours + "h"
  var d = new Date(t)
  var n = new Date(now)
  var sameDay = d.getFullYear() === n.getFullYear() && d.getMonth() === n.getMonth() && d.getDate() === n.getDate()
  var hm = pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  if (sameDay) return hm
  var y = new Date(now - 86400000)
  if (d.getFullYear() === y.getFullYear() && d.getMonth() === y.getMonth() && d.getDate() === y.getDate()) return "Yesterday " + hm
  if (diff < 6 * 86400000) return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getDay()] + " " + hm
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return d.getDate() + " " + months[d.getMonth()]
}

function absoluteTime(unixSeconds) {
  var t = Number(unixSeconds) * 1000
  if (!isFinite(t) || t <= 0) return ""
  var d = new Date(t)
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return d.getDate() + " " + months[d.getMonth()] + " " + d.getFullYear() + " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

function muteLabel(muteUntil, nowMs) {
  if (!muteUntil) return ""
  if (muteUntil < 0) return "Muted"
  var mins = Math.max(1, Math.ceil((muteUntil - nowMs) / 60000))
  if (mins < 60) return "Muted " + mins + "m"
  return "Muted " + Math.ceil(mins / 60) + "h"
}

function filterMessages(list, topic, query) {
  var q = String(query || "").trim().toLowerCase()
  var out = []
  for (var i = 0; i < list.length; i++) {
    var m = list[i]
    if (!m) continue
    if (topic && m.topic !== topic) continue
    if (q) {
      var hay = (m.title + " " + m.message + " " + m.topic + " " + (m.tags || []).join(" ")).toLowerCase()
      if (hay.indexOf(q) === -1) continue
    }
    out.push(m)
  }
  return out
}

function safeHttpUrl(url) {
  var s = String(url || "").trim()
  return /^https?:\/\//i.test(s) ? s : ""
}

function parseStreamLine(line) {
  var raw = String(line || "").trim()
  if (!raw) return { kind: "empty" }
  var obj
  try { obj = JSON.parse(raw) } catch (e) { return { kind: "invalid", raw: raw } }
  if (!obj || typeof obj !== "object") return { kind: "invalid", raw: raw }
  if (obj.event === "pigeon_exit") return { kind: "exit", http: Number(obj.http || 0) }
  if (obj.event === "pigeon_overflow") return { kind: "overflow", fatal: obj.fatal === true }
  if (obj.event === "message") return { kind: "message", data: obj }
  if (obj.event === "open") return { kind: "open" }
  if (obj.event === "keepalive") return { kind: "keepalive" }
  if (obj.error || obj.http) return { kind: "error", data: obj }
  return { kind: "other", data: obj }
}

function describeHttpError(code, body) {
  var c = Number(code || 0)
  var hint = ""
  try {
    var parsed = JSON.parse(String(body || ""))
    if (parsed && parsed.error) hint = String(parsed.error)
  } catch (e) {}
  if (c === 401) return "Unauthorized" + (hint ? ": " + hint : "") + " (check token / credentials)"
  if (c === 403) return "Forbidden" + (hint ? ": " + hint : "") + " (no read access to this topic)"
  if (c === 404) return "Not found (check the server URL)"
  if (c === 429) return "Rate limited by the server"
  if (c >= 500) return "Server error " + c
  if (c > 0) return "HTTP " + c + (hint ? ": " + hint : "")
  return hint || "Connection failed"
}

function fitWidths(naturals, available, gap) {
  var n = naturals.length
  if (!n) return []
  var room = Math.max(0, available - gap * (n - 1))
  var total = 0
  for (var i = 0; i < n; i++) total += naturals[i]
  if (total <= room) return naturals.slice()
  var out = naturals.slice()
  var fixed = {}
  var fixedCount = 0
  var fixedSum = 0
  var changed = true
  while (changed && fixedCount < n) {
    changed = false
    var share = (room - fixedSum) / (n - fixedCount)
    for (var j = 0; j < n; j++) {
      if (fixed[j] || naturals[j] > share) continue
      fixed[j] = true
      fixedCount++
      fixedSum += naturals[j]
      changed = true
    }
  }
  var rest = fixedCount < n ? (room - fixedSum) / (n - fixedCount) : 0
  for (var k = 0; k < n; k++) if (!fixed[k]) out[k] = Math.floor(rest)
  return out
}

function fitLabel(label, suffix, naturalWidth, assignedWidth, chrome) {
  var name = String(label || "")
  var tail = String(suffix || "")
  if (!(naturalWidth > 0) || assignedWidth >= naturalWidth) return name + tail
  var textWidth = Math.max(1, naturalWidth - chrome)
  var budget = Math.floor((name.length + tail.length) * Math.max(0, assignedWidth - chrome) / textWidth) - 1
  var keep = budget - tail.length
  if (keep < 2) {
    tail = ""
    keep = budget
  }
  keep = Math.max(1, Math.min(name.length - 1, keep))
  return name.slice(0, keep) + "…" + tail
}
