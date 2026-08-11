import std/[os, osproc, strutils, algorithm, heapqueue, sets, uri, tables, streams]
import state, utils, config_loader, parser, gui
when defined(icons):
  import icon_resolver

proc recentBoost*(name: string): int =
  let idx = recentApps.find(name)
  if idx >= 0: return max(0, 200 - idx * 40)
  0

proc scanFilesFast*(query: string): seq[string] =
  let home  = getHomeDir()
  let ql    = query.toLowerAscii
  let limit = SearchFdCap

  try:
    let fdExe = findExe("fd")
    if fdExe.len > 0:
      let args = @[
        "-i", "--type", "f", "--absolute-path",
        "--color", "never",
        "--max-results", $limit,
        "--fixed-strings",
        query, home
      ]
      let p = startProcess(fdExe, args = args, options = {poUsePath, poStdErrToStdOut})
      defer: close(p)
      let output = p.outputStream.readAll()
      for line in output.splitLines():
        if line.len > 0: result.add(line)
      return

    let locExe = findExe("locate")
    if locExe.len > 0:
      let p = startProcess(locExe, args = @["-i", "-l", $limit, query],
                           options = {poUsePath, poStdErrToStdOut})
      defer: close(p)
      let output = p.outputStream.readAll()
      for line in output.splitLines():
        if line.len > 0: result.add(line)
      return

    var count = 0
    for path in walkDirRec(home, yieldFilter = {pcFile}):
      if path.toLowerAscii.contains(ql):
        result.add(path)
        inc count
        if count >= limit: break

  except CatchableError as e:
    echo "scanFilesFast warning: ", e.name, ": ", e.msg

proc takePrefix*(input, pfx: string; rest: var string): bool =
  let n = pfx.len
  if input.len >= n and input[0..n-1] == pfx:
    if input.len == n:
      rest = ""; return true
    if input.len > n:
      if input[n] == ' ':
        rest = input[n+1 .. ^1].strip(); return true
      rest = input[n .. ^1].strip(); return true
  false

proc subseqPositions*(q, t: string): seq[int] =
  if q.len == 0: return @[]
  let lq = q.toLowerAscii
  let lt = t.toLowerAscii
  var qi = 0
  for i in 0 ..< lt.len:
    if qi < lq.len and lt[i] == lq[qi]:
      result.add i
      inc qi
      if qi == lq.len: return
  result.setLen(0)

proc subseqSpans*(q, t: string): seq[(int, int)] =
  for p in subseqPositions(q, t): result.add (p, 1)

proc isWordBoundary*(lt: string; idx: int): bool =
  if idx <= 0: return true
  let c = lt[idx-1]
  c == ' ' or c == '-' or c == '_' or c == '.' or c == '/'

proc scoreMatch*(q, t, fullPath, home: string): int =
  if q.len == 0: return -1_000_000
  let lq = q.toLowerAscii
  let lt = t.toLowerAscii
  let pos = lt.find(lq)

  proc withinOneEdit(a, b: string): bool =
    let m = a.len; let n = b.len
    if abs(m - n) > 1: return false
    var i = 0; var j = 0; var edits = 0
    while i < m and j < n:
      if a[i] == b[j]: inc i; inc j
      else:
        inc edits; if edits > 1: return false
        if m == n: inc i; inc j
        elif m < n: inc j
        else: inc i
    edits += (m - i) + (n - j)
    edits <= 1

  proc withinOneTransposition(a, b: string): bool =
    if a.len != b.len or a.len < 2: return false
    var k = 0
    while k < a.len and a[k] == b[k]: inc k
    if k >= a.len - 1: return false
    if not (a[k] == b[k+1] and a[k+1] == b[k]): return false
    let tailStart = k + 2
    result = if tailStart < a.len:
      a[tailStart .. ^1] == b[tailStart .. ^1]
    else:
      true

  var s = -1_000_000
  if pos >= 0:
    s = 1000
    if pos == 0: s += 200
    if isWordBoundary(lt, pos): s += 80
    s += max(0, 60 - (t.len - q.len))

  if t == q: s += 9000
  elif lt == lq: s += 8600
  elif lt.startsWith(lq): s += 8200
  elif pos >= 0: s += 7800
  else:
    var typoHit = false
    if lq.len >= 2:
      let sizes = [max(1, lq.len - 1), lq.len, lq.len + 1]
      for L in sizes:
        if L > lt.len: continue
        var start = 0
        let maxStart = lt.len - L
        while start <= maxStart:
          let seg = lt[start ..< start + L]
          if withinOneEdit(lq, seg) or withinOneTransposition(lq, seg):
            typoHit = true
            var base = 7700
            if start == 0: base = 7950
            s = max(s, base - min(120, start))
            break
          inc start
        if typoHit: break
    if not typoHit and lq.len >= 2:
      if withinOneEdit(lq, lt) or withinOneTransposition(lq, lt):
        s = max(s, 7600)

  if fullPath.startsWith(home & "/"):
    if lt == lq: s += 600
    elif lt.startsWith(lq): s += 400
  s

proc parseCommand*(inputText: string): (CmdKind, string, int) =
  if inputText.len > 0 and inputText[0] == ':':
    var body = inputText[1 .. ^1]
    var rest = ""
    let sep = body.find({' ', '\t'})
    var keyword = body
    if sep >= 0:
      keyword = body[0 ..< sep]
      rest = body[sep + 1 .. ^1].strip()
    else:
      rest = ""
    let norm = normalizePrefix(keyword)
    case norm
    of "s": return (ckSearch, rest, -1)
    of "c": return (ckConfig, rest, -1)
    of "t": return (ckTheme, rest, -1)
    of "r": return (ckRun, rest, -1)
    else:
      for i, m in menus:
        if norm == m.prefix:
          return (ckMenu, rest, i)
      for i, sc in shortcuts:
        if norm == sc.prefix:
          return (ckShortcut, rest, i)
      return (ckNone, inputText, -1)

  var rest: string
  if takePrefix(inputText, "!", rest):
    return (ckRun, rest.strip(), -1)
  (ckNone, inputText, -1)

proc substituteQuery*(pattern, value: string): string =
  if pattern.contains("{query}"):
    result = pattern.replace("{query}", value)
  else:
    result = pattern & value

proc shortcutLabel*(sc: Shortcut; query: string): string =
  if sc.label.len == 0:
    return query
  if query.len == 0:
    return sc.label
  result = sc.label
  let last = sc.label[^1]
  if not last.isSpaceAscii():
    result.add ' '
  result.add query

proc shortcutExec*(sc: Shortcut; query: string): string =
  case sc.mode
  of smUrl:
    result = substituteQuery(sc.base, encodeUrl(query))
  of smShell:
    result = substituteQuery(sc.base, shellQuote(query))
  of smFile:
    result = substituteQuery(sc.base, query)

proc buildThemeActions*(rest: string; defaultIndex: var int): seq[Action] =
  defaultIndex = 0
  let ql = rest.toLowerAscii
  let currentThemeLower = config.themeName.toLowerAscii
  var idx = 0
  for th in themeList:
    if ql.len == 0 or th.name.toLowerAscii.contains(ql):
      result.add Action(kind: akTheme, label: th.name, exec: th.name)
      if th.name.toLowerAscii == currentThemeLower:
        defaultIndex = idx
      inc idx
  if result.len == 0:
    result.add Action(kind: akPlaceholder, label: "No matching themes", exec: "")

proc buildConfigActions*(rest: string): seq[Action] =
  ensureConfigFiles()
  let ql = rest.toLowerAscii
  for entry in configFilesCache:
    if ql.len == 0 or entry.name.toLowerAscii.contains(ql):
      result.add Action(kind: akConfig, label: entry.name, exec: entry.exec)
  if result.len == 0:
    result.add Action(kind: akPlaceholder, label: "No matches", exec: "")

proc buildShortcutActions*(rest: string; shortcutIdx: int): seq[Action] =
  if shortcutIdx < 0 or shortcutIdx >= shortcuts.len:
    return @[Action(kind: akPlaceholder, label: "Shortcut not found", exec: "")]
  let sc = shortcuts[shortcutIdx]
  @[Action(kind: akShortcut,
           label: shortcutLabel(sc, rest),
           exec: shortcutExec(sc, rest),
           shortcutMode: sc.mode)]

proc buildMenuActions*(idx: int, rest: string): seq[Action] =
  if menus.len <= idx: return @[]
  let menu = menus[idx]
  if menu.items.len == 0:
    return @[Action(kind: akPlaceholder,
                    label: "No items in menu: " & menu.name,
                    exec: "")]
  let ql = rest.strip().toLowerAscii
  for item in menu.items:
    if ql.len == 0 or item.label.toLowerAscii.contains(ql):
      result.add Action(kind: akMenuAction,
                        label: item.label,
                        exec: item.command,
                        menuMode: item.mode,
                        stayOpen: item.stayOpen)
  if result.len == 0:
    result.add Action(kind: akPlaceholder, label: "No matches", exec: "")

proc buildRunActions*(rest: string): seq[Action] =
  if rest.len == 0:
    return @[Action(kind: akPlaceholder, label: "Run: enter a command", exec: "")]
  @[Action(kind: akRun, label: "Run: " & rest, exec: rest)]

proc iconPathFor*(icon: string): string =
  when defined(icons):
    if icon.len == 0:
      return ""
    if iconPathCache.hasKey(icon):
      return iconPathCache[icon]
    result = resolveIconInIndex(icon, iconIndex, preferredSize = 24)
    iconPathCache[icon] = result
  else:
    ""

proc pickIcon*(app: DesktopApp): string =
  if app.icon.len > 0:
    return app.icon
  let base = parser.getBaseExec(app.exec).toLowerAscii
  if iconAliases.hasKey(base):
    return iconAliases[base]
  base

proc appIconPath*(app: DesktopApp): string =
  iconPathFor(pickIcon(app))

proc appActionIconPath*(app: DesktopApp; entryAction: DesktopEntryAction): string =
  if entryAction.icon.len > 0:
    result = iconPathFor(entryAction.icon)
  if result.len == 0:
    result = appIconPath(app)

proc buildSearchActions*(rest: string): seq[Action] =
  let sinceEdit = gui.nowMs() - lastInputChangeMs
  if rest.len < 2 or sinceEdit < SearchDebounceMs:
    return @[Action(kind: akPlaceholder, label: "Searching…", exec: "")]

  gui.notifyStatus("Searching…", 1200)
  let restLower = rest.toLowerAscii

  var paths: seq[string]
  if lastSearchQuery.len > 0 and rest.len >= lastSearchQuery.len and
     rest.startsWith(lastSearchQuery) and lastSearchResults.len > 0:
    for p in lastSearchResults:
      if p.toLowerAscii.contains(restLower):
        paths.add p
  else:
    paths = scanFilesFast(rest)

  lastSearchQuery = rest
  lastSearchResults = paths

  let maxScore = min(paths.len, SearchShowCap)
  proc pathDepth(s: string): int =
    var d = 0
    for ch in s:
      if ch == '/': inc d
    d

  let home = getHomeDir()
  var top = initHeapQueue[(int, string)]()
  let limit = config.maxVisibleItems
  let ql = restLower

  for idx in 0 ..< maxScore:
    let p = paths[idx]
    let name = p.extractFilename
    var s = scoreMatch(rest, name, p, home)
    let nl = name.toLowerAscii
    if nl == ql: s += 12_000
    elif nl.startsWith(ql): s += 4_000

    if p.startsWith(home & "/"):
      s += 800
      let dir = p[0 ..< max(0, p.len - name.len)]
      let relDepth = max(0, pathDepth(dir) - pathDepth(home))
      s -= min(relDepth, 10) * 200
      if dir == home or dir == (home & "/"):
        s += 5_000
        if name.len > 0 and name[0] == '.': s += 4_000
    else:
      s -= 2_000

    if s > -1_000_000:
      push(top, (s, p))
      if top.len > max(limit, 200): discard pop(top)

  var ranked: seq[(int, string)] = @[]
  while top.len > 0: ranked.add pop(top)
  ranked.sort(proc(a, b: (int, string)): int = cmp(b[0], a[0]))

  let showCap = max(limit, min(40, SearchShowCap))
  for i, it in ranked:
    if i >= showCap: break
    let p = it[1]
    let name = p.extractFilename
    var dir = p[0 ..< max(0, p.len - name.len)]
    while dir.len > 0 and dir[^1] == '/': dir.setLen(dir.len - 1)
    let pretty = name & " — " & shortenPath(dir)
    result.add Action(kind: akFile, label: pretty, exec: p)

  if result.len == 0:
    result.add Action(kind: akPlaceholder, label: "No matches", exec: "")

proc buildDefaultActions*(rest: string; defaultIndex: var int): seq[Action] =
  defaultIndex = 0
  if rest.len == 0:
    var seen = initHashSet[string]()
    for name in recentApps:
      if allAppsIndex.hasKey(name):
        let app = allAppsIndex[name]
        result.add Action(kind: akApp, label: app.name, exec: app.exec,
                          appData: app, iconPath: appIconPath(app))
        seen.incl name
    for app in allApps:
      if not seen.contains(app.name):
        result.add Action(kind: akApp, label: app.name, exec: app.exec,
                          appData: app, iconPath: appIconPath(app))
  else:
    type RankedAction = tuple[score: int; label: string; appIndex: int; actionIndex: int]
    var top = initHeapQueue[RankedAction]()
    let limit = config.maxVisibleItems
    for i, app in allApps:
      var s = scoreMatch(rest, app.name, app.name, "")
      for kw in app.keywords:
        s = max(s, scoreMatch(rest, kw, kw, "") - 100)
      if s > -1_000_000:
        push(top, (s + recentBoost(app.name), app.name, i, -1))
        if top.len > limit: discard pop(top)

      for actionIndex, entryAction in app.desktopActions:
        let label = app.name & ": " & entryAction.name
        var s = max(scoreMatch(rest, label, label, ""),
                    scoreMatch(rest, entryAction.name, label, ""))
        if s > -1_000_000:
          s += recentBoost(app.name)
          push(top, (s, label, i, actionIndex))
          if top.len > limit: discard pop(top)
    var ranked: seq[RankedAction] = @[]
    while top.len > 0: ranked.add pop(top)
    ranked.sort(proc(a, b: RankedAction): int =
      result = cmp(b.score, a.score)
      if result == 0: result = cmpIgnoreCase(a.label, b.label)
    )
    for item in ranked:
      let app = allApps[item.appIndex]
      if item.actionIndex < 0:
        result.add Action(kind: akApp, label: app.name, exec: app.exec,
                          appData: app, iconPath: appIconPath(app))
      else:
        let entryAction = app.desktopActions[item.actionIndex]
        result.add Action(kind: akAppAction,
                          label: item.label,
                          exec: entryAction.exec,
                          appData: app,
                          iconPath: appActionIconPath(app, entryAction))

  if result.len == 0:
    result.add Action(kind: akPlaceholder, label: "No applications found", exec: "")

proc beginThemePreviewSession*() =
  if not themePreviewActive:
    themePreviewActive = true
    themePreviewBaseTheme = config.themeName
    themePreviewCurrent = config.themeName

proc endThemePreviewSession*(persist: bool) =
  if not themePreviewActive:
    return
  if persist:
    themePreviewBaseTheme = config.themeName
    themePreviewCurrent = config.themeName
  else:
    if themePreviewBaseTheme.len > 0 and themePreviewCurrent.len > 0 and
       themePreviewCurrent != themePreviewBaseTheme:
      applyThemeAndColors(config, themePreviewBaseTheme)
      themePreviewCurrent = themePreviewBaseTheme
  themePreviewActive = false

proc updateThemePreview*() =
  let (cmd, _, _) = parseCommand(inputText)
  if cmd != ckTheme:
    return
  if actions.len == 0:
    endThemePreviewSession(false)
    return
  beginThemePreviewSession()
  if selectedIndex < 0 or selectedIndex >= actions.len:
    return
  let act = actions[selectedIndex]
  if act.kind != akTheme:
    return
  let name = act.exec
  if themePreviewCurrent == name:
    return
  applyThemeAndColors(config, name)
  themePreviewCurrent = name
