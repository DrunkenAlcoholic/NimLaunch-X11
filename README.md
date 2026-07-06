# NimLaunch X11

This is the original X11 version of NimLaunch.

The main SDL version is available here:

https://github.com/DrunkenAlcoholic/NimLaunch

This X11 branch is kept for users who prefer a small Xlib/Xft launcher with
minimal runtime dependencies on traditional X11 desktops and window managers.



Lightning-fast, X11-native application and command launcher written in Nim. Pure
Xlib/Xft rendering, instant fuzzy search, rich themes, and no GTK/Qt dependency.
Optional icon rendering can be enabled at build time with Imlib2.

![NimLaunch screenshot](Screenshot.gif)

---

## Features

- **Instant fuzzy search** – typo-tolerant scoring that favours prefixes, word
  boundaries, and recent launches.
- **Keyboard-first workflow** – arrow keys or Vim-style navigation, quick
  command prefixes (`:s`, `:c`, `:t`, `:r`, `:p`, `!`), plus custom shortcuts.
- **Small & native** – no GTK/Qt; just Nim, Xlib, and Xft.
- **Smart filesystem search** – `:s` uses `fd` when available, falls back to
  `locate`, then a bounded walk under `$HOME`.
- **Desktop actions** – searchable `.desktop` actions such as “New Window” or
  “Private Window” appear as `App: Action` results when the app declares them.
- **Optional icons** – app icon names are cached from `.desktop` files; default
  builds stay text-only, while `-d:icons` builds render icons with Imlib2.
- **Themeable** – 25+ bundled themes with instant `:t` preview and easy TOML tweaks.
- **Single-instance guard** – second launch exits immediately instead of
  spawning duplicate windows.

---

## Installation

### Prebuilt binary

Download the latest release from this repository and run `./bin/nimlaunch-x11`.
Ensure your system provides the `libX11` and `libXft` shared libraries. Icon
enabled binaries additionally need `libImlib2`. Wayland sessions require
XWayland.

### Build from source

```bash
git clone https://github.com/DrunkenAlcoholic/NimLaunch-X11.git
cd NimLaunch-X11
nimble install --depsOnly # optional: install dependencies declared in the nimble file
nimble release           # produces ./bin/nimlaunch-x11
./bin/nimlaunch-x11
```

Dependencies:

- **Nim toolchain** – install via [choosenim](https://nim-lang.org/install_unix.html)
  or your package manager.
- **Runtime libraries** – `libX11` and `libXft` for all builds; `Imlib2` only
  for icon-enabled binaries.
- **Development headers** – `libx11` and `libxft` headers for compiling; add
  Imlib2 headers for icon builds.
- **Nim packages** – already covered by `nimble install` above (`parsetoml`, `x11`).

Common package names:

| Distro | Default build deps | Icon build extra | Runtime |
| ------ | ------------------ | ---------------- | ------- |
| Solus | `libx11-devel libxft-devel` | `imlib2-devel` | `libx11 libxft-devel imlib2` for icon builds |
| Debian/Ubuntu | `libx11-dev libxft-dev` | `libimlib2-dev` | `libx11-6 libxft2 libimlib2` for icon builds |
| Arch/Manjaro | `libx11 libxft` | `imlib2` | same packages provide runtime libraries |
| Fedora | `libX11-devel libXft-devel` | `imlib2-devel` | `libX11 libXft imlib2` for icon builds |

On Solus, `libxft-devel` is currently listed as a runtime requirement because
the Nim `x11` package dynamically opens `libXft.so`; Solus provides that
unversioned loader symlink in `libxft-devel`, while `libxft` only provides
`libXft.so.2`.

Command-line flag:

- `--bench` – prints millisecond startup timings and exits.

---

## Quick Reference

Every query updates the result list in real time. These shortcuts cover the
core workflow:

| Trigger | Context | Effect |
| ------- | ------- | ------ |
| Type text | Normal | Fuzzy-search applications; top hit updates instantly |
| Enter | Normal or command bar | Launch the highlighted entry immediately |
| Esc | Command bar | Close the bar, keep the narrowed results selected |
| Esc | Normal | Exit NimLaunch |
| ↑ / ↓ / PgUp / PgDn / Home / End | Any | Navigate the results list |
| `/` | Normal | Toggle the command bar (restores previous `/` search) |
| `:` / `!` | Normal | Open the bar primed for a prefix or `!` command |
| Ctrl+U | Command bar | Clear the current query |
| Ctrl+H / Backspace | Command bar | Delete one character (closes the bar when empty) |

### Built-in prefixes

| Prefix | Example | Description |
| ------ | ------- | ----------- |
| *none* | `fire` | Regular app search; rankings favour prefixes and recent launches |
| `:t` | `:t nord` | Browse themes; Up/Down preview, Enter to keep selection |
| `:s` | `:s notes` | Search files (`fd` → `locate` → bounded `$HOME` walk) |
| `:c` | `:c sway` | Match files inside `~/.config` and open with the default handler |
| `:r` | `:r htop` | Run a shell command inside your preferred terminal |
| `!` | `!htop` | Shorthand for `:r` without the colon |
| `:p` | `:p lock` | Show configured power/system actions (label filter) |

`:s` results render as `filename — /path/to/dir` and open with the system
handler. Power actions can either spawn in the background or run inside your
configured terminal depending on their `mode`.

### Vim mode

Enable by setting `[input].vim_mode = true` in `~/.config/nimlaunch/nimlaunch.toml`.
Vim mode adds:

| Trigger | Effect |
| ------- | ------ |
| `h` / `j` / `k` / `l` | Move cursor left/down/up/right (acts on the result list) |
| `gg` / `Shift+G` | Jump to top / bottom of the list |
| `/` | Toggle the command bar; reopening restores the last slash search |
| `:` / `!` | Open the command bar primed for colon or bang commands |
| `Enter` | Launch the highlighted entry immediately |
| `Esc` | Leave command mode but keep the current filtered results |
| `:q` (then Enter) | Quit NimLaunch from the command bar |
| `Ctrl+H` | Delete one character (when empty, closes the bar) |
| `Ctrl+U` | Clear the entire command |

---

## Configuration

The config lives at `~/.config/nimlaunch/nimlaunch.toml`. It is auto-generated
on first run, shipping with sensible defaults and a long list of themes.

```toml
[window]
width = 500
max_visible_items = 10
center = true
vertical_align = "one-third"

[font]
fontname = "Noto Sans:size=12"

[input]
prompt   = "> "
cursor   = "_"
vim_mode = false

[terminal]
program = "kitty"

[border]
width = 2

[[shortcuts]]
prefix = ":g"            # write "g", ":g", or "g:" — all map to :g in the UI
label  = "Search Google: "
base   = "https://www.google.com/search?q={query}"
mode   = "url"            # other options: "shell", "file"

[power]
prefix = ":p"            # write with or without ':'; the UI trigger remains :p

[[power_actions]]
label   = "Shutdown"
command = "systemctl poweroff"
mode    = "spawn"         # or "terminal"
stay_open = false

[[themes]]
name                = "Nord"
bgColorHex          = "#2E3440"
fgColorHex          = "#D8DEE9"
highlightBgColorHex = "#88C0D0"
highlightFgColorHex = "#2E3440"
borderColorHex      = "#4C566A"
matchFgColorHex     = "#f8c291"

[theme]
last_chosen = "Nord"
```

Shortcut and power prefixes are stored case-insensitively without leading/trailing
colons, so feel free to write `g:`, `:g`, or just `g`. At runtime you still press
`:` followed by the keyword (for example `:g search terms`).

### Custom shortcuts

Add more `[[shortcuts]]` blocks:

```toml
[[shortcuts]]
prefix = "yt:"
label  = "Search YouTube: "
base   = "https://www.youtube.com/results?search_query={query}"

[[shortcuts]]
prefix = "rg"
label  = "grep repo: "
base   = "cd ~/code && rg {query}"
mode   = "shell"

[[shortcuts]]
prefix = ":note"
label  = "Open note: "
base   = "~/notes/{query}.md"
mode   = "file"
```

`mode = "shell"` quotes the query for a shell command, while `mode = "file"`
expands `~` and launches the path with your default handler. If the file is
missing, NimLaunch stays open so you can adjust the query.

### Power actions

`[[power_actions]]` entries expose shutdown/reboot/lock/etc. commands behind a
keyword (default `:p`). Each action supports:

- `label` – text shown in the list.
- `command` – shell command executed via `/bin/sh -c`.
- `mode` – `spawn` (background) or `terminal` (run inside the configured terminal).
- `stay_open` – keep NimLaunch open after execution.

Set `[power].prefix = "x"` (or clear it) to change or disable the trigger.

---

## File discovery & caching

NimLaunch indexes `.desktop` files from:

1. `~/.local/share/applications`
2. `~/.local/share/flatpak/exports/share/applications`
3. `/usr/share/applications`
4. `/var/lib/flatpak/exports/share/applications`

Metadata is cached at `~/.cache/nimlaunch/apps.json`. The cache is invalidated
automatically when source directories change. Entries flagged as `NoDisplay=true`,
`Terminal=true`, or belonging solely to the `Settings` / `System` categories are
skipped so the list remains focused on launchable apps. Entries with `TryExec`
are also skipped when the referenced executable is unavailable.

NimLaunch also reads `.desktop` action sections. When an application declares
actions such as `New Window`, those appear in normal search as `Application:
New Window` and launch the action's own `Exec` command.

Icon names from `.desktop` files are stored in the app cache. The lightweight
resolver checks `~/.local/share/icons`, `~/.icons`, `$XDG_DATA_DIRS/icons`, and
`$XDG_DATA_DIRS/pixmaps` for PNG, XPM, or SVG files, preferring small app icon
sizes.

Real icon rendering is optional and uses Imlib2. Default builds remain text-only
and do not link to Imlib2. To enable icons, install the Imlib2 development
package and build with:

```bash
nimble debugIcons
# or
nimble releaseIcons
```

Icon-enabled builds produce `./bin/nimlaunch-x11-icons`.

When distributing an icon-enabled binary, users only need the runtime Imlib2
package. The `*-devel` package is only needed on the machine compiling
NimLaunch-X11.

Recent launches are tracked in `~/.cache/nimlaunch/recent.json`, ensuring the
empty-query view always surfaces the last applications you opened.

---

## Themes

- `:t` shows the theme list; move with Up/Down to preview instantly and press Enter to keep the selection.
  Leaving `:t` without pressing Enter restores the theme you started with.
- Add or edit `[[themes]]` blocks in the TOML to create your own colour schemes.

Popular presets include Nord, Catppuccin (all flavours), Ayu, Dracula, Gruvbox,
Solarized, Tokyo Night, Monokai, Palenight, and more.

---

## License

MIT © 2025 DrunkenAlcoholic. Enjoy launching at ludicrous speed. 🚀
