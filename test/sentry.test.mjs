// Unit tests for sentry.js. Run: node --test test/
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

// sentry.js is a QML JavaScript library: drop its pragma and run it as a script.
const source = readFileSync(new URL("../sentry.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
const S = vm.createContext({})
vm.runInContext(source, S)

// Values from the script context have that context's prototypes.
const plain = (value) => JSON.parse(JSON.stringify(value))

const DSN = "https://3d67047e69cbc44478121e507a9407b8@o4511987937705984.ingest.de.sentry.io/4512433525162064"
const PLUGIN = "file:///home/ada/.config/omarchy/plugins/simonmcschubert.todo/"
const OPTIONS = {
  release: "omarchy-todo@0.1.0", environment: "production", pluginUrl: PLUGIN,
  home: "/home/ada", os: "linux", now: 1763112600000, random: () => 0.5
}

// A stack as the QML engine writes it: newest frame first.
const STACK = [
  "inner@" + PLUGIN + "tasks.js:2",
  "add@" + PLUGIN + "TaskStore.qml:61",
  "submit@file:///usr/share/omarchy/shell/Ui/Button.qml:40",
  "expression for onCompleted@qs:@/qs/shell.qml:16"
].join("\n")

test("parseDsn gives the envelope endpoint and refuses anything else", () => {
  assert.deepEqual(plain(S.parseDsn(DSN)), {
    key: "3d67047e69cbc44478121e507a9407b8",
    envelopeUrl: "https://o4511987937705984.ingest.de.sentry.io/api/4512433525162064/envelope/"
      + "?sentry_version=7&sentry_key=3d67047e69cbc44478121e507a9407b8&sentry_client=omarchy-todo.sentry%2F1.0.0"
  })
  assert.equal(S.parseDsn(""), null)
  assert.equal(S.parseDsn("not a dsn"), null)
  assert.equal(S.parseDsn("https://key@host/project"), null)
})

test("DO_NOT_TRACK turns reports off unless empty or 0", () => {
  assert.equal(S.optedOut(undefined), false)
  assert.equal(S.optedOut(""), false)
  assert.equal(S.optedOut("0"), false)
  assert.equal(S.optedOut("false"), false)
  assert.equal(S.optedOut("1"), true)
  assert.equal(S.optedOut("true"), true)
  assert.equal(S.optedOut(" yes "), true)
})

test("scrub shortens home paths and long text", () => {
  assert.equal(S.scrub("Can't read /home/ada/.local/state/omarchy-todo/tasks.json.", "/home/ada"),
    "Can't read ~/.local/state/omarchy-todo/tasks.json.")
  assert.equal(S.scrub("x".repeat(600), "/home/ada").length, S.MAX_MESSAGE_LENGTH)
  assert.equal(S.scrub(null, "/home/ada"), "")
  assert.equal(S.scrub("/a/b", "/"), "/a/b")
})

test("event ids are 32 hex digits", () => {
  assert.match(S.eventId(Math.random), /^[0-9a-f]{32}$/)
})

test("parseStack orders frames oldest first and keeps only plugin paths", () => {
  assert.deepEqual(plain(S.parseStack(STACK, PLUGIN)), [
    { function: "expression for onCompleted", filename: "shell.qml", lineno: 16, in_app: false },
    { function: "submit", filename: "Button.qml", lineno: 40, in_app: false },
    { function: "add", filename: "TaskStore.qml", lineno: 61, in_app: true },
    { function: "inner", filename: "tasks.js", lineno: 2, in_app: true }
  ])
  assert.deepEqual(plain(S.parseStack(undefined, PLUGIN)), [])
  assert.deepEqual(plain(S.parseStack("@" + PLUGIN + "Main.qml:3", PLUGIN))[0].function, "<anonymous>")
})

test("exception events carry the error and stack, and nothing about the user", () => {
  const error = { name: "TypeError", message: "Cannot read property 'id' of null", stack: STACK }
  const event = plain(S.exceptionEvent(error, "add", OPTIONS))
  assert.match(event.event_id, /^[0-9a-f]{32}$/)
  assert.equal(event.timestamp, 1763112600)
  assert.equal(event.platform, "javascript")
  assert.equal(event.level, "error")
  assert.equal(event.release, "omarchy-todo@0.1.0")
  assert.equal(event.environment, "production")
  assert.deepEqual(event.sdk.settings, { infer_ip: "never" })
  assert.deepEqual(event.tags, { action: "add" })
  const value = event.exception.values[0]
  assert.equal(value.type, "TypeError")
  assert.equal(value.value, "Cannot read property 'id' of null")
  assert.deepEqual(value.mechanism, { type: "generic", handled: false })
  assert.equal(value.stacktrace.frames.length, 4)
  assert.equal(event.user, undefined)
  assert.equal(event.server_name, undefined)
  assert.doesNotMatch(JSON.stringify(event), /\/home\/ada/)
})

test("exception events also take thrown values that are not errors", () => {
  const value = plain(S.exceptionEvent("boom", "load", OPTIONS)).exception.values[0]
  assert.equal(value.type, "Error")
  assert.equal(value.value, "boom")
  assert.equal(value.stacktrace, undefined)
})

test("message events group by kind and scrub home paths", () => {
  const event = plain(S.messageEvent("unreadable-file",
    "Can't read /home/ada/.local/state/omarchy-todo/tasks.json (task 3 is not valid).",
    "task 3 is not valid", OPTIONS))
  assert.deepEqual(event.message, { formatted: "Can't read ~/.local/state/omarchy-todo/tasks.json (task 3 is not valid)." })
  assert.deepEqual(event.fingerprint, ["store", "unreadable-file"])
  assert.deepEqual(event.tags, { kind: "unreadable-file", detail: "task 3 is not valid" })
  assert.deepEqual(plain(S.messageEvent("save-failed", "Can't save.", "", OPTIONS)).tags, { kind: "save-failed" })
})

test("envelope is a header, an item header, and the event, one per line", () => {
  const event = S.messageEvent("save-failed", "Can't save.", "", OPTIONS)
  const lines = S.envelope(event, DSN, OPTIONS.now).split("\n")
  assert.equal(lines.length, 4)
  assert.equal(lines[3], "")
  assert.deepEqual(JSON.parse(lines[0]), {
    event_id: event.event_id, sent_at: "2025-11-14T09:30:00.000Z", dsn: DSN,
    sdk: { name: "omarchy-todo.sentry", version: "1.0.0" }
  })
  assert.deepEqual(JSON.parse(lines[1]), { type: "event" })
  assert.equal(JSON.parse(lines[2]).event_id, event.event_id)
})
