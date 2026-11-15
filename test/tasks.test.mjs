// Unit tests for tasks.js. Run: node --test test/
process.env.TZ = "Europe/Berlin"

import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

// tasks.js is a QML JavaScript library: drop its pragma and run it as a script.
const source = readFileSync(new URL("../tasks.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
const T = vm.createContext({})
vm.runInContext(source, T)

// Values from the script context have that context's prototypes.
const plain = (value) => JSON.parse(JSON.stringify(value))

const NOW = new Date(2026, 10, 14, 9, 30).getTime() // Sat 14 Nov 2026, 09:30
const TODAY = "2026-11-14"

function task(over) {
  return { id: "a", text: "Task", due: null, starred: false, createdAt: 1, doneAt: null, ...over }
}

test("date keys are local calendar days and reject impossible dates", () => {
  assert.equal(T.dateKey(new Date(2026, 0, 5, 23, 59)), "2026-01-05")
  assert.equal(T.isDateKey("2026-02-28"), true)
  assert.equal(T.isDateKey("2026-02-30"), false)
  assert.equal(T.isDateKey("2026-2-3"), false)
  assert.equal(T.isDateKey(null), false)
  assert.equal(T.addDays("2026-12-31", 1), "2027-01-01")
  assert.equal(T.addMonths("2026-11-14", 1), "2026-12-14")
  assert.equal(T.addMonths("2027-01-31", 1), "2027-02-28")
  assert.equal(T.addMonths("2026-12-15", 1), "2027-01-15")
})

test("day differences ignore daylight saving changes", () => {
  // Berlin switches to summer time on 29 March 2026 and back on 25 October.
  assert.equal(T.daysBetween("2026-03-28", "2026-03-30"), 2)
  assert.equal(T.daysBetween("2026-10-24", "2026-10-26"), 2)
  assert.equal(T.daysBetween("2026-11-14", "2026-11-13"), -1)
})

test("due labels", () => {
  assert.deepEqual(plain(T.dueInfo("2026-11-14", TODAY)), { label: "Today", state: "today" })
  assert.deepEqual(plain(T.dueInfo("2026-11-15", TODAY)), { label: "Tomorrow", state: "soon" })
  assert.deepEqual(plain(T.dueInfo("2026-11-18", TODAY)), { label: "Wed", state: "soon" })
  assert.deepEqual(plain(T.dueInfo("2026-11-21", TODAY)), { label: "21 Nov", state: "later" })
  assert.deepEqual(plain(T.dueInfo("2027-01-04", TODAY)), { label: "4 Jan 2027", state: "later" })
  assert.deepEqual(plain(T.dueInfo("2026-11-13", TODAY)), { label: "Yesterday", state: "overdue" })
  assert.deepEqual(plain(T.dueInfo("2026-11-02", TODAY)), { label: "2 Nov", state: "overdue" })
  assert.deepEqual(plain(T.dueInfo(null, TODAY)), { label: "", state: "" })
})

test("next weekday is always after today", () => {
  assert.equal(T.nextWeekday(TODAY, 1), "2026-11-16") // Monday
  assert.equal(T.nextWeekday(TODAY, 6), "2026-11-21") // Saturday, a week on
  assert.equal(T.nextWeekday("", 1), null)
})

test("month grid starts on the chosen first day of the week", () => {
  const monday = plain(T.monthGrid(2026, 10, 1))
  assert.equal(monday.length, 42)
  assert.equal(monday[0].key, "2026-10-26")
  assert.equal(monday[0].inMonth, false)
  assert.equal(monday[6].key, "2026-11-01")
  assert.equal(monday[6].inMonth, true)
  const sunday = plain(T.monthGrid(2026, 10, 0))
  assert.equal(sunday[0].key, "2026-11-01")
  assert.deepEqual(plain(T.weekdayHeaders(1)), ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"])
})

test("parseStore accepts an empty file and refuses what it cannot read", () => {
  assert.deepEqual(plain(T.parseStore("")), { ok: true, tasks: [], error: "" })
  assert.equal(T.parseStore("{oops").ok, false)
  assert.equal(T.parseStore("[]").ok, false)
  assert.equal(T.parseStore('{"version":2,"tasks":[]}').ok, false)
  assert.equal(T.parseStore('{"version":1,"tasks":{}}').ok, false)
  assert.equal(T.parseStore('{"version":2,"tasks":[]}').error, "unsupported format version 2")
  // Errors are sent in error reports, so file content stays out of them.
  assert.equal(T.parseStore('{"version":{"text":"Private task"},"tasks":[]}').error, "unsupported format version")
})

test("parseStore refuses a file with any task it cannot read back exactly", () => {
  const good = { id: "a", text: "Call the bank", due: "2026-11-20", starred: true, createdAt: 5, doneAt: null }
  const file = (...tasks) => JSON.stringify({ version: 1, tasks })
  assert.deepEqual(plain(T.parseStore(file(good))).tasks, [good])
  assert.deepEqual(plain(T.parseStore(file({ id: "b", text: "Short", createdAt: 7 }))).tasks, [
    { id: "b", text: "Short", due: null, starred: false, createdAt: 7, doneAt: null }
  ])
  const bad = [
    "not an object",
    { ...good, id: "c d" },
    { ...good, text: "   " },
    { ...good, text: "  Call the bank  " },
    { ...good, due: "2026-02-30" },
    { ...good, starred: "yes" },
    { ...good, createdAt: -1 },
    { ...good, doneAt: "x" }
  ]
  for (const task of bad) {
    const result = plain(T.parseStore(file(good, task)))
    assert.equal(result.ok, false, JSON.stringify(task))
    assert.equal(result.error, "task 2 is not valid")
  }
  assert.equal(T.parseStore(file(good, { ...good, text: "Duplicate id" })).ok, false)
})

test("serialize round-trips through parseStore", () => {
  const tasks = [task({ id: "x", due: "2026-11-20", starred: true, doneAt: NOW })]
  const parsed = plain(T.parseStore(T.serialize(tasks)))
  assert.deepEqual(parsed.tasks, tasks)
})

test("addTask puts a clean new task first and ignores empty text", () => {
  const before = [task({ id: "old" })]
  const after = plain(T.addTask(before, "  Buy milk ", "2026-11-15", false, NOW, 0.5))
  assert.equal(after.length, 2)
  assert.equal(after[0].text, "Buy milk")
  assert.equal(after[0].due, "2026-11-15")
  assert.equal(after[0].starred, false)
  assert.equal(after[0].doneAt, null)
  assert.equal(after[0].createdAt, NOW)
  assert.match(after[0].id, /^[A-Za-z0-9_-]+$/)
  assert.equal(T.addTask(before, "   ", null, false, NOW, 0.5), before)
  assert.equal(plain(T.addTask([], "No date", "tomorrow", false, NOW, 0.1))[0].due, null)
})

test("addTask stars the new task only when asked to", () => {
  assert.equal(plain(T.addTask([], "Starred", null, true, NOW, 0.5))[0].starred, true)
  assert.equal(plain(T.addTask([], "Truthy", null, "yes", NOW, 0.5))[0].starred, false)
  assert.equal(plain(T.addTask([], "Left out", null, undefined, NOW, 0.5))[0].starred, false)
})

test("operations return new lists and leave the input alone", () => {
  const tasks = [task({ id: "a" }), task({ id: "b", doneAt: 9 })]
  const snapshot = plain(tasks)

  assert.equal(plain(T.setDone(tasks, "a", true, NOW))[0].doneAt, NOW)
  assert.equal(plain(T.setDone(tasks, "b", false, NOW))[1].doneAt, null)
  assert.equal(plain(T.toggleStar(tasks, "a"))[0].starred, true)
  assert.equal(plain(T.toggleStar(T.toggleStar(tasks, "a"), "a"))[0].starred, false)
  assert.equal(plain(T.setDue(tasks, "a", "2026-12-01"))[0].due, "2026-12-01")
  assert.equal(plain(T.setDue(tasks, "a", ""))[0].due, null)
  assert.deepEqual(plain(T.removeTask(tasks, "a")).map((t) => t.id), ["b"])
  assert.deepEqual(plain(T.clearDone(tasks)).map((t) => t.id), ["a"])

  assert.deepEqual(plain(tasks), snapshot)
})

test("open tasks: starred first, then by due date", () => {
  const tasks = [
    task({ id: "none", createdAt: 1 }),
    task({ id: "later", due: "2026-11-30" }),
    task({ id: "soon", due: "2026-11-17" }),
    task({ id: "tomorrow", due: "2026-11-15" }),
    task({ id: "today2", due: TODAY, createdAt: 3 }),
    task({ id: "today1", due: TODAY, createdAt: 2 }),
    task({ id: "overdue", due: "2026-11-01" }),
    task({ id: "starNoDate", starred: true, createdAt: 1 }),
    task({ id: "starLater", starred: true, due: "2026-12-24" }),
    task({ id: "starOverdue", starred: true, due: "2026-11-10" }),
    task({ id: "done", due: TODAY, doneAt: NOW })
  ]
  const sections = plain(T.openSections(tasks, TODAY))
  assert.deepEqual(
    sections.map((s) => [s.title, s.tasks.map((t) => t.id)]),
    [
      ["Starred", ["starOverdue", "starLater", "starNoDate"]],
      ["Overdue", ["overdue"]],
      ["Today", ["today1", "today2"]],
      ["Tomorrow", ["tomorrow"]],
      ["Upcoming", ["soon", "later"]],
      ["No date", ["none"]]
    ]
  )
  const rows = plain(T.rows(T.openSections(tasks, TODAY)))
  assert.deepEqual(rows[0], { kind: "header", key: "starred", title: "Starred", count: 3 })
  assert.equal(rows[1].kind, "task")
  assert.equal(rows[1].task.id, "starOverdue")
})

test("done tasks are grouped by completion day, newest first", () => {
  const tasks = [
    task({ id: "old", doneAt: new Date(2026, 10, 2, 8, 0).getTime() }),
    task({ id: "yesterday", doneAt: new Date(2026, 10, 13, 18, 0).getTime() }),
    task({ id: "early", doneAt: new Date(2026, 10, 14, 7, 0).getTime() }),
    task({ id: "late", doneAt: new Date(2026, 10, 14, 9, 0).getTime() }),
    task({ id: "open" })
  ]
  const sections = plain(T.doneSections(tasks, TODAY))
  assert.deepEqual(
    sections.map((s) => [s.title, s.tasks.map((t) => t.id)]),
    [
      ["Today", ["late", "early"]],
      ["Yesterday", ["yesterday"]],
      ["Mon, 2 Nov", ["old"]]
    ]
  )
  assert.equal(T.countOpen(tasks), 1)
  assert.equal(T.countDone(tasks), 4)
  assert.equal(T.timeOfDay(new Date(2026, 10, 14, 7, 5).getTime()), "07:05")
})
