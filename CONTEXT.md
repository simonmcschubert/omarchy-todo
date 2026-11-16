# To Do: terms

The words the code, the tests, and the README use for To Do's parts.

- **Task**: one to-do: a one-line title (`text`), a plain-text description,
  an optional due date (a local day), a star, and when it was done
  (`doneAt`). A done task keeps its due date and star.
- **Tasks file**: `tasks.json` in `$XDG_STATE_HOME/omarchy-todo/`, loaded and
  saved by `TaskStore.qml`. The store never writes over a file it cannot
  read; while it shows an error, it refuses changes.
- **Surface**: where the list shows: the **window** (all tabs), the
  **drop-down** (only Focus), or **quick add** (only the field for a new
  task, no list). The drop-down and quick add are one view.
- **Tab**: **Focus** (open tasks that are starred or due today), **To do**
  (`open`), and **Done**.
- **Typed task**: the task being written in the field at the top, with its
  own due date, star, and description, until it is added.
- **Selected task**: the task picked in the list with Up and Down. Ctrl+D and
  Ctrl+F act on it, or on the typed task while none is selected. Typing
  unselects it.
- **Opened task**: a task shown in place of the list (Enter on the selected
  task, or a click), its title and description edited in place.
- **List rules**: `list.js`, which decides what keys, clicks, and adding a
  task do to the tab, the selection, and the typed task. `TaskView.qml` sends
  it events and applies the effects it returns.
