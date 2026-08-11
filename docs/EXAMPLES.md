# NimLaunch Advanced Features & Examples

NimLaunch isn't just a simple application launcher. With Shortcuts, Menus, and `dmenu` mode, you can build a highly customized productivity environment.

---

## 1. Custom Menus (`[[menus]]`)
Menus allow you to group static commands under a specific prefix. When you type the prefix (e.g., `:p`), the launcher will display the list of choices. If you continue typing, it will fuzzy-search within that menu.

### Example: System Power Menu
```toml
[[menus]]
prefix = ":p"
name = "Power Options"

  [[menus.items]]
  label   = "Shutdown"
  command = "systemctl poweroff"
  mode    = "spawn" # runs in the background

  [[menus.items]]
  label   = "Reboot"
  command = "systemctl reboot"
  mode    = "spawn"
```

### Example: Development Tools
```toml
[[menus]]
prefix = ":dev"
name = "Development"

  [[menus.items]]
  label   = "System Monitor (htop)"
  command = "htop"
  mode    = "terminal" # Opens inside your configured terminal emulator

  [[menus.items]]
  label   = "Docker Desktop"
  command = "systemctl --user start docker-desktop"
  mode    = "spawn"
```

---

## 2. Dynamic Shortcuts (`[[shortcuts]]`)
Shortcuts allow you to inject search queries directly into commands, URLs, or scripts. The `{query}` placeholder gets replaced by whatever you type after the prefix.

### Example: Web Searches
```toml
[[shortcuts]]
prefix = ":g"
label  = "Search Google: "
base   = "https://www.google.com/search?q={query}"
mode   = "url"

[[shortcuts]]
prefix = ":wiki"
label  = "Search Wikipedia: "
base   = "https://en.wikipedia.org/wiki/Special:Search?search={query}"
mode   = "url"
```

### Example: Custom Shell Scripts
Pass arguments to a bash script and keep the terminal open to see the result:
```toml
[[shortcuts]]
prefix = ":ping"
label  = "Ping Domain: "
base   = "ping {query}"
mode   = "shell"
```

---

## 3. Scripting with `--dmenu` Mode
NimLaunch can replace `dmenu` or `rofi` in your shell scripts! By passing the `--dmenu` (or `-dmenu`) flag, NimLaunch bypasses your Desktop application cache and instead reads lines directly from standard input (`stdin`). 

It will present these lines in its beautifully themed UI, allow the user to fuzzy-find, and then echo the exact selected line to `stdout`.

### Basic Usage
```bash
# Pick a file from the current directory and open it
ls -1 | nimlaunch-x11 --dmenu | xargs xdg-open
```

### Advanced Example: Audio Output Selector
You can use `dmenu` mode to build a graphical audio switcher for PulseAudio. Create a shell script (or bind it to a keyboard shortcut):
```bash
#!/bin/bash
# Fetch audio sinks, let user pick via NimLaunch, then set it as default
pactl list short sinks | awk '{print $2}' | nimlaunch-x11 --dmenu | xargs -I {} pactl set-default-sink {}
```

### Combining Menus with Screenshots
Custom menus are great for categorizing tools like screenshot utilities. (Note: The following examples use `maim` and `xclip` since this is the X11 version of NimLaunch):

```toml
[[menus]]
prefix = ":sc"
name = "Screenshot Tools"

  [[menus.items]]
  label   = "Capture Full Screen"
  command = "maim ~/Pictures/screenshot_$(date +%s).png"
  mode    = "spawn"

  [[menus.items]]
  label   = "Capture Selection to Clipboard"
  command = "maim -s | xclip -selection clipboard -t image/png"
  mode    = "spawn"
```
