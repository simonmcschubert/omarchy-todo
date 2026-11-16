.pragma library
.import "tasks.js" as Tasks

// The task list's keyboard and selection rules, without QML: which task a
// key acts on (the selected task, or the typed task while none is), what
// Esc, Enter, and the arrow keys do, and what adding a task does to the tab
// and the typed task. TaskView.qml keeps the state, sends events, and
// applies the effects; the node tests in test/ load this file directly.
//
// Surfaces: "window" (all tabs), "dropdown" (only Focus), "add" (quick add:
// only the typed task's field, no list).
//
// State (initial):
//   tab             "focus", "open" (To do), or "done"
//   selectedId      the selected task, "" when none
//   shortcutsShown  the keyboard shortcuts box is open
//   describing      the typed task's description field is open
//   newDue          the typed task's due date, "" for none
//   newStarred      whether the typed task is starred
//   pickerTarget    what the date picker sets: "" the typed task, else a task id
//
// step(state, event, ctx) returns { state, effects }, or null when the event
// does nothing (a key that is no shortcut then goes on to the field).
//
// ctx:
//   surface      as above
//   rows         the rows of the tab shown (Tasks.rows)
//   typed        the title field's text
//   description  the typed task's description
//   taskOpen     a task opened from the list is shown instead of the list
//   store        TaskStore: tasks, today, add, toggleStar, setDue
//
// Events: { type: ... }
//   key           name ("Escape", "Enter", "Up", "Down", "Ctrl+D", "Ctrl+F",
//                 "Ctrl+1" to "Ctrl+3", "Ctrl+?"), from: "title" (the title
//                 field, before it handles the key), "description" (passed
//                 on by the typed task's description), or "other" (passed on
//                 by anything else, the title field included)
//   typed         the typed task's title or description was typed in
//   describe      Tab in the title field
//   descriptionLeft  empty: whether the description left was empty
//   submit        add the typed task
//   starNew       the typed task's star button
//   tab           tab: a tab button
//   shortcuts     the keyboard shortcuts button
//   open          id: a click on a task's row
//   pickDue       id: a due date button ("" the typed task's)
//   picked        due: the date picker's choice
//   back          back to the list, ready to type a task
//   taskClosed    the opened task closed (deleted elsewhere, or Back)
//
// Effects, which TaskView applies in this order:
//   hideTask      close the opened task, which saves it
//   focus         "new" (the typed task: its description while open, else
//                 the title field), "title", "description", or "shortcuts"
//   clearTyped    empty the typed task's title and description
//   scrollTop     show the top of the list
//   picker        { target, current }: open the date picker
//   openTask      id: open this task
//   reveal        id: scroll to this task once the rows show it
//   close         nothing to go back from: the view asks to close
//   added         id: a task was added (last: quick add closes on it)

function initial(surface) {
  return {
    tab: surface === "window" ? "open" : "focus",
    selectedId: "",
    shortcutsShown: false,
    describing: false,
    newDue: "",
    newStarred: false,
    pickerTarget: ""
  }
}

// The selected task while it is in the rows shown, else null. Quick add
// shows no list, so nothing is selected there.
function selectedTask(state, ctx) {
  if (ctx.surface === "add" || state.selectedId === "") return null
  for (var i = 0; i < ctx.rows.length; i++)
    if (ctx.rows[i].kind === "task" && ctx.rows[i].key === state.selectedId) return ctx.rows[i].task
  return null
}

function step(state, event, ctx) {
  var state2 = {}
  for (var k in state) state2[k] = state[k]
  var r = { state: state2, effects: {} }
  return handle(r, event, ctx) ? r : null
}

function handle(r, event, ctx) {
  var s = r.state
  switch (event.type) {
  case "key": return key(r, event, ctx)
  case "typed":
    s.selectedId = ""
    return true
  case "describe":
    s.describing = true
    r.effects.focus = "description"
    return true
  case "descriptionLeft":
    if (!event.empty) return false
    s.describing = false
    return true
  case "submit": return submit(r, ctx)
  case "starNew":
    s.newStarred = !s.newStarred
    return true
  case "tab":
    setTab(r, event.tab)
    return true
  case "shortcuts":
    toggleShortcuts(r)
    return true
  case "open":
    open(r, event.id)
    return true
  case "pickDue":
    pickDue(r, event.id, ctx)
    return true
  case "picked": return picked(r, event.due, ctx)
  case "back":
    back(r)
    return true
  case "taskClosed":
    r.effects.focus = "new"
    return true
  }
  return false
}

// Shortcuts that work anywhere in the view, also while typing a task.
function key(r, event, ctx) {
  var s = r.state
  var name = event.name
  var selected = selectedTask(s, ctx)
  if (name === "Escape") {
    if (s.shortcutsShown || ctx.taskOpen) back(r)
    else if (selected) s.selectedId = ""
    else r.effects.close = true
    return true
  }
  if (name === "Ctrl+D") {
    back(r)
    pickDue(r, selected ? selected.id : "", ctx)
    return true
  }
  if (name === "Ctrl+F") {
    back(r)
    if (!selected) s.newStarred = !s.newStarred
    else if (ctx.store.toggleStar(selected.id)) r.effects.reveal = selected.id
    return true
  }
  // Quick add is only the field: the rest needs the list.
  if (ctx.surface === "add") return false
  if (name === "Ctrl+?") {
    toggleShortcuts(r)
    return true
  }
  if (name === "Ctrl+1" || ((name === "Ctrl+2" || name === "Ctrl+3") && ctx.surface === "window")) {
    back(r)
    setTab(r, name === "Ctrl+1" ? "focus" : name === "Ctrl+2" ? "open" : "done")
    return true
  }
  // In the description, the arrow keys stay with the text.
  if ((name === "Up" || name === "Down") && !s.shortcutsShown && !ctx.taskOpen && event.from !== "description") {
    move(r, name === "Down" ? 1 : -1, selected, ctx)
    return true
  }
  // Only the title field opens the selected task: after adding a typed
  // task, the field passes its Enter on.
  if (name === "Enter" && event.from === "title" && selected && !s.shortcutsShown && !ctx.taskOpen
      && ctx.typed.trim() === "") {
    open(r, selected.id)
    return true
  }
  return false
}

// Back to the list, ready to type a task.
function back(r) {
  r.state.shortcutsShown = false
  r.effects.hideTask = true
  r.effects.focus = "new"
}

function setTab(r, tab) {
  if (r.state.tab === tab) return
  r.state.tab = tab
  r.state.selectedId = ""
  r.effects.scrollTop = true
}

function toggleShortcuts(r) {
  if (r.state.shortcutsShown) {
    back(r)
  } else {
    r.state.shortcutsShown = true
    r.effects.focus = "shortcuts"
  }
}

function open(r, id) {
  r.state.selectedId = id
  r.effects.openTask = id
}

// Up and Down select the task below or above. Up from the first task goes
// back to the typed task.
function move(r, delta, selected, ctx) {
  var ids = []
  for (var i = 0; i < ctx.rows.length; i++)
    if (ctx.rows[i].kind === "task") ids.push(ctx.rows[i].key)
  var index = selected ? ids.indexOf(selected.id) + delta : (delta > 0 ? 0 : -1)
  if (index < 0) {
    r.state.selectedId = ""
  } else if (index < ids.length) {
    r.state.selectedId = ids[index]
    r.effects.reveal = ids[index]
  }
}

// The date picker for a task, or for the typed task (id ""). A done task
// keeps its date, so the picker does not open for it.
function pickDue(r, id, ctx) {
  r.state.shortcutsShown = false
  if (id === "") {
    r.state.pickerTarget = ""
    r.effects.picker = { target: "", current: r.state.newDue }
    return
  }
  var task = Tasks.findTask(ctx.store.tasks, id)
  if (!task || task.doneAt !== null) return
  r.state.pickerTarget = id
  r.effects.picker = { target: id, current: task.due || "" }
}

function picked(r, due, ctx) {
  var target = r.state.pickerTarget
  if (target === "") {
    r.state.newDue = due
  } else {
    ctx.store.setDue(target, due)
    // The task may move to another section; keep the selection in view.
    if (target === r.state.selectedId) r.effects.reveal = target
  }
  return true
}

function submit(r, ctx) {
  var s = r.state
  if (ctx.typed.trim() === "") return false
  var id = ctx.store.add(ctx.typed, ctx.description, s.newDue, s.newStarred)
  if (id === "") return false
  s.describing = false
  s.newDue = ""
  s.newStarred = false
  r.effects.focus = "title"
  r.effects.clearTyped = true
  if (ctx.surface !== "add") {
    // Show the new task: in Focus when it belongs there, else in To do.
    // The drop-down shows only Focus, so it stays there.
    if (ctx.surface === "window"
        && !(s.tab === "focus" && Tasks.inFocus(Tasks.findTask(ctx.store.tasks, id), ctx.store.today)))
      setTab(r, "open")
    r.effects.reveal = id
  }
  r.effects.added = id
  return true
}
