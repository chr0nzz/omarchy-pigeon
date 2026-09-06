import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null

  readonly property string pluginId: "xyzlab.pigeon"
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/pigeon"
  readonly property string statePath: stateDir + "/state.json"

  readonly property var defaults: manifest && manifest.barWidget && manifest.barWidget.defaults ? manifest.barWidget.defaults : ({})
  readonly property var settings: resolveSettings(shell ? shell.shellConfig : null)

  function resolveSettings(config) {
    var merged = {}
    for (var d in defaults) merged[d] = defaults[d]
    var entry = findEntry(config)
    if (entry) for (var k in entry) if (k !== "id") merged[k] = entry[k]
    return merged
  }

  function findEntry(config) {
    if (!config || typeof config !== "object") return null
    var key = Util.canonicalWidgetId(pluginId)
    var bar = config.bar && typeof config.bar === "object" ? config.bar : null
    var layout = bar && bar.layout && typeof bar.layout === "object" ? bar.layout : null
    var sections = ["left", "center", "right"]
    if (layout) {
      for (var s = 0; s < sections.length; s++) {
        var arr = layout[sections[s]]
        if (!Array.isArray(arr)) continue
        for (var i = 0; i < arr.length; i++) {
          var e = Util.normalizeLayoutEntry(arr[i])
          if (e && Util.canonicalWidgetId(e.id) === key) return e
        }
      }
    }
    if (Array.isArray(config.plugins)) {
      for (var p = 0; p < config.plugins.length; p++) {
        var pe = config.plugins[p]
        if (pe && Util.canonicalWidgetId(pe.id) === key) return pe
      }
    }
    return null
  }

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  function boolSetting(name, fallback) {
    var v = setting(name, fallback)
    if (typeof v === "boolean") return v
    var s = String(v).toLowerCase()
    if (s === "true" || s === "1" || s === "yes" || s === "on") return true
    if (s === "false" || s === "0" || s === "no" || s === "off") return false
    return fallback
  }

  readonly property string server: Model.normalizeServer(setting("server", "https://ntfy.sh"))
  readonly property var topics: Model.parseTopics(setting("topics", ""))
  readonly property string authMode: String(setting("auth", "none")).toLowerCase()
  readonly property string authHeader: Model.authHeader(authMode, setting("token", ""), setting("username", ""), setting("password", ""))
  readonly property bool toastsEnabled: boolSetting("toasts", true)
  readonly property int toastMinPriority: Model.clampPriority(setting("toastMinPriority", 2))
  readonly property string backfill: String(setting("backfill", "all"))
  readonly property int maxMessages: Math.max(20, parseInt(setting("maxMessages", 200), 10) || 200)
  readonly property bool allowHttpActions: boolSetting("allowHttpActions", false)
  readonly property bool configured: server !== "" && topics.length > 0

  property var subscribedTopics: []
  onTopicsChanged: if (stateLoaded) reconcileTopics()

  function reconcileTopics() {
    var current = topics.slice()
    var removed = []
    for (var i = 0; i < subscribedTopics.length; i++) {
      if (current.indexOf(subscribedTopics[i]) === -1) removed.push(subscribedTopics[i])
    }
    var same = removed.length === 0 && current.length === subscribedTopics.length
    if (same) return
    for (var r = 0; r < removed.length; r++) {
      clear(removed[r])
      var next = {}
      for (var k in cursors) if (k !== removed[r]) next[k] = cursors[k]
      cursors = next
    }
    subscribedTopics = current
    scheduleSave()
  }
  readonly property bool authIncomplete: authMode !== "none" && authHeader === ""

  readonly property string connectionKey: server + "\n" + topics.join(",") + "\n" + authHeader + "\n" + backfill
  onConnectionKeyChanged: if (stateLoaded) reconnectSoon.restart()

  property var messages: []
  property int unreadCount: 0
  property int urgentUnreadCount: 0
  property var cursors: ({})
  property double cursorTime: 0
  property var tombstones: ({})
  property double muteUntil: 0
  property double nowMs: Date.now()
  readonly property bool muted: muteUntil < 0 || muteUntil > nowMs

  property bool stateLoaded: false
  property bool dirReady: false

  property string status: "unconfigured"
  property string lastError: ""
  property double connectedSince: 0
  property double lastEventAt: 0
  property int backoffMs: 2000
  property int reconnectAttempts: 0
  property bool forceBackfill: false
  property var streamCursors: ({})
  property double streamStartedAt: 0
  property int lastHttpCode: 0
  property string lastHttpBody: ""
  property string lastStderr: ""

  property bool publishing: false
  property string publishStatus: ""
  property bool publishOk: false

  property var actionStates: ({})

  property var ownIds: ({})
  property var ownPending: []

  function isOwnMessage(raw) {
    if (ownIds[String(raw.id || "")] === true) return true
    var now = Date.now()
    var keep = []
    var hit = false
    for (var i = 0; i < ownPending.length; i++) {
      var p = ownPending[i]
      if (now - p.at > 60000) continue
      if (!hit && p.topic === String(raw.topic || "") && p.message === String(raw.message || "") && p.title === String(raw.title || "")) {
        hit = true
        continue
      }
      keep.push(p)
    }
    if (hit || keep.length !== ownPending.length) ownPending = keep
    return hit
  }

  signal messageArrived(var message)
  signal publishFinished(bool ok, string text)

  readonly property string statusLine: {
    if (!configured) return topics.length === 0 ? "No topics configured" : "No server configured"
    if (authIncomplete) return "Auth mode " + authMode + " needs credentials"
    if (status === "connected") return "Connected"
    if (status === "connecting") return "Connecting"
    if (status === "reconnecting") return "Reconnecting" + (lastError ? " · " + lastError : "")
    if (status === "error") return lastError || "Error"
    return "Idle"
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  function recount() {
    var c = Model.countUnread(messages, "")
    unreadCount = c.unread
    urgentUnreadCount = c.urgent
  }

  function unreadFor(topic) {
    return Model.countUnread(messages, topic).unread
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.stateDir]
    onExited: root.dirReady = true
  }

  FileView {
    id: stateFile
    path: root.dirReady ? root.statePath : ""
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyState(text())
    onLoadFailed: root.applyState("")
  }

  function applyState(raw) {
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
    if (parsed && typeof parsed === "object") {
      var list = Array.isArray(parsed.messages) ? parsed.messages : []
      var cleaned = []
      for (var i = 0; i < list.length; i++) {
        var m = list[i]
        if (m && m.id) cleaned.push(m)
      }
      messages = cleaned.slice(0, maxMessages)
      cursorTime = Number(parsed.cursorTime || 0)
      cursors = Util.isPlainObject(parsed.cursors) ? parsed.cursors : {}
      subscribedTopics = Array.isArray(parsed.subscribedTopics) ? parsed.subscribedTopics : []
      tombstones = Util.isPlainObject(parsed.tombstones) ? parsed.tombstones : {}
      muteUntil = Number(parsed.muteUntil || 0)
      if (muteUntil > 0 && muteUntil < Date.now()) muteUntil = 0
    }
    recount()
    if (!stateLoaded) {
      stateLoaded = true
      if (subscribedTopics.length === 0) {
        var seen = {}
        for (var m = 0; m < messages.length; m++) if (messages[m]) seen[messages[m].topic] = true
        subscribedTopics = Object.keys(seen)
      }
      reconcileTopics()
      reconnectSoon.restart()
    }
  }

  Timer {
    id: saveTimer
    interval: 400
    onTriggered: root.saveNow()
  }

  function scheduleSave() { saveTimer.restart() }

  function saveNow() {
    if (!dirReady) { saveTimer.restart(); return }
    var payload = {
      version: 1,
      savedAt: Date.now(),
      cursorTime: cursorTime,
      cursors: cursors,
      subscribedTopics: subscribedTopics,
      tombstones: tombstones,
      muteUntil: muteUntil,
      messages: messages.slice(0, maxMessages)
    }
    stateFile.setText(JSON.stringify(payload))
  }

  Timer {
    id: reconnectSoon
    interval: 250
    onTriggered: root.restartStream()
  }

  Timer {
    id: backoffTimer
    onTriggered: root.startStream()
  }

  Timer {
    id: watchdog
    interval: 120000
    onTriggered: {
      if (!streamProc.running) return
      root.lastError = "No data for 2 minutes"
      streamProc.running = false
    }
  }

  function restartStream() {
    backoffTimer.stop()
    backoffMs = 2000
    reconnectAttempts = 0
    if (streamProc.running) {
      restartRequested = true
      streamProc.running = false
      return
    }
    startStream()
  }
  property bool restartRequested: false

  function reconnect() {
    lastError = ""
    restartStream()
  }

  function startStream() {
    if (!stateLoaded) return
    if (streamProc.running) return
    if (!configured || authIncomplete) {
      status = "unconfigured"
      return
    }
    var oldest = 0
    var fresh = forceBackfill
    for (var i = 0; i < topics.length; i++) {
      var c = Number(cursors[topics[i]] || 0)
      if (!(c > 0)) { fresh = true; break }
      if (oldest === 0 || c < oldest) oldest = c
    }
    forceBackfill = false
    var snap = {}
    for (var t in cursors) snap[t] = cursors[t]
    streamCursors = snap
    streamStartedAt = Date.now() / 1000
    var since = Model.sinceParam(fresh ? 0 : oldest, backfill)
    lastHttpCode = 0
    lastHttpBody = ""
    lastStderr = ""
    status = reconnectAttempts > 0 ? "reconnecting" : "connecting"
    streamProc.streamUrl = Model.subscribeUrl(server, topics, since)
    streamProc.running = true
    watchdog.restart()
  }

  function scheduleReconnect() {
    if (restartRequested) {
      restartRequested = false
      startStream()
      return
    }
    reconnectAttempts++
    var configError = lastHttpCode === 401 || lastHttpCode === 403 || lastHttpCode === 404
    var delay = configError ? 60000 : backoffMs
    backoffMs = Math.min(60000, backoffMs * 2)
    backoffTimer.interval = delay
    backoffTimer.restart()
  }

  Process {
    id: streamProc
    property string streamUrl: ""
    environment: ({ PIGEON_AUTH: root.authHeader })
    command: ["bash", "-c",
      'args=(-sS -N --no-buffer --connect-timeout 15 --keepalive-time 30 -L --max-redirs 3 -A "omarchy-pigeon/1.0"); '
      + 'if [[ -n ${PIGEON_AUTH:-} ]]; then args+=(-H "Authorization: $PIGEON_AUTH"); fi; '
      + 'exec curl "${args[@]}" -w \'\\n{"event":"pigeon_exit","http":%{http_code}}\\n\' -- "$1"',
      "pigeon-stream", streamUrl]
    stdout: SplitParser {
      onRead: function(line) { root.handleLine(line) }
    }
    stderr: SplitParser {
      onRead: function(line) {
        var s = String(line || "").trim()
        if (s && !root.lastStderr) root.lastStderr = s.replace(/^curl:\s*\(\d+\)\s*/, "")
      }
    }
    onExited: function(exitCode) {
      watchdog.stop()
      var wasConnected = root.status === "connected"
      if (root.lastHttpCode >= 400) {
        root.lastError = Model.describeHttpError(root.lastHttpCode, root.lastHttpBody)
        root.status = "error"
      } else if (!root.restartRequested) {
        if (!root.lastError) root.lastError = root.lastStderr || (wasConnected ? "Connection closed" : "Could not connect")
        root.status = "reconnecting"
      }
      root.scheduleReconnect()
    }
  }

  function handleLine(line) {
    watchdog.restart()
    lastEventAt = Date.now()
    var parsed = Model.parseStreamLine(line)
    switch (parsed.kind) {
    case "open":
      status = "connected"
      lastError = ""
      backoffMs = 2000
      reconnectAttempts = 0
      connectedSince = Date.now()
      break
    case "message":
      ingest(parsed.data)
      break
    case "error":
      lastHttpBody = JSON.stringify(parsed.data)
      if (parsed.data.http) lastHttpCode = Number(parsed.data.http)
      break
    case "exit":
      if (parsed.http) lastHttpCode = parsed.http
      break
    default:
      break
    }
  }

  function ingest(raw) {
    var id = String(raw.id || "")
    if (!id || tombstones[id] === true) return
    var topic = String(raw.topic || "")
    var cursor = Number(cursors[topic] || 0)
    var time = Number(raw.time || 0)
    var snap = Number(streamCursors[topic] || 0)
    var isNew = snap > 0 ? time > snap : time > streamStartedAt - 5
    var own = isOwnMessage(raw)
    var msg = Model.normalizeMessage(raw, isNew && !own)
    if (!msg) return
    if (time > cursor) {
      var next = {}
      for (var k in cursors) next[k] = cursors[k]
      next[topic] = time
      cursors = next
    }
    if (Model.hasMessage(messages, msg.id)) return
    messages = Model.mergeMessage(messages, msg, maxMessages)
    if (msg.time > cursorTime) cursorTime = msg.time
    recount()
    scheduleSave()
    messageArrived(msg)
    if (isNew && !own) maybeToast(msg)
  }

  function maybeToast(msg) {
    if (!toastsEnabled || muted) return
    if (msg.priority < toastMinPriority) return
    var tags = Model.splitTags(msg.tags)
    var glyph = tags.emoji.length ? tags.emoji[0] : (msg.priority >= 4 ? Model.priorityGlyph(msg.priority) : "󰂚")
    var title = Model.toastTitle(msg)
    var body = Model.truncate(Model.toastBody(msg), 400)
    if (msg.attachment && msg.attachment.name) body = (body ? body + "\n" : "") + "󰁦 " + msg.attachment.name
    var argv = ["omarchy-notification-send", "--app-name", "Pigeon", "-g", glyph, "-u", Model.urgencyFor(msg.priority), title, body, "--exec"]
    var click = Model.safeHttpUrl(msg.click)
    if (click) argv = argv.concat(["omarchy-launch-browser", click])
    else argv = argv.concat(["omarchy-shell", "shell", "summon", pluginId, "{}"])
    Quickshell.execDetached(argv)
  }

  function messageById(id) {
    for (var i = 0; i < messages.length; i++) if (messages[i] && messages[i].id === id) return messages[i]
    return null
  }

  function markRead(id, read) {
    var changed = false
    var next = messages.map(function(m) {
      if (!m || m.id !== id) return m
      var want = read !== false
      if (m.unread === !want) return m
      changed = true
      var copy = Util.cloneJson(m)
      copy.unread = !want
      return copy
    })
    if (!changed) return
    messages = next
    recount()
    scheduleSave()
  }

  function markAllRead(topic) {
    var changed = false
    var next = messages.map(function(m) {
      if (!m || !m.unread) return m
      if (topic && m.topic !== topic) return m
      changed = true
      var copy = Util.cloneJson(m)
      copy.unread = false
      return copy
    })
    if (!changed) return
    messages = next
    recount()
    scheduleSave()
  }

  function bury(ids) {
    var next = {}
    var keys = Object.keys(tombstones)
    var start = Math.max(0, keys.length + ids.length - 1000)
    for (var i = start; i < keys.length; i++) next[keys[i]] = true
    for (var j = 0; j < ids.length; j++) next[ids[j]] = true
    tombstones = next
  }

  function remove(id) {
    var next = messages.filter(function(m) { return m && m.id !== id })
    if (next.length === messages.length) return
    bury([id])
    messages = next
    recount()
    scheduleSave()
  }

  function clear(topic) {
    var gone = []
    var next = messages.filter(function(m) {
      var keep = m && topic && m.topic !== topic
      if (!keep && m) gone.push(m.id)
      return keep
    })
    if (next.length === messages.length) return
    bury(gone)
    messages = next
    recount()
    scheduleSave()
  }

  function reload() {
    lastError = ""
    forceBackfill = true
    restartStream()
  }

  function setMute(seconds) {
    var s = Number(seconds)
    if (!isFinite(s) || s === 0) muteUntil = 0
    else if (s < 0) muteUntil = -1
    else muteUntil = Date.now() + s * 1000
    nowMs = Date.now()
    scheduleSave()
  }

  function toggleMute() {
    setMute(muted ? 0 : -1)
  }

  function openUrl(url) {
    var safe = Model.safeHttpUrl(url)
    if (!safe) return false
    Util.execArgv(["omarchy-launch-browser", safe])
    return true
  }

  function openClick(msg) {
    if (!msg) return false
    if (openUrl(msg.click)) { markRead(msg.id, true); return true }
    return false
  }

  function openAttachment(msg) {
    if (!msg || !msg.attachment) return false
    if (openUrl(msg.attachment.url)) { markRead(msg.id, true); return true }
    return false
  }

  function copyMessage(msg) {
    if (!msg) return
    var text = msg.title ? msg.title + "\n" + msg.message : msg.message
    Util.execArgv(["wl-copy", "--", text])
  }

  function actionKey(msg, index) { return String(msg ? msg.id : "") + ":" + index }

  function actionState(msg, index) {
    return actionStates[actionKey(msg, index)] || ""
  }

  function setActionState(key, value) {
    var next = {}
    for (var k in actionStates) next[k] = actionStates[k]
    next[key] = value
    actionStates = next
  }

  function runAction(msg, index) {
    if (!msg) return
    var action = Model.toList(msg.actions)[index]
    if (!action) return
    if (action.action === "view") {
      if (openUrl(action.url)) markRead(msg.id, true)
      return
    }
    if (action.action === "http") {
      if (!allowHttpActions) {
        setActionState(actionKey(msg, index), "HTTP actions are disabled in settings")
        return
      }
      var url = Model.safeHttpUrl(action.url)
      if (!url) return
      if (httpActionProc.running) return
      httpActionProc.stateKey = actionKey(msg, index)
      httpActionProc.clearAfter = action.clear === true ? msg.id : ""
      httpActionProc.method = action.method || "POST"
      httpActionProc.headersJson = JSON.stringify(action.headers || {})
      httpActionProc.body = action.body || ""
      httpActionProc.targetUrl = url
      setActionState(httpActionProc.stateKey, "running")
      httpActionProc.running = true
      markRead(msg.id, true)
    }
  }

  Process {
    id: httpActionProc
    property string stateKey: ""
    property string clearAfter: ""
    property string method: "POST"
    property string headersJson: "{}"
    property string body: ""
    property string targetUrl: ""
    environment: ({ PIGEON_METHOD: method, PIGEON_HEADERS: headersJson, PIGEON_BODY: body })
    command: ["bash", "-c",
      'args=(-sS --connect-timeout 15 --max-time 30 -X "$PIGEON_METHOD" -A "omarchy-pigeon/1.0"); '
      + 'while IFS= read -r h; do [[ -n $h ]] && args+=(-H "$h"); done < <(jq -r \'to_entries[] | "\\(.key): \\(.value)"\' <<<"$PIGEON_HEADERS" 2>/dev/null); '
      + 'if [[ -n ${PIGEON_BODY:-} ]]; then args+=(--data-binary "$PIGEON_BODY"); fi; '
      + 'curl "${args[@]}" -o /dev/null -w "%{http_code}" -- "$1"',
      "pigeon-action", targetUrl]
    stdout: StdioCollector {
      id: actionOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var code = parseInt(String(actionOut.text || "").trim(), 10) || 0
      var ok = exitCode === 0 && code >= 200 && code < 300
      root.setActionState(stateKey, ok ? "ok" : ("failed" + (code ? " (" + code + ")" : "")))
      if (ok && clearAfter) root.remove(clearAfter)
    }
  }

  function publish(topic, title, message, priority, tags) {
    var t = String(topic || "").trim()
    if (!Model.validTopic(t)) return failPublish("Invalid topic name")
    if (!server) return failPublish("No server configured")
    if (authIncomplete) return failPublish("Credentials missing for auth mode " + authMode)
    var body = String(message || "")
    var heading = String(title || "").trim()
    if (!body && !heading) return failPublish("Nothing to send")
    if (publishProc.running) return failPublish("Still sending the previous message")
    var payload = { topic: t, message: body || heading }
    if (heading && body) payload.title = heading
    var p = Model.clampPriority(priority || 3)
    if (p !== 3) payload.priority = p
    var tagList = Model.parseTopics(tags)
    if (tagList.length) payload.tags = tagList
    publishProc.payload = JSON.stringify(payload)
    ownPending = ownPending.concat([{ topic: t, message: payload.message, title: payload.title || "", at: Date.now() }])
    publishing = true
    publishOk = false
    publishStatus = "Sending…"
    publishProc.running = true
    return true
  }

  function failPublish(text) {
    publishing = false
    publishOk = false
    publishStatus = text
    publishFinished(false, text)
    return false
  }

  Process {
    id: publishProc
    property string payload: ""
    environment: ({ PIGEON_AUTH: root.authHeader, PIGEON_BODY: payload })
    command: ["bash", "-c",
      'args=(-sS --connect-timeout 15 --max-time 30 -H "Content-Type: application/json" -A "omarchy-pigeon/1.0"); '
      + 'if [[ -n ${PIGEON_AUTH:-} ]]; then args+=(-H "Authorization: $PIGEON_AUTH"); fi; '
      + 'curl "${args[@]}" -w \'\\n%{http_code}\' --data-binary "$PIGEON_BODY" -- "$1"',
      "pigeon-publish", root.server]
    stdout: StdioCollector {
      id: publishOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: publishErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var out = String(publishOut.text || "")
      var nl = out.lastIndexOf("\n")
      var code = parseInt(out.slice(nl + 1).trim(), 10) || 0
      var body = nl >= 0 ? out.slice(0, nl) : ""
      var ok = exitCode === 0 && code >= 200 && code < 300
      if (ok) {
        try {
          var sent = JSON.parse(body)
          if (sent && sent.id) {
            var next = {}
            for (var k in root.ownIds) next[k] = root.ownIds[k]
            next[String(sent.id)] = true
            root.ownIds = next
          }
        } catch (e) {}
      }
      root.publishing = false
      root.publishOk = ok
      if (ok) root.publishStatus = "Sent"
      else if (code) root.publishStatus = Model.describeHttpError(code, body)
      else root.publishStatus = String(publishErr.text || "").trim().replace(/^curl:\s*\(\d+\)\s*/, "") || "Send failed"
      root.publishFinished(ok, root.publishStatus)
      publishStatusReset.restart()
    }
  }

  Timer {
    id: publishStatusReset
    interval: 6000
    onTriggered: if (!root.publishing) root.publishStatus = ""
  }

  IpcHandler {
    target: "pigeon"

    function status(): string {
      return JSON.stringify({
        status: root.status,
        statusLine: root.statusLine,
        server: root.server,
        topics: root.topics,
        unread: root.unreadCount,
        urgent: root.urgentUnreadCount,
        total: root.messages.length,
        muted: root.muted,
        lastError: root.lastError
      })
    }

    function publish(topic: string, title: string, message: string): string {
      return root.publish(topic, title, message, 3, "") ? "ok" : root.publishStatus
    }

    function markAllRead(): void { root.markAllRead("") }
    function clear(): void { root.clear("") }
    function reconnect(): void { root.reconnect() }
    function reload(): void { root.reload() }
    function mute(seconds: string): void { root.setMute(parseInt(seconds, 10)) }
    function unmute(): void { root.setMute(0) }
  }

  Component.onCompleted: mkdirProc.running = true

  Component.onDestruction: {
    watchdog.stop()
    backoffTimer.stop()
    restartRequested = true
    streamProc.running = false
  }
}
