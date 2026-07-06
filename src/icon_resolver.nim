## icon_resolver.nim — freedesktop icon lookup without image decoding.
## MIT; see LICENSE for details.
##
## This module only resolves an Icon= value to an existing icon file path. It
## deliberately does not decode or draw image data, so it adds no dependencies.

import std/[algorithm, os, sets, strutils, tables]

const
  IconExts = [".png", ".xpm", ".svg"]
  FallbackIconThemes = ["papirus", "papirus-dark", "adwaita", "adwaita-dark",
                        "breeze", "breeze-dark", "hicolor"]

var preferredIconThemes: seq[string] = @[]

type
  IconCandidate = object
    path: string
    score: int

  IconIndex* = Table[string, seq[string]]

proc hasIconExt(path: string): bool =
  let lower = path.toLowerAscii()
  for ext in IconExts:
    if lower.endsWith(ext):
      return true
  false

proc appendUniqueTheme(dst: var seq[string]; themeName: string) =
  let cleaned = themeName.strip(chars = {' ', '\t', '\'', '"'}).toLowerAscii
  if cleaned.len > 0 and cleaned notin dst:
    dst.add cleaned

proc detectThemeFromGtkSettings(): string =
  let cfgHome = getEnv("XDG_CONFIG_HOME", getHomeDir() / ".config")
  for iniPath in [cfgHome / "gtk-4.0" / "settings.ini",
                  cfgHome / "gtk-3.0" / "settings.ini"]:
    if not fileExists(iniPath):
      continue
    try:
      for rawLine in lines(iniPath):
        let line = rawLine.strip()
        if line.len == 0 or line.startsWith("#") or line.startsWith(";"):
          continue
        let lower = line.toLowerAscii()
        if not lower.startsWith("gtk-icon-theme-name"):
          continue
        let eq = line.find('=')
        if eq >= 0:
          return line[eq + 1 .. ^1].strip(chars = {' ', '\t', '\'', '"'})
    except CatchableError:
      discard
  ""

proc initPreferredIconThemes() =
  if preferredIconThemes.len > 0:
    return
  for theme in [getEnv("ICON_THEME"), detectThemeFromGtkSettings()]:
    if theme.len == 0:
      continue
    preferredIconThemes.appendUniqueTheme(theme)
    let lower = theme.toLowerAscii()
    if lower.endsWith("-dark"):
      preferredIconThemes.appendUniqueTheme(theme[0 ..< theme.len - 5])
    else:
      preferredIconThemes.appendUniqueTheme(theme & "-dark")
  for theme in FallbackIconThemes:
    preferredIconThemes.appendUniqueTheme(theme)

proc candidateNames(icon: string): seq[string] =
  ## Return filename candidates for an Icon= value.
  let base = icon.extractFilename()
  if base.len == 0:
    return
  if hasIconExt(base):
    result.add base
  else:
    for ext in IconExts:
      result.add base & ext

proc iconKey(path: string): string =
  ## Normalise a concrete icon filename to the Icon= key used for lookup.
  result = path.extractFilename()
  let lower = result.toLowerAscii()
  for ext in IconExts:
    if lower.endsWith(ext):
      result.setLen(result.len - ext.len)
      break

proc parseSizeHint(path: string; preferredSize: int): int =
  ## Lower is better. Recognises common theme paths like /24x24/apps/foo.png.
  const NoSizeHintPenalty = 10_000
  var best = NoSizeHintPenalty
  for part in path.split(DirSep):
    let x = part.find('x')
    if x <= 0 or x >= part.high:
      continue
    let left = part[0 ..< x]
    var rightEnd = x + 1
    while rightEnd < part.len and part[rightEnd].isDigit:
      inc rightEnd
    let right = part[x + 1 ..< rightEnd]
    if left.len == 0 or right.len == 0:
      continue
    try:
      let w = parseInt(left)
      let h = parseInt(right)
      if w > 0 and h > 0:
        best = min(best, abs(w - preferredSize) + abs(h - preferredSize))
    except ValueError:
      discard
  best

proc extensionScore(path: string): int =
  let lower = path.toLowerAscii()
  if lower.endsWith(".png"): return 0
  if lower.endsWith(".xpm"): return 20
  if lower.endsWith(".svg"): return 40
  80

proc themeScore(path: string): int =
  initPreferredIconThemes()
  let parts = path.split(DirSep)
  var best = 200
  for part in parts:
    let name = part.toLowerAscii()
    for i, pref in preferredIconThemes:
      if name == pref:
        best = min(best, i * 10)
      elif name.startsWith(pref & "-"):
        best = min(best, i * 10 + 3)
    if name.contains("legacy"):
      best = max(best, 800)
    if name.contains("highcontrast"):
      best = max(best, 900)
  best

proc scoreCandidate(path: string; preferredSize: int): int =
  let lower = path.toLowerAscii()
  result = parseSizeHint(path, preferredSize) * 10 +
           extensionScore(path) +
           themeScore(path) * 5
  if lower.contains(DirSep & "apps" & DirSep):
    result -= 8
  if lower.contains(DirSep & "hicolor" & DirSep):
    result -= 4
  if lower.contains(DirSep & "scalable" & DirSep):
    result += 16

proc defaultIconRoots*(): seq[string] =
  ## Return standard icon roots plus /pixmaps fallback directories.
  var seen = initHashSet[string]()

  proc addRoot(roots: var seq[string]; path: string) =
    let expanded = path.expandTilde()
    if expanded.len > 0 and dirExists(expanded) and not seen.contains(expanded):
      seen.incl expanded
      roots.add expanded

  let dataHome = getEnv("XDG_DATA_HOME", getHomeDir() / ".local/share")
  result.addRoot(dataHome / "icons")
  result.addRoot(getHomeDir() / ".icons")
  result.addRoot(getHomeDir() / ".local/share/flatpak/exports/share/icons")
  result.addRoot(getHomeDir() / ".local/share/flatpak/exports/share/pixmaps")

  let dataDirs = getEnv("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
  for dir in dataDirs.split(':'):
    if dir.len == 0:
      continue
    result.addRoot(dir / "icons")
    result.addRoot(dir / "pixmaps")
  result.addRoot("/var/lib/flatpak/exports/share/icons")
  result.addRoot("/var/lib/flatpak/exports/share/pixmaps")

proc buildIconIndex*(roots: openArray[string]): IconIndex =
  ## Index icon roots once so UI rebuilds do not recursively scan per row.
  result = initTable[string, seq[string]]()
  for root in roots:
    if not dirExists(root):
      continue
    for path in walkDirRec(root, yieldFilter = {pcFile}):
      if not hasIconExt(path):
        continue
      let key = iconKey(path)
      if key.len == 0:
        continue
      result.mgetOrPut(key, @[]).add path

proc bestIconPath(paths: openArray[string]; preferredSize: int): string =
  var matches: seq[IconCandidate] = @[]
  for path in paths:
    if fileExists(path):
      matches.add IconCandidate(path: path,
                                score: scoreCandidate(path, preferredSize))
  if matches.len == 0:
    return ""
  matches.sort(proc(a, b: IconCandidate): int =
    result = cmp(a.score, b.score)
    if result == 0: result = cmp(a.path.len, b.path.len)
    if result == 0: result = cmp(a.path, b.path)
  )
  matches[0].path

proc resolveIconInIndex*(icon: string; index: IconIndex;
                         preferredSize = 24): string =
  ## Resolve Icon= from a prebuilt icon index.
  let trimmed = icon.strip()
  if trimmed.len == 0:
    return ""

  let expanded = trimmed.expandTilde()
  if expanded.isAbsolute() or expanded.contains(DirSep):
    if fileExists(expanded):
      return expanded
    if not hasIconExt(expanded):
      for ext in IconExts:
        if fileExists(expanded & ext):
          return expanded & ext
    return ""

  let key = iconKey(trimmed)
  if index.hasKey(key):
    return bestIconPath(index[key], preferredSize)
  ""

proc resolveIconInRoots*(icon: string; roots: openArray[string];
                         preferredSize = 24): string =
  ## Resolve Icon= in explicit roots. Returns "" when no matching file exists.
  let trimmed = icon.strip()
  if trimmed.len == 0:
    return ""

  let expanded = trimmed.expandTilde()
  if expanded.isAbsolute() or expanded.contains(DirSep):
    if fileExists(expanded):
      return expanded
    if not hasIconExt(expanded):
      for ext in IconExts:
        if fileExists(expanded & ext):
          return expanded & ext
    return ""

  let names = candidateNames(trimmed).toHashSet()
  var matches: seq[string] = @[]

  for root in roots:
    if not dirExists(root):
      continue
    for path in walkDirRec(root, yieldFilter = {pcFile}):
      if names.contains(path.extractFilename()):
        matches.add path

  bestIconPath(matches, preferredSize)

proc resolveIcon*(icon: string; preferredSize = 24): string =
  ## Resolve Icon= using standard freedesktop icon locations.
  resolveIconInRoots(icon, defaultIconRoots(), preferredSize)
