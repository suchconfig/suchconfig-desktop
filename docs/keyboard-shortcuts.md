# Keyboard shortcuts

Default shortcuts for SuchConfig. Inspired by [Linear](https://linear.app/docs/keyboard-shortcuts)-style sequences and [Alfred](https://www.alfredapp.com/help/getting-started/cheatsheet/)-style discoverability.

If a shortcut conflicts with OS or browser bindings, prefer the in-app command palette (`⌘K` / `Ctrl+K`).

Legend:

| Symbol | Meaning |
| --- | --- |
| `⌘` | Command (macOS) / mapped to Ctrl on Windows/Linux where noted |
| `⌃` | Control |
| `⇧` | Shift |
| `↵` | Return / Enter |
| `⎋` | Escape |
| `then` | Press keys in sequence within ~1s (not held together) |

---

## Global

| Shortcut | Action |
| --- | --- |
| `⌘K` / `Ctrl+K` | Open command palette |
| `⌃⇧L` | Lock vault (or prompt unlock when locked) |
| `⎋` | Close command palette / password generator / dismiss overlay |

Chords are ignored while typing in inputs, textareas, or contenteditable fields.

---

## Navigation chords (`G then …`)

| Shortcut | Action |
| --- | --- |
| `G` then `D` | Open Dashboard |
| `G` then `W` | Open Projects |
| `G` then `P` | Open Project Vault |
| `G` then `S` | Open Secrets Vault |
| `G` then `G` | Toggle Password Generator |
| `G` then `,` | Open Settings |
| `G` then `E` | Export sealed archive |
| `G` then `I` | Import sealed archive |

---

## Create chords (`N then …`)

| Shortcut | Action |
| --- | --- |
| `N` then `L` | New login entry |
| `N` then `A` | New API key |
| `N` then `S` | New SSH key |
| `N` then `N` | New secure note |
| `N` then `P` | New project |

---

## Command palette

Open with `⌘K` / `Ctrl+K`, then:

| Shortcut | Action |
| --- | --- |
| `↑` / `↓` | Move selection |
| `↵` | Run selected command |
| `⎋` | Close |
| `G` / `N` chords | Same as global — runs the matching command and closes the palette |

Click any row to run it. Hint labels on each row mirror the shortcuts above.

---

## Notes

- Secrets Vault create/nav chords require Secrets Vault to be enabled for the build.
- Sealed archive import/export opens Project Vault’s archive panel (`.suchvault`), not third-party manager formats. Manager import (`.1pux` / CSV) is tracked separately for a future release.
- Chord prefixes (`G`, `N`) reset after ~1 second if no follow-up key is pressed.
