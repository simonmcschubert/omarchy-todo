# 1. No shared table for tabs and keys

Date: 2026-11-16. Status: accepted.

## Context

Adding the Focus tab touched six files: each tab and each key is written out
in the list rules (`list.js`), in `TaskView.qml` (tab buttons, tooltips, the
empty list's text), in the keyboard shortcuts box (`Shortcuts.qml`), and in
`README.md`. An architecture review considered one table of tabs and keys
that the tab buttons, the key handling, and the shortcuts box would all read.

## Decision

No shared table. The surface is one value (`surface`: window, drop-down, or
quick add) instead of three booleans, and tabs and keys stay written out
where they are used.

## Reasons

- What a key does depends on focus, the typed text, modifiers, and the
  surface. A table that held that would be code again; `list.js` already
  holds it, with tests.
- The shortcuts box is text for people, worded for each surface.
- With three tabs and no fourth planned, the indirection costs more than the
  edits it would save.

Revisit when a fourth tab or user-configurable keys come up.
