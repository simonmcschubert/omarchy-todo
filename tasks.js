.pragma library

// Task logic without QML dependencies: storage format, operations, sorting,
// and date helpers. The node tests in test/ load this file directly.
//
// Stored file (version 2):
//   { "version": 2, "tasks": [ { "id", "text", "description", "due", "starred", "createdAt", "doneAt" } ] }
// text is one line. description is plain text over any number of lines, ""
// when there is none. due is a local calendar day "YYYY-MM-DD" or null;
// createdAt and doneAt are epoch milliseconds, doneAt null while the task is
// open. Version 1 is the same without description; it is read and saved as
// version 2, which older versions refuse instead of dropping descriptions.

var FORMAT_VERSION = 2
var READABLE_VERSIONS = [1, 2]
var MAX_TEXT_LENGTH = 1000
var MAX_DESCRIPTION_LENGTH = 10000
var MAX_TASKS = 10000

var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var MONTHS_LONG = ["January", "February", "March", "April", "May", "June", "July",
  "August", "September", "October", "November", "December"]

function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

// ---- dates ------------------------------------------------------------------

function dateKey(date) {
  return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
}

function isDateKey(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  var d = parseDateKey(value)
  return d !== null && dateKey(d) === value
}

// Local midnight of a "YYYY-MM-DD" key, or null.
function parseDateKey(key) {
  if (typeof key !== "string") return null
  var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(key)
  if (!m) return null
  var d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
  return isNaN(d.getTime()) ? null : d
}

function addDays(key, days) {
  var d = parseDateKey(key)
  if (!d) return null
  d.setDate(d.getDate() + days)
  return dateKey(d)
}

// Same day n months later, clamped to the month's last day (31 Jan -> 28 Feb).
function addMonths(key, months) {
  var d = parseDateKey(key)
  if (!d) return null
  var target = new Date(d.getFullYear(), d.getMonth() + months, 1)
  var lastDay = new Date(target.getFullYear(), target.getMonth() + 1, 0).getDate()
  target.setDate(Math.min(d.getDate(), lastDay))
  return dateKey(target)
}

// Whole calendar days from a to b (b - a), immune to daylight saving shifts.
function daysBetween(a, b) {
  var da = parseDateKey(a)
  var db = parseDateKey(b)
  if (!da || !db) return 0
  var ua = Date.UTC(da.getFullYear(), da.getMonth(), da.getDate())
  var ub = Date.UTC(db.getFullYear(), db.getMonth(), db.getDate())
  return Math.round((ub - ua) / 86400000)
}

// The next given weekday (0 = Sunday) strictly after today.
function nextWeekday(today, weekday) {
  var d = parseDateKey(today)
  if (!d) return null
  var delta = (weekday - d.getDay() + 7) % 7
  return addDays(today, delta === 0 ? 7 : delta)
}

function shortDate(key, today) {
  var d = parseDateKey(key)
  if (!d) return ""
  var label = d.getDate() + " " + MONTHS[d.getMonth()]
  var t = parseDateKey(today)
  if (!t || t.getFullYear() !== d.getFullYear()) label += " " + d.getFullYear()
  return label
}

// Label and state of a due date relative to today.
// state: "overdue" | "today" | "soon" (within 6 days) | "later"
function dueInfo(due, today) {
  if (!isDateKey(due)) return { label: "", state: "" }
  var diff = daysBetween(today, due)
  if (diff < 0) {
    return { label: diff === -1 ? "Yesterday" : shortDate(due, today), state: "overdue" }
  }
  if (diff === 0) return { label: "Today", state: "today" }
  if (diff === 1) return { label: "Tomorrow", state: "soon" }
  if (diff < 7) return { label: WEEKDAYS[parseDateKey(due).getDay()], state: "soon" }
  return { label: shortDate(due, today), state: "later" }
}

function dayHeading(key, today) {
  var diff = daysBetween(today, key)
  if (diff === 0) return "Today"
  if (diff === -1) return "Yesterday"
  var d = parseDateKey(key)
  return WEEKDAYS[d.getDay()] + ", " + shortDate(key, today)
}

function monthTitle(year, month) {
  return MONTHS_LONG[month] + " " + year
}

// 42 calendar cells (6 weeks) for a month view.
// firstDayOfWeek: 0 = Sunday ... 6 = Saturday (Qt.locale().firstDayOfWeek uses
// 7 for Sunday; pass value % 7).
function monthGrid(year, month, firstDayOfWeek) {
  var first = new Date(year, month, 1)
  var offset = (first.getDay() - firstDayOfWeek + 7) % 7
  var start = new Date(year, month, 1 - offset)
  var cells = []
  for (var i = 0; i < 42; i++) {
    var d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
    cells.push({ key: dateKey(d), day: d.getDate(), inMonth: d.getMonth() === month })
  }
  return cells
}

function weekdayHeaders(firstDayOfWeek) {
  var out = []
  for (var i = 0; i < 7; i++) out.push(WEEKDAYS[(firstDayOfWeek + i) % 7].substring(0, 2))
  return out
}

// ---- storage ----------------------------------------------------------------

// At most max characters of trimmed text, without half an emoji at the cut or
// whitespace before it, so cutting a cut text changes nothing.
function cut(text, max) {
  if (text.length <= max) return text
  var end = max
  var last = text.charCodeAt(end - 1)
  if (last >= 0xD800 && last <= 0xDBFF) end--
  return text.substring(0, end).replace(/\s+$/, "")
}

// Cleaning clean text changes nothing, so a saved title or description
// always reads back.
function cleanText(value) {
  if (typeof value !== "string") return ""
  return cut(value.replace(/[\r\n\t]+/g, " ").trim(), MAX_TEXT_LENGTH)
}

// Line endings become "\n" and the ends are trimmed.
function cleanDescription(value) {
  if (typeof value !== "string") return ""
  return cut(value.replace(/\r\n?/g, "\n").trim(), MAX_DESCRIPTION_LENGTH)
}

function finiteOrNull(value) {
  return typeof value === "number" && isFinite(value) && value > 0 ? Math.floor(value) : null
}

// A clean task from untrusted input, or null when it cannot be one.
function normalizeTask(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null
  var text = cleanText(raw.text)
  if (!text) return null
  var id = typeof raw.id === "string" && /^[A-Za-z0-9_-]{1,64}$/.test(raw.id) ? raw.id : null
  if (!id) return null
  return {
    id: id,
    text: text,
    description: cleanDescription(raw.description),
    due: isDateKey(raw.due) ? raw.due : null,
    starred: raw.starred === true,
    createdAt: finiteOrNull(raw.createdAt) || 0,
    doneAt: finiteOrNull(raw.doneAt)
  }
}

// { ok, tasks, error }. An empty file is an empty list. Anything this version
// cannot read safely is an error, so the caller never overwrites it.
function parseStore(text) {
  if (typeof text !== "string" || text.trim() === "") return { ok: true, tasks: [], error: "" }
  var data
  try {
    data = JSON.parse(text)
  } catch (e) {
    return { ok: false, tasks: [], error: "not valid JSON" }
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return { ok: false, tasks: [], error: "unexpected content" }
  }
  if (READABLE_VERSIONS.indexOf(data.version) < 0) {
    // Errors are reported, so they never quote the file beyond a number.
    var version = typeof data.version === "number" ? " " + data.version : ""
    return { ok: false, tasks: [], error: "unsupported format version" + version }
  }
  if (!Array.isArray(data.tasks)) return { ok: false, tasks: [], error: "tasks is not a list" }
  if (data.tasks.length > MAX_TASKS) return { ok: false, tasks: [], error: "more than " + MAX_TASKS + " tasks" }
  // Saving writes back only what was read, so a task that does not read back
  // exactly would be lost or changed: refuse the whole file instead.
  var tasks = []
  var seen = {}
  for (var i = 0; i < data.tasks.length; i++) {
    var raw = data.tasks[i]
    var task = normalizeTask(raw)
    if (!task || seen[task.id] || !readsBack(raw, task)) {
      return { ok: false, tasks: [], error: "task " + (i + 1) + " is not valid" }
    }
    seen[task.id] = true
    tasks.push(task)
  }
  return { ok: true, tasks: tasks, error: "" }
}

// Whether a stored task is exactly what normalizeTask made of it.
// description, due, starred, and doneAt may be left out.
function readsBack(raw, task) {
  return raw.text === task.text
    && (raw.description === undefined ? "" : raw.description) === task.description
    && (raw.due === undefined ? null : raw.due) === task.due
    && (raw.starred === undefined ? false : raw.starred) === task.starred
    && raw.createdAt === task.createdAt
    && (raw.doneAt === undefined ? null : raw.doneAt) === task.doneAt
}

function serialize(tasks) {
  return JSON.stringify({ version: FORMAT_VERSION, tasks: tasks }, null, 2) + "\n"
}

// ---- operations (each returns a new list) -----------------------------------

function newId(now, random) {
  return "t" + Math.floor(now).toString(36) + Math.floor(random * 1679616).toString(36)
}

function addTask(tasks, text, description, due, starred, now, random) {
  var clean = cleanText(text)
  if (!clean || tasks.length >= MAX_TASKS) return tasks
  var id = newId(now, random)
  while (tasks.some(function(t) { return t.id === id })) id += "x"
  return [{
    id: id,
    text: clean,
    description: cleanDescription(description),
    due: isDateKey(due) ? due : null,
    starred: starred === true,
    createdAt: Math.floor(now),
    doneAt: null
  }].concat(tasks)
}

function findTask(tasks, id) {
  for (var i = 0; i < tasks.length; i++) if (tasks[i].id === id) return tasks[i]
  return null
}

function update(tasks, id, change) {
  return tasks.map(function(t) {
    if (t.id !== id) return t
    var copy = {}
    for (var k in t) copy[k] = t[k]
    for (var c in change) copy[c] = change[c]
    return copy
  })
}

function setDone(tasks, id, done, now) {
  return update(tasks, id, { doneAt: done ? Math.floor(now) : null })
}

function toggleStar(tasks, id) {
  var task = findTask(tasks, id)
  return task ? update(tasks, id, { starred: !task.starred }) : tasks
}

// A new title and description. An empty title keeps the old one. The same
// list when nothing changes.
function editTask(tasks, id, text, description) {
  var task = findTask(tasks, id)
  if (!task) return tasks
  var change = {}
  var title = cleanText(text)
  if (title && title !== task.text) change.text = title
  var notes = cleanDescription(description)
  if (notes !== task.description) change.description = notes
  return Object.keys(change).length > 0 ? update(tasks, id, change) : tasks
}

function setDue(tasks, id, due) {
  return update(tasks, id, { due: isDateKey(due) ? due : null })
}

function removeTask(tasks, id) {
  return tasks.filter(function(t) { return t.id !== id })
}

function clearDone(tasks) {
  return tasks.filter(function(t) { return t.doneAt === null })
}

// ---- views ------------------------------------------------------------------

function byDueThenCreated(a, b) {
  if (a.due !== b.due) {
    if (a.due === null) return 1
    if (b.due === null) return -1
    return a.due < b.due ? -1 : 1
  }
  return a.createdAt - b.createdAt
}

// Open tasks in sections: Starred first (the priority list), then the rest by
// due date: Overdue, Today, Tomorrow, Upcoming, No date. Empty sections are left out.
function openSections(tasks, today) {
  var starred = []
  var groups = { overdue: [], today: [], tomorrow: [], upcoming: [], none: [] }
  tasks.forEach(function(t) {
    if (t.doneAt !== null) return
    if (t.starred) { starred.push(t); return }
    if (t.due === null) { groups.none.push(t); return }
    var diff = daysBetween(today, t.due)
    if (diff < 0) groups.overdue.push(t)
    else if (diff === 0) groups.today.push(t)
    else if (diff === 1) groups.tomorrow.push(t)
    else groups.upcoming.push(t)
  })
  var sections = [
    { key: "starred", title: "Starred", tasks: starred },
    { key: "overdue", title: "Overdue", tasks: groups.overdue },
    { key: "today", title: "Today", tasks: groups.today },
    { key: "tomorrow", title: "Tomorrow", tasks: groups.tomorrow },
    { key: "upcoming", title: "Upcoming", tasks: groups.upcoming },
    { key: "none", title: "No date", tasks: groups.none }
  ]
  return sections.filter(function(s) {
    s.tasks.sort(byDueThenCreated)
    return s.tasks.length > 0
  })
}

// Done tasks grouped by the day they were completed, newest first.
function doneSections(tasks, today) {
  var done = tasks.filter(function(t) { return t.doneAt !== null })
  done.sort(function(a, b) { return b.doneAt - a.doneAt })
  var sections = []
  var current = null
  done.forEach(function(t) {
    var key = dateKey(new Date(t.doneAt))
    if (!current || current.key !== key) {
      current = { key: key, title: dayHeading(key, today), tasks: [] }
      sections.push(current)
    }
    current.tasks.push(t)
  })
  return sections
}

// Sections flattened into list rows: { kind: "header", title, count } and
// { kind: "task", task }.
function rows(sections) {
  var out = []
  sections.forEach(function(s) {
    out.push({ kind: "header", key: s.key, title: s.title, count: s.tasks.length })
    s.tasks.forEach(function(t) { out.push({ kind: "task", key: t.id, task: t }) })
  })
  return out
}

function countOpen(tasks) {
  return tasks.filter(function(t) { return t.doneAt === null }).length
}

function countDone(tasks) {
  return tasks.length - countOpen(tasks)
}

function timeOfDay(ms) {
  var d = new Date(ms)
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}
