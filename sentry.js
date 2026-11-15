.pragma library

// Error reports to Sentry, without an SDK: there is none for QML. These
// functions build the events and the envelope that ErrorReports.qml sends.
// The node tests in test/ load this file directly.
//
// An event never carries task text, the user, or the host name. Paths under
// the home directory are shortened to "~".

var SDK_NAME = "omarchy-todo.sentry"
var SDK_VERSION = "1.0.0"
var MAX_MESSAGE_LENGTH = 500

// { key, envelopeUrl } for a DSN like https://KEY@HOST/PROJECT, or null.
function parseDsn(dsn) {
  var m = /^(https?):\/\/([0-9a-f]+)@([A-Za-z0-9.-]+(?::\d+)?)\/(\d+)$/.exec(String(dsn || ""))
  if (!m) return null
  var url = m[1] + "://" + m[3] + "/api/" + m[4] + "/envelope/"
    + "?sentry_version=7&sentry_key=" + m[2] + "&sentry_client=" + SDK_NAME + "%2F" + SDK_VERSION
  return { key: m[2], envelopeUrl: url }
}

// DO_NOT_TRACK set to anything but "" or "0" turns reports off.
function optedOut(doNotTrack) {
  var value = String(doNotTrack || "").trim().toLowerCase()
  return value !== "" && value !== "0" && value !== "false"
}

function scrub(text, home) {
  var out = String(text === undefined || text === null ? "" : text)
  if (home && home.length > 1) out = out.split(home).join("~")
  return out.length > MAX_MESSAGE_LENGTH ? out.substring(0, MAX_MESSAGE_LENGTH) : out
}

// 32 lowercase hex digits.
function eventId(random) {
  var id = ""
  for (var i = 0; i < 32; i++) id += Math.floor(random() * 16).toString(16)
  return id
}

// Frames of a QML engine stack ("fn@url:line", newest first), oldest first
// as Sentry wants them. Frames from the plugin get their path inside it;
// others only their file name.
function parseStack(stack, pluginUrl) {
  var frames = []
  String(stack || "").split("\n").forEach(function(line) {
    var m = /^([^@]*)@(.+):(\d+)$/.exec(line.trim())
    if (!m) return
    var url = m[2]
    var inApp = !!pluginUrl && url.indexOf(pluginUrl) === 0
    var path = inApp ? url.substring(pluginUrl.length) : url.substring(url.lastIndexOf("/") + 1)
    frames.unshift({
      function: m[1] || "<anonymous>",
      filename: path,
      lineno: Number(m[3]),
      in_app: inApp
    })
  })
  return frames
}

// The fields every event shares. options: { release, environment, now, random }
function baseEvent(options) {
  return {
    event_id: eventId(options.random),
    timestamp: options.now / 1000,
    platform: "javascript",
    level: "error",
    logger: "omarchy-todo",
    release: options.release,
    environment: options.environment,
    sdk: { name: SDK_NAME, version: SDK_VERSION, settings: { infer_ip: "never" } },
    contexts: { os: { name: options.os || "linux" } },
    tags: {},
    extra: {}
  }
}

// An exception caught in the plugin's code. action names what it was doing.
function exceptionEvent(error, action, options) {
  var event = baseEvent(options)
  var frames = parseStack(error && error.stack, options.pluginUrl)
  var value = {
    type: error && error.name ? String(error.name) : "Error",
    value: scrub(error && error.message !== undefined ? error.message : error, options.home),
    mechanism: { type: "generic", handled: false }
  }
  if (frames.length > 0) value.stacktrace = { frames: frames }
  event.exception = { values: [value] }
  event.tags.action = action
  return event
}

// A failure the plugin noticed itself, like a tasks file it cannot read.
// kind groups the events; detail goes into a tag.
function messageEvent(kind, message, detail, options) {
  var event = baseEvent(options)
  event.message = { formatted: scrub(message, options.home) }
  event.fingerprint = ["store", kind]
  event.tags.kind = kind
  if (detail) event.tags.detail = scrub(detail, options.home).substring(0, 200)
  return event
}

function envelope(event, dsn, now) {
  var header = { event_id: event.event_id, sent_at: new Date(now).toISOString(), dsn: dsn,
    sdk: { name: SDK_NAME, version: SDK_VERSION } }
  return JSON.stringify(header) + "\n" + JSON.stringify({ type: "event" }) + "\n" + JSON.stringify(event) + "\n"
}
