# NimLaunch Configuration Guide

NimLaunch is highly configurable via a TOML file. By default, this file is generated at `~/.config/nimlaunch/nimlaunch.toml` upon your first launch.

This guide walks you through the different sections of the configuration file.

## `[window]`
Controls the size, position, and layout of the launcher window.
```toml
[window]
width = 500               # Total width in pixels
max_visible_items = 10    # Maximum number of search results to display
center = true             # If true, ignores position_x/position_y and centers horizontally
position_x = 20           # X coordinate offset
position_y = 50           # Y coordinate offset
vertical_align = "one-third" # Vertical alignment ("center", "top", "bottom", "one-third")
```

## `[input]`
Controls the prompt and input mode.
```toml
[input]
prompt = "> "
cursor = "_"
vim_mode = false          # Enable Vim-like keybindings (j, k, gg, G)
```

## `[font]`
Set the UI font using Xft font strings.
```toml
[font]
fontname = "Noto Sans:size=12"
```

## `[terminal]`
Specify which terminal emulator NimLaunch should use when executing commands or running terminal-based tools.
```toml
[terminal]
program = "gnome-terminal"
```

## `[border]`
Window border thickness. Set to 0 to disable borders.
```toml
[border]
width = 2
```

## `[[themes]]`
You can define multiple themes in the configuration file. The active theme is saved automatically when you use the `:t` command inside the launcher to select one.

```toml
[[themes]]
name                = "MyCustomTheme"   
bgColorHex          = "#1E1E2E"
fgColorHex          = "#CDD6F4"
highlightBgColorHex = "#313244"
highlightFgColorHex = "#89B4FA"
borderColorHex      = "#F38BA8"
matchFgColorHex     = "#A6E3A1"
```
