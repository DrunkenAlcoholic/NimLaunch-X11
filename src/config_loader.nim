## config.nim — TOML loading, theming, and configuration application
import std/[os, strutils]
import parsetoml as toml
import state, utils, gui

var baseMatchFgColorHex*: string = ""

proc applyTheme*(cfg: var Config; name: string) =
  ## Set theme fields from `themeList` by name; respect explicit match color.
  let fallbackMatch = if baseMatchFgColorHex.len > 0:
    baseMatchFgColorHex
  else:
    cfg.matchFgColorHex
  for i, th in themeList:
    if th.name.toLowerAscii == name.toLowerAscii:
      cfg.bgColorHex = th.bgColorHex
      cfg.fgColorHex = th.fgColorHex
      cfg.highlightBgColorHex = th.highlightBgColorHex
      cfg.highlightFgColorHex = th.highlightFgColorHex
      cfg.borderColorHex = th.borderColorHex
      if th.matchFgColorHex.len > 0:
        cfg.matchFgColorHex = th.matchFgColorHex
      else:
        cfg.matchFgColorHex = fallbackMatch
      cfg.themeName = th.name
      currentThemeIndex = i
      break

proc updateParsedColors*(cfg: var Config) =
  ## Resolve hex → pixel colours used by Xft/Xlib.
  cfg.bgColor = parseColor(cfg.bgColorHex)
  cfg.fgColor = parseColor(cfg.fgColorHex)
  cfg.highlightBgColor = parseColor(cfg.highlightBgColorHex)
  cfg.highlightFgColor = parseColor(cfg.highlightFgColorHex)
  cfg.borderColor = parseColor(cfg.borderColorHex)

proc applyThemeAndColors*(cfg: var Config; name: string; doNotify = true) =
  ## Apply theme, resolve colors, push to GUI, and optionally redraw.
  applyTheme(cfg, name)
  updateParsedColors(cfg)
  gui.updateGuiColors()
  if doNotify:
    gui.notifyThemeChanged(name)
    gui.redrawWindow()

proc saveLastTheme*(cfgPath: string) =
  ## Update or insert [theme].last_chosen = "<name>" in the TOML file.
  var lines = readFile(cfgPath).splitLines()
  var inTheme = false
  var updated = false
  var themeSectionFound = false
  for i in 0..<lines.len:
    let l = lines[i].strip()
    if l == "[theme]":
      inTheme = true
      themeSectionFound = true
      continue
    if inTheme:
      if l.startsWith("[") and l.endsWith("]"):
        lines.insert("last_chosen = \"" & config.themeName & "\"", i)
        updated = true
        inTheme = false
        break
      if l.startsWith("last_chosen"):
        lines[i] = "last_chosen = \"" & config.themeName & "\""
        updated = true
        inTheme = false
        break
  if inTheme and not updated:
    lines.add("last_chosen = \"" & config.themeName & "\"")
    updated = true
  if not themeSectionFound:
    lines.add("")
    lines.add("[theme]")
    lines.add("last_chosen = \"" & config.themeName & "\"")
    updated = true
  if updated:
    writeFile(cfgPath, lines.join("\n"))

proc loadShortcutsSection*(tbl: toml.TomlValueRef; cfgPath: string) =
  ## Populate `state.shortcuts` from `[[shortcuts]]` entries in *tbl*.
  shortcuts = @[]
  if not tbl.hasKey("shortcuts"): return

  try:
    for scVal in tbl["shortcuts"].getElems():
      let scTbl = scVal.getTable()
      let prefixRaw = scTbl.getOrDefault("prefix").getStr("")
      let prefix = normalizePrefix(prefixRaw)
      let base = scTbl.getOrDefault("base").getStr("").strip()
      if prefix.len == 0 or base.len == 0:
        continue

      let label = scTbl.getOrDefault("label").getStr("").strip(chars = {'\t', '\r', '\n'})
      let modeStr = scTbl.getOrDefault("mode").getStr("url").toLowerAscii

      var mode = smUrl
      case modeStr
      of "shell": mode = smShell
      of "file": mode = smFile
      else: discard

      shortcuts.add Shortcut(prefix: prefix, label: label, base: base, mode: mode)
  except CatchableError:
    echo "NimLaunch warning: ignoring invalid [[shortcuts]] entries in ", cfgPath

proc loadMenusSection*(tbl: toml.TomlValueRef; cfgPath: string) =
  menus = @[]
  if not tbl.hasKey("menus"): return

  try:
    for mVal in tbl["menus"].getElems():
      let mTbl = mVal.getTable()
      let rawPrefix = mTbl.getOrDefault("prefix").getStr("").strip()
      let name = mTbl.getOrDefault("name").getStr("").strip()
      if rawPrefix.len == 0: continue

      var items: seq[MenuItem] = @[]
      if mTbl.hasKey("items"):
        for iVal in mTbl["items"].getElems():
          let iTbl = iVal.getTable()
          let label = iTbl.getOrDefault("label").getStr("").strip()
          let command = iTbl.getOrDefault("command").getStr("").strip()
          if label.len == 0 or command.len == 0: continue

          var mode = mamSpawn
          let modeStr = iTbl.getOrDefault("mode").getStr("spawn").strip().toLowerAscii
          case modeStr
          of "terminal": mode = mamTerminal
          else: discard
          let stayOpen = iTbl.getOrDefault("stay_open").getBool(false)
          items.add MenuItem(label: label, command: command, mode: mode, stayOpen: stayOpen)

      menus.add Menu(prefix: normalizePrefix(rawPrefix), name: name, items: items)
  except CatchableError:
    echo "NimLaunch warning: ignoring invalid [[menus]] entries in ", cfgPath

proc initLauncherConfig*() =
  ## Initialize defaults, read TOML, apply last theme, compute geometry.
  config = Config() # zero-init

  ## In-code defaults
  config.winWidth = 500
  config.lineHeight = 22
  config.maxVisibleItems = 10
  config.centerWindow = true
  config.positionX = 20
  config.positionY = 50
  config.verticalAlign = "one-third"
  config.fontName = "Noto Sans:size=12"
  config.prompt = "> "
  config.cursor = "_"
  config.terminalExe = "gnome-terminal"
  config.borderWidth = 2
  config.matchFgColorHex = "#f8c291"
  config.vimMode = false

  ## Ensure TOML exists
  let cfgDir = getHomeDir() / ".config" / "nimlaunch"
  let cfgPath = cfgDir / "nimlaunch.toml"
  if not fileExists(cfgPath):
    createDir(cfgDir)
    writeFile(cfgPath, defaultToml)
    echo "Created default config at ", cfgPath

  ## Parse TOML
  let tbl = toml.parseFile(cfgPath)

  ## window
  if tbl.hasKey("window"):
    try:
      let w = tbl["window"].getTable()
      config.winWidth = w.getOrDefault("width").getInt(config.winWidth)
      config.maxVisibleItems = w.getOrDefault("max_visible_items").getInt(config.maxVisibleItems)
      config.centerWindow = w.getOrDefault("center").getBool(config.centerWindow)
      config.positionX = w.getOrDefault("position_x").getInt(config.positionX)
      config.positionY = w.getOrDefault("position_y").getInt(config.positionY)
      config.verticalAlign = w.getOrDefault("vertical_align").getStr(config.verticalAlign)
    except CatchableError:
      echo "NimLaunch warning: ignoring invalid [window] section in ", cfgPath

  ## font
  if tbl.hasKey("font"):
    try:
      let f = tbl["font"].getTable()
      config.fontName = f.getOrDefault("fontname").getStr(config.fontName)
    except CatchableError:
      echo "NimLaunch warning: ignoring invalid [font] section in ", cfgPath

  ## input
  if tbl.hasKey("input"):
    try:
      let inp = tbl["input"].getTable()
      config.prompt = inp.getOrDefault("prompt").getStr(config.prompt)
      config.cursor = inp.getOrDefault("cursor").getStr(config.cursor)
      config.vimMode = inp.getOrDefault("vim_mode").getBool(config.vimMode)
    except CatchableError:
      echo "NimLaunch warning: ignoring invalid [input] section in ", cfgPath

  ## terminal
  if tbl.hasKey("terminal"):
    try:
      let term = tbl["terminal"].getTable()
      config.terminalExe = term.getOrDefault("program").getStr(config.terminalExe)
    except CatchableError:
      echo "NimLaunch warning: ignoring invalid [terminal] section in ", cfgPath

  ## border
  if tbl.hasKey("border"):
    try:
      let b = tbl["border"].getTable()
      config.borderWidth = b.getOrDefault("width").getInt(config.borderWidth)
    except CatchableError:
      echo "NimLaunch warning: ignoring invalid [border] section in ", cfgPath

  ## themes
  themeList = @[]
  if tbl.hasKey("themes"):
    try:
      for thVal in tbl["themes"].getElems():
        let th = thVal.getTable()
        themeList.add Theme(
          name: th.getOrDefault("name").getStr(""),
          bgColorHex: th.getOrDefault("bgColorHex").getStr(""),
          fgColorHex: th.getOrDefault("fgColorHex").getStr(""),
          highlightBgColorHex: th.getOrDefault("highlightBgColorHex").getStr(""),
          highlightFgColorHex: th.getOrDefault("highlightFgColorHex").getStr(""),
          borderColorHex: th.getOrDefault("borderColorHex").getStr(""),
          matchFgColorHex: th.getOrDefault("matchFgColorHex").getStr("")
        )
    except CatchableError:
      echo "NimLaunch warning: ignoring invalid [[themes]] entries in ", cfgPath

  loadShortcutsSection(tbl, cfgPath)
  loadMenusSection(tbl, cfgPath)

  ## last_chosen (case-insensitive match; fallback to first theme)
  var lastName = ""
  if tbl.hasKey("theme"):
    try:
      let themeTbl = tbl["theme"].getTable()
      lastName = themeTbl.getOrDefault("last_chosen").getStr("")
    except CatchableError:
      echo "NimLaunch warning: ignoring invalid [theme] section in ", cfgPath
  var pickedIndex = -1
  if lastName.len > 0:
    for i, th in themeList:
      if th.name.toLowerAscii == lastName.toLowerAscii:
        pickedIndex = i
        break
  if pickedIndex < 0:
    if themeList.len > 0: pickedIndex = 0
    else: quit("NimLaunch error: no themes defined in nimlaunch.toml")

  let chosen = themeList[pickedIndex].name
  config.themeName = chosen
  if baseMatchFgColorHex.len == 0:
    baseMatchFgColorHex = config.matchFgColorHex
  applyTheme(config, chosen)
  if chosen != lastName:
    saveLastTheme(cfgPath)

  ## guard rails for config values that affect layout/search limits
  if config.maxVisibleItems < 1:
    config.maxVisibleItems = 1

  ## derived geometry
  config.winMaxHeight = 40 + config.maxVisibleItems * config.lineHeight
