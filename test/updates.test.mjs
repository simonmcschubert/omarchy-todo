// Unit tests for updates.js, the update button's states. Run: node --test test/
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

// updates.js is a QML JavaScript library: drop its pragma and run it as a script.
const source = readFileSync(new URL("../updates.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
const U = vm.createContext({})
vm.runInContext(source, U)

// Values from the script context have that context's prototypes.
const plain = (value) => JSON.parse(JSON.stringify(value))

const IDLE = { status: "", version: "", installed: "0.1.3", checking: false, checkError: "", confirmedCurrent: false }
const state = (over) => ({ ...IDLE, ...over })

test("a check finds a release to download, a downloaded one, or none", () => {
  assert.deepEqual(plain(U.checked(0, "available 0.2.0\n", "", false)), { checkError: "", status: "available", version: "0.2.0" })
  assert.deepEqual(plain(U.checked(0, "downloaded 0.2.0\n", "", true)), { checkError: "", status: "downloaded", version: "0.2.0" })
  assert.deepEqual(plain(U.checked(0, "current\n", "", false)), { checkError: "", status: "", version: "", confirm: false })
  // Only a check the button asked for says "Up to date".
  assert.equal(U.checked(0, "current\n", "", true).confirm, true)
})

test("a failed check shows the update script's own reason, only when the button asked", () => {
  // git's error comes first on stderr; the script's reason is the last line.
  const message = "fatal: unable to access 'https://github.com/x/y.git/': Could not resolve host: github.com\nupdate: can't reach origin"
  assert.deepEqual(plain(U.checked(1, "", message, true)), { checkError: "can't reach origin" })
  assert.deepEqual(plain(U.checked(1, "", "", true)), { checkError: "the update script failed" })
  // A failed check on the timer changes nothing: what an earlier check found stays.
  assert.deepEqual(plain(U.checked(1, "", message, false)), {})
})

test("a release shows in the window and the drop-down", () => {
  for (const inWindow of [true, false]) {
    assert.deepEqual(plain(U.button(state({ status: "available", version: "0.2.0" }), inWindow)),
      { icon: U.DOWNLOAD, text: "Update", color: "accent", tip: "To Do 0.2.0 is available. Click to download it." })
    assert.equal(U.button(state({ status: "downloading", version: "0.2.0" }), inWindow).text, "Downloading")
    assert.equal(U.button(state({ status: "downloaded", version: "0.2.0" }), inWindow).text, "Restart to update")
    assert.equal(U.button(state({ status: "installing", version: "0.2.0" }), inWindow).busy, true)
    assert.equal(U.button(state({ status: "failed", version: "0.2.0" }), inWindow).color, "urgent")
  }
})

test("with nothing to offer, the window shows a check button and the drop-down none", () => {
  assert.equal(U.button(IDLE, false), null)
  assert.equal(U.button(state({ checkError: "can't reach origin" }), false), null)
  assert.deepEqual(plain(U.button(IDLE, true)),
    { icon: U.REFRESH, text: "", color: "normal", tip: "To Do 0.1.3 is installed. Click to check for updates." })
  assert.equal(U.button(state({ installed: "" }), true).tip, "Click to check for updates.")
  assert.equal(U.button(state({ checking: true }), true).busy, true)
  assert.deepEqual(plain(U.button(state({ checkError: "can't reach origin" }), true)),
    { icon: U.WARNING, text: "Can't check", color: "urgent", tip: "Can't check for updates: can't reach origin. Click to try again." })
  assert.deepEqual(plain(U.button(state({ confirmedCurrent: true }), true)),
    { icon: U.CHECK, text: "Up to date", color: "normal", tip: "To Do 0.1.3 is up to date." })
})
