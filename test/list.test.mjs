// Unit tests for list.js, the task list's keyboard and selection rules.
// Run: node --test test/
process.env.TZ = "Europe/Berlin"

import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

// QML JavaScript libraries: drop their pragma and imports and run them as
// scripts. list.js imports tasks.js as Tasks.
const script = (name) => readFileSync(new URL(`../${name}`, import.meta.url), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
  .replace(/^\.import .*$/gm, "")
const T = vm.createContext({})
vm.runInContext(script("tasks.js"), T)
const L = vm.createContext({ Tasks: T })
vm.runInContext(script("list.js"), L)

// Values from the script contexts have their prototypes.
const plain = (value) => JSON.parse(JSON.stringify(value))

const NOW = new Date(2026, 10, 14, 9, 30).getTime() // Sat 14 Nov 2026, 09:30
const TODAY = "2026-11-14"

function task(over) {
  return { id: "a", text: "Task", description: "", due: null, starred: false, createdAt: 1, doneAt: null, ...over }
}

// To do shows a (Starred), b (Today), c (Upcoming); Focus a and b; Done d.
const TASKS = [
  task({ id: "a", text: "Renew passport", starred: true, createdAt: 1 }),
  task({ id: "b", text: "Call the dentist", due: TODAY, createdAt: 2 }),
  task({ id: "c", text: "Review the notes", due: "2026-12-01", createdAt: 3 }),
  task({ id: "d", text: "Water the plants", due: TODAY, starred: true, createdAt: 4, doneAt: NOW - 1000 })
]

// TaskStore's operations over tasks.js.
function fakeStore(tasks) {
  const store = {
    tasks, today: TODAY,
    commit(next) {
      if (next === store.tasks) return false
      store.tasks = next
      return true
    },
    add(text, description, due, starred) {
      return store.commit(T.addTask(store.tasks, text, description, due, starred, NOW, 0.5)) ? store.tasks[0].id : ""
    },
    toggleStar(id) { return store.commit(T.toggleStar(store.tasks, id)) },
    setDue(id, due) { return store.commit(T.setDue(store.tasks, id, due)) }
  }
  return store
}

// TaskView, as far as the rules see it: the rows of the tab shown, the
// typed task's text, whether a task is open.
function view(surface, tasks = TASKS) {
  const v = { surface, store: fakeStore(tasks), state: L.initial(surface), typed: "", description: "", taskOpen: false }
  v.send = (event) => {
    const sections = v.state.tab === "focus" ? T.focusSections : v.state.tab === "open" ? T.openSections : T.doneSections
    const result = L.step(v.state, event, {
      surface: v.surface, rows: T.rows(sections(v.store.tasks, TODAY)), typed: v.typed,
      description: v.description, taskOpen: v.taskOpen, store: v.store
    })
    if (!result) return null
    v.state = result.state
    const effects = plain(result.effects)
    if (effects.openTask) v.taskOpen = true
    if (effects.hideTask) v.taskOpen = false
    if (effects.clearTyped) v.typed = v.description = ""
    return effects
  }
  v.key = (name, from = "title") => v.send({ type: "key", name, from })
  v.find = (id) => plain(T.findTask(v.store.tasks, id))
  return v
}

test("the window opens on To do; the drop-down and quick add on Focus", () => {
  assert.equal(L.initial("window").tab, "open")
  assert.equal(L.initial("dropdown").tab, "focus")
  assert.equal(L.initial("add").tab, "focus")
})

test("Up and Down select tasks in list order; Up from the first goes back to the typed task", () => {
  const v = view("window")
  assert.deepEqual(v.key("Down"), { reveal: "a" })
  v.key("Down")
  v.key("Down")
  assert.equal(v.state.selectedId, "c")
  v.key("Down")
  assert.equal(v.state.selectedId, "c")
  v.key("Up")
  v.key("Up")
  assert.equal(v.state.selectedId, "a")
  v.key("Up")
  assert.equal(v.state.selectedId, "")
})

test("in the typed task's description, Up and Down stay with the text", () => {
  const v = view("window")
  assert.equal(v.key("Down", "description"), null)
  assert.equal(v.state.selectedId, "")
})

test("Enter with nothing typed opens the selected task, only from the title field", () => {
  const v = view("window")
  v.key("Down")
  // After adding a typed task, the field passes Enter on: no task opens.
  assert.equal(v.key("Enter", "other"), null)
  v.typed = "Buy milk"
  assert.equal(v.key("Enter"), null)
  v.typed = " "
  assert.deepEqual(v.key("Enter"), { openTask: "a" })
})

test("typing in the typed task's title or description unselects the task", () => {
  const v = view("window")
  v.key("Down")
  v.send({ type: "typed" })
  assert.equal(v.state.selectedId, "")
})

test("Ctrl+D picks the selected task's due date, else the typed task's", () => {
  const v = view("window")
  v.key("Down")
  v.key("Down")
  assert.deepEqual(v.key("Ctrl+D"), { hideTask: true, focus: "new", picker: { target: "b", current: TODAY } })
  // The task may move to another section; it stays in view.
  assert.deepEqual(v.send({ type: "picked", due: "2026-11-20" }), { reveal: "b" })
  assert.equal(v.find("b").due, "2026-11-20")

  v.send({ type: "typed" })
  assert.deepEqual(v.key("Ctrl+D").picker, { target: "", current: "" })
  assert.deepEqual(v.send({ type: "picked", due: "2026-11-30" }), {})
  assert.equal(v.state.newDue, "2026-11-30")
  assert.deepEqual(v.key("Ctrl+D").picker, { target: "", current: "2026-11-30" })
})

test("a done task keeps its due date and star", () => {
  const v = view("window")
  v.key("Ctrl+3")
  v.key("Down")
  assert.equal(v.state.selectedId, "d")
  assert.deepEqual(v.key("Ctrl+D"), { hideTask: true, focus: "new" })
  assert.deepEqual(v.send({ type: "pickDue", id: "d" }), {})
  assert.deepEqual(v.key("Ctrl+F"), { hideTask: true, focus: "new" })
  assert.equal(v.find("d").starred, true)
})

test("Ctrl+F stars or unstars the selected task, else the typed task", () => {
  const v = view("window")
  v.key("Down")
  assert.equal(v.key("Ctrl+F").reveal, "a")
  assert.equal(v.find("a").starred, false)

  v.send({ type: "typed" })
  v.key("Ctrl+F")
  assert.equal(v.state.newStarred, true)
  v.send({ type: "starNew" })
  assert.equal(v.state.newStarred, false)
})

test("Ctrl+D and Ctrl+F while writing the description return to it", () => {
  const v = view("window")
  v.typed = "Buy milk"
  assert.deepEqual(v.send({ type: "describe" }), { focus: "description" })
  v.description = "2 litres"
  assert.equal(v.key("Ctrl+F", "description").focus, "new")
  // TaskView focuses the description for "new" while it is open.
  assert.equal(v.state.describing, true)
  // Leaving it closes it only when it is empty.
  assert.equal(v.send({ type: "descriptionLeft", empty: false }), null)
  v.send({ type: "descriptionLeft", empty: true })
  assert.equal(v.state.describing, false)
})

test("Esc goes back from an opened task or the shortcuts, else unselects, else asks to close", () => {
  const v = view("window")
  v.key("Down")
  v.key("Enter")
  assert.equal(v.taskOpen, true)
  assert.deepEqual(v.key("Escape", "other"), { hideTask: true, focus: "new" })
  // Back from the task, it stays selected.
  assert.equal(v.state.selectedId, "a")
  assert.deepEqual(v.key("Escape"), {})
  assert.equal(v.state.selectedId, "")
  assert.deepEqual(v.key("Escape"), { close: true })

  assert.deepEqual(v.key("Ctrl+?"), { focus: "shortcuts" })
  assert.equal(v.state.shortcutsShown, true)
  // The arrow keys belong to the box while it is open.
  assert.equal(v.key("Down", "other"), null)
  v.key("Escape", "other")
  assert.equal(v.state.shortcutsShown, false)
  v.send({ type: "shortcuts" })
  assert.deepEqual(v.send({ type: "shortcuts" }), { hideTask: true, focus: "new" })
})

test("Ctrl+1 to Ctrl+3 switch tabs in the window; the drop-down has only Focus", () => {
  const v = view("window")
  v.key("Down")
  assert.deepEqual(v.key("Ctrl+3"), { hideTask: true, focus: "new", scrollTop: true })
  assert.equal(v.state.tab, "done")
  v.key("Ctrl+2")
  assert.equal(v.state.tab, "open")
  v.key("Ctrl+1")
  assert.equal(v.state.tab, "focus")
  assert.equal(v.key("Ctrl+1").scrollTop, undefined)

  const d = view("dropdown")
  assert.equal(d.key("Ctrl+2"), null)
  assert.equal(d.key("Ctrl+3"), null)
  assert.equal(d.state.tab, "focus")
})

test("a click on a task opens and selects it; changing tabs unselects", () => {
  const v = view("window")
  assert.deepEqual(v.send({ type: "open", id: "c" }), { openTask: "c" })
  assert.equal(v.state.selectedId, "c")
  v.send({ type: "back" })
  assert.deepEqual(v.send({ type: "tab", tab: "done" }), { scrollTop: true })
  assert.equal(v.state.selectedId, "")
  assert.deepEqual(v.send({ type: "tab", tab: "done" }), {})
})

test("quick add is only the field: Ctrl+D, Ctrl+F, and Esc act on the typed task", () => {
  // The drop-down and quick add are one view; a task selected in the
  // drop-down is not selected in quick add.
  const v = view("dropdown")
  v.key("Down")
  assert.equal(v.state.selectedId, "a")
  v.surface = "add"
  v.key("Ctrl+F")
  assert.equal(v.state.newStarred, true)
  assert.equal(v.find("a").starred, true)
  assert.equal(v.key("Ctrl+D").picker.target, "")
  for (const name of ["Ctrl+1", "Ctrl+?", "Up", "Down", "Enter"]) assert.equal(v.key(name), null, name)
  assert.deepEqual(v.key("Escape"), { close: true })
})

test("adding the typed task saves its description, due date, and star, then empties it", () => {
  const v = view("window")
  v.key("Ctrl+D")
  v.send({ type: "picked", due: "2026-12-24" })
  v.key("Ctrl+F")
  v.send({ type: "describe" })
  v.typed = "Buy presents"
  v.description = "For the family"
  const effects = v.send({ type: "submit" })
  const id = v.store.tasks[0].id
  assert.deepEqual(effects, { focus: "title", clearTyped: true, reveal: id, added: id })
  assert.deepEqual(v.find(id), { ...v.find(id), text: "Buy presents", description: "For the family", due: "2026-12-24", starred: true })
  assert.deepEqual([v.state.newDue, v.state.newStarred, v.state.describing], ["", false, false])
  assert.equal(v.typed, "")
})

test("nothing typed adds nothing", () => {
  const v = view("window")
  v.typed = "   "
  assert.equal(v.send({ type: "submit" }), null)
  assert.equal(v.store.tasks.length, TASKS.length)
})

test("a new task shows in Focus when it belongs there, else in To do; the drop-down stays on Focus", () => {
  const v = view("window")
  v.key("Ctrl+1")
  v.key("Ctrl+F")
  v.typed = "Starred task"
  assert.equal(v.send({ type: "submit" }).scrollTop, undefined)
  assert.equal(v.state.tab, "focus")
  v.typed = "Plain task"
  assert.equal(v.send({ type: "submit" }).scrollTop, true)
  assert.equal(v.state.tab, "open")

  const d = view("dropdown")
  d.typed = "Plain task"
  const effects = d.send({ type: "submit" })
  assert.equal(d.state.tab, "focus")
  assert.equal(effects.reveal, d.store.tasks[0].id)
})

test("quick add keeps the drop-down's tab and reveals nothing", () => {
  const v = view("add")
  v.typed = "Quick task"
  const id = "t" + Math.floor(NOW).toString(36) + Math.floor(0.5 * 1679616).toString(36)
  assert.deepEqual(v.send({ type: "submit" }), { focus: "title", clearTyped: true, added: id })
  assert.equal(v.store.tasks[0].id, id)
  assert.equal(v.state.tab, "focus")
})
