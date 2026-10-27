# Changelog

## [1.0.0] - 2026-10-27

The first release.

### Added

- A hill on the bar with a dot for each project, gliding to its new spot whenever one moves.
- Hovering the bar hill shows a card with every project on a little hill of its own: the stretch it has already climbed in its color, and how far along it is.
- Clicking opens the whole hill. Drag a dot, or its label, along the curve; it rides the slope, and the top and both ends pull it in. A bubble shows where it would land, the top of the hill lights up as it gets there, and a project cresting the top or reaching done celebrates.
- Add a project by typing its name, or by double-clicking the hill where it already stands.
- Labels: hide any project's label by double-clicking it or with the eye on its row; double-clicking its dot brings it back. Show all and Hide all, or Shift+T, do every label at once.
- Colors: new projects get one from your theme; right-click a dot, click its color on its row, or press c to pick your own.
- A list under the hill, in hill order: rename (double-click, ✎ or Enter), done and back, remove.
- Every change can be undone (Ctrl+Z).
- Projects that haven't moved for a while (7 days by default) get a red ring.
- The whole panel works from the keyboard.
- Commands for scripts and key bindings: `omarchy-shell marcho78.hillchart toggle | peek | add | addAt | move | remove | list`.

### Security

- Every file Hill Chart reads or writes goes through one small helper, `bin/hillchart-files`. It follows no symbolic links, reads nothing past a fixed size, and writes atomically, readable by you only, inside your home folder only.
- Programs run by absolute path, each in its own process group with an output budget and a deadline.
- No network, no root, and nothing downloaded or compiled.
