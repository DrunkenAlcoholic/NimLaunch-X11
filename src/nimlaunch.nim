## nimlaunch.nim — main program
## MIT; see LICENSE for details.

# ── Imports ─────────────────────────────────────────────────────────────
import std/[os, strutils, tables, times, exitprocs]
when defined(posix):
  import posix
import parsetoml as toml
import x11/[xlib, xutil, x, keysym]
import ./[state, parser, gui, utils, executor, config_loader, search]
when defined(icons):
  import ./icon_resolver
when defined(posix):
  when not declared(flock):
    proc flock(fd: cint; operation: cint): cint {.importc, header: "<sys/file.h>".}

# ── Module-local globals ────────────────────────────────────────────────




var
  lockFilePath = ""
when defined(posix):
  var lockFd: cint = -1



# ── Single-instance helpers ────────────────────────────────────────────
when defined(posix):
  const
    LOCK_EX = 2.cint
    LOCK_NB = 4.cint
    LOCK_UN = 8.cint

  proc releaseSingleInstanceLock() =
    if lockFd >= 0:
      discard flock(lockFd, LOCK_UN)
      discard close(lockFd)
      lockFd = -1
    if lockFilePath.len > 0 and fileExists(lockFilePath):
      try:
        removeFile(lockFilePath)
      except CatchableError:
        discard

  proc ensureSingleInstance(): bool =
    ## Obtain an exclusive advisory lock; return false if another instance owns it.
    let cacheDir = getHomeDir() / ".cache" / "nimlaunch"
    try:
      createDir(cacheDir)
    except CatchableError:
      discard
    lockFilePath = cacheDir / "nimlaunch.lock"

    let fd = open(lockFilePath.cstring, O_RDWR or O_CREAT, 0o664)
    if fd < 0:
      echo "NimLaunch warning: unable to open lock file at ", lockFilePath
      return true

    if flock(fd, LOCK_EX or LOCK_NB) != 0:
      discard close(fd)
      return false

    discard ftruncate(fd, 0)
    discard lseek(fd, 0, 0)
    let pidStr = $getCurrentProcessId() & "\n"
    discard write(fd, pidStr.cstring, pidStr.len.cint)

    lockFd = fd
    addExitProc(releaseSingleInstanceLock)
    true
else:
  proc releaseSingleInstanceLock() =
    if lockFilePath.len > 0 and fileExists(lockFilePath):
      try:
        removeFile(lockFilePath)
      except CatchableError:
        discard

  proc ensureSingleInstance(): bool =
    ## Basic file sentinel fallback for non-POSIX targets.
    let cacheDir = getHomeDir() / ".cache" / "nimlaunch"
    try:
      createDir(cacheDir)
    except CatchableError:
      discard
    lockFilePath = cacheDir / "nimlaunch.lock"

    if fileExists(lockFilePath):
      return false

    try:
      writeFile(lockFilePath, $getCurrentProcessId())
      addExitProc(releaseSingleInstanceLock)
    except CatchableError:
      discard
    true

# ── Small searches: ~/.config helper ────────────────────────────────────






# ── Prefix helpers ─────────────────────────────────────────────────────
# ── Theme helpers ───────────────────────────────────────────────────────


# ── Applications discovery (.desktop) ───────────────────────────────────




# ── Fuzzy match + helpers ───────────────────────────────────────────────


proc updateDisplayRows(cmd: CmdKind; highlightQuery: string; defaultIndex: int) =
  ## Sync state.filteredApps/matchSpans and maintain selection/preview state.
  filteredApps.setLen(0)
  matchSpans.setLen(0)

  for act in actions:
    filteredApps.add DisplayRow(text: act.label, iconPath: act.iconPath)
    if highlightQuery.len == 0:
      matchSpans.add @[]
    else:
      case act.kind
      of akRun:
        const prefix = "Run: "
        let off = if act.label.len >= prefix.len: prefix.len else: 0
        let seg = if off < act.label.len: act.label[off .. ^1] else: ""
        var spansAbs: seq[(int, int)] = @[]
        for (s, l) in subseqSpans(highlightQuery, seg): spansAbs.add (off + s, l)
        matchSpans.add spansAbs
      of akPlaceholder:
        matchSpans.add @[]
      else:
        matchSpans.add subseqSpans(highlightQuery, act.label)

  if actions.len == 0:
    if cmd == ckTheme:
      endThemePreviewSession(false)
    else:
      selectedIndex = 0
      viewOffset = 0
  else:
    let maxIndex = actions.len - 1
    var clamped = min(defaultIndex, maxIndex)
    if cmd == ckTheme and defaultIndex == 0:
      clamped = min(selectedIndex, maxIndex)
    selectedIndex = clamped
    let visible = max(1, config.maxVisibleItems)
    if clamped >= visible:
      viewOffset = clamped - visible + 1
    else:
      viewOffset = 0

    if cmd == ckTheme:
      if actions.len > 0 and actions[selectedIndex].kind == akTheme:
        updateThemePreview()
      else:
        endThemePreviewSession(false)
    else:
      endThemePreviewSession(false)

# ── Build actions & mirror to filteredApps ─────────────────────────────
proc buildActions() =
  ## Populate `actions` based on `inputText`; mirror to GUI lists/spans.
  let (cmd, rest, shortcutIdx) = parseCommand(inputText)
  var defaultIndex = 0
  var nextActions: seq[Action] = @[]

  case cmd
  of ckTheme:
    beginThemePreviewSession()
    nextActions = buildThemeActions(rest, defaultIndex)
  of ckConfig:
    nextActions = buildConfigActions(rest)
  of ckShortcut:
    nextActions = buildShortcutActions(rest, shortcutIdx)
  of ckMenu:
    nextActions = buildMenuActions(shortcutIdx, rest)
  of ckSearch:
    nextActions = buildSearchActions(rest)
  of ckRun:
    nextActions = buildRunActions(rest)
  else:
    discard

  if cmd == ckNone:
    nextActions = buildDefaultActions(rest, defaultIndex)
  elif nextActions.len == 0:
    nextActions.add Action(kind: akPlaceholder, label: "No matches", exec: "")

  actions = nextActions
  updateDisplayRows(cmd, rest, defaultIndex)

# ── Perform selected action ─────────────────────────────────────────────
proc clearInput() =
  inputText.setLen(0)
  lastInputChangeMs = gui.nowMs()
  buildActions()

proc performAction(a: Action) =
  var exitAfter = true ## default: exit after action
  case a.kind
  of akRun:
    runCommand(a.exec)
  of akConfig:
    if not spawnShellCommand(a.exec):
      gui.notifyStatus("Failed: " & a.label, 1600)
      exitAfter = false
  of akFile:
    discard openPathWithFallback(a.exec)
  of akApp, akAppAction:
    ## safer: strip .desktop field codes before launching
    let sanitized = parser.stripFieldCodes(a.exec).strip()
    let args = parser.tokenize(sanitized)
    var success = false
    if args.len > 0:
      success = spawnProcess(args[0], args[1..^1])
    if success:
      let recentName = if a.appData.name.len > 0: a.appData.name else: a.label
      let ri = recentApps.find(recentName)
      if ri >= 0: recentApps.delete(ri)
      recentApps.insert(recentName, 0)
      if recentApps.len > maxRecent: recentApps.setLen(maxRecent)
      saveRecent()
    else:
      gui.notifyStatus("Failed: " & a.label, 1600)
      exitAfter = false
  of akShortcut:
    case a.shortcutMode
    of smUrl:
      openUrl(a.exec)
    of smShell:
      runCommand(a.exec)
    of smFile:
      let expanded = a.exec.expandTilde()
      if not fileExists(expanded) and not dirExists(expanded):
        gui.notifyStatus("Not found: " & shortenPath(expanded, 50), 1600)
        exitAfter = false
      elif not openPathWithFallback(expanded):
        gui.notifyStatus("Failed to open: " & shortenPath(expanded, 50), 1600)
        exitAfter = false
  of akMenuAction:
    var success = true
    case a.menuMode
    of mamSpawn:
      success = spawnShellCommand(a.exec)
    of mamTerminal:
      runCommand(a.exec)
    if not success:
      gui.notifyStatus("Failed: " & a.label, 1600)
      exitAfter = false
    elif a.stayOpen:
      exitAfter = false
  of akTheme:
    ## Apply and persist, but DO NOT reset selection or exit.
    applyThemeAndColors(config, a.exec, doNotify = false)
    saveLastTheme(getHomeDir() / ".config" / "nimlaunch" / "nimlaunch.toml")
    endThemePreviewSession(true)
    clearInput()
    gui.redrawWindow()
    exitAfter = false
  of akPlaceholder:
    exitAfter = false
  if exitAfter: shouldExit = true

# ── Input/navigation helpers ───────────────────────────────────────────
proc deleteLastInputChar() =
  if inputText.len > 0:
    inputText.setLen(inputText.len - 1)
    lastInputChangeMs = gui.nowMs()
    buildActions()

proc activateCurrentSelection() =
  if selectedIndex in 0..<actions.len:
    if dmenuMode:
      echo actions[selectedIndex].exec
      shouldExit = true
    else:
      performAction(actions[selectedIndex])

proc moveSelectionBy(step: int) =
  if filteredApps.len == 0: return
  var newIndex = selectedIndex + step
  if newIndex < 0: newIndex = 0
  if newIndex > filteredApps.len - 1: newIndex = filteredApps.len - 1
  if newIndex == selectedIndex: return
  selectedIndex = newIndex
  if selectedIndex < viewOffset:
    viewOffset = selectedIndex
  elif selectedIndex >= viewOffset + config.maxVisibleItems:
    viewOffset = selectedIndex - config.maxVisibleItems + 1
    if viewOffset < 0: viewOffset = 0
  updateThemePreview()

proc jumpToTop() =
  if filteredApps.len == 0: return
  selectedIndex = 0
  viewOffset = 0
  updateThemePreview()

proc jumpToBottom() =
  if filteredApps.len == 0: return
  selectedIndex = filteredApps.len - 1
  let start = filteredApps.len - config.maxVisibleItems
  viewOffset = if start > 0: start else: 0
  updateThemePreview()

proc syncVimCommand() =
  inputText = vimCommandBuffer
  lastInputChangeMs = gui.nowMs()
  buildActions()

proc openVimCommand(initial: string = "") =
  if not vimCommandActive:
    vimSavedInput = inputText
    vimSavedSelectedIndex = selectedIndex
    vimSavedViewOffset = viewOffset
    vimCommandRestorePending = true
  if initial.len == 0 and vimLastSearchBuffer.len > 0:
    vimCommandBuffer = vimLastSearchBuffer
  else:
    vimCommandBuffer = initial
  vimCommandActive = true
  vimPendingG = false
  syncVimCommand()

proc closeVimCommand(restoreInput = false; preserveBuffer = false) =
  let savedInput = vimSavedInput
  let savedSelected = vimSavedSelectedIndex
  let savedOffset = vimSavedViewOffset
  let savedBuffer = vimCommandBuffer
  if savedBuffer.len == 0:
    vimLastSearchBuffer = ""
  elif preserveBuffer and (savedBuffer[0] != ':' and savedBuffer[0] != '!'):
    vimLastSearchBuffer = savedBuffer
  vimCommandBuffer.setLen(0)
  vimCommandActive = false
  vimPendingG = false

  if restoreInput and vimCommandRestorePending:
    inputText = savedInput
    lastInputChangeMs = gui.nowMs()
    buildActions()

    if filteredApps.len > 0:
      let clampedSel = max(0, min(savedSelected, filteredApps.len - 1))
      let visibleRows = max(1, config.maxVisibleItems)
      let maxOffset = max(0, filteredApps.len - visibleRows)
      var newOffset = max(0, min(savedOffset, maxOffset))
      if clampedSel < newOffset:
        newOffset = clampedSel
      elif clampedSel >= newOffset + visibleRows:
        newOffset = max(0, clampedSel - visibleRows + 1)
      selectedIndex = clampedSel
      viewOffset = newOffset
    else:
      selectedIndex = 0
      viewOffset = 0

  vimSavedInput = ""
  vimSavedSelectedIndex = 0
  vimSavedViewOffset = 0
  vimCommandRestorePending = false



proc executeVimCommand() =
  let trimmed = vimCommandBuffer.strip()
  closeVimCommand(preserveBuffer = false)
  if trimmed.len == 0:
    return
  if trimmed == ":q":
    shouldExit = true
    return
  inputText = trimmed
  lastInputChangeMs = gui.nowMs()
  buildActions()
  if trimmed.len == 0 or (trimmed[0] != ':' and trimmed[0] != '!'):
    vimLastSearchBuffer = trimmed
  if actions.len > 0:
    activateCurrentSelection()

proc handleVimKey(ks: KeySym; text: string; ch: char; state: cuint): bool =
  if not config.vimMode:
    return false

  if vimCommandActive:
    if ks == XK_Return:
      executeVimCommand()
      return true
    if ks == XK_BackSpace or ks == XK_Delete:
      if vimCommandBuffer.len > 0:
        vimCommandBuffer.setLen(vimCommandBuffer.len - 1)
        syncVimCommand()
      else:
        closeVimCommand(restoreInput = true, preserveBuffer = false)
        return true
    if ks == XK_h and (state and ControlMask.cuint) != 0:
      if vimCommandBuffer.len > 0:
        vimCommandBuffer.setLen(vimCommandBuffer.len - 1)
        syncVimCommand()
      else:
        closeVimCommand(restoreInput = true, preserveBuffer = false)
      return true
    if ks == XK_u and (state and ControlMask.cuint) != 0:
      vimCommandBuffer.setLen(0)
      syncVimCommand()
      return true
    if ks == XK_Escape:
      closeVimCommand(restoreInput = true, preserveBuffer = true)
      return true
    if text.len > 0:
      vimCommandBuffer.add(text)
      syncVimCommand()
      return true
    return true

  case ks
  of XK_slash:
    if vimCommandActive:
      vimCommandBuffer.add('/')
      syncVimCommand()
    else:
      openVimCommand("")
    return true
  of XK_colon:
    openVimCommand(":")
    return true
  of XK_exclam:
    openVimCommand("!")
    return true
  of XK_g, XKc_G:
    let shiftHeld = (ks == XKc_G) or (state and ShiftMask.cuint) != 0 or ch == 'G'
    if shiftHeld:
      vimPendingG = false
      jumpToBottom()
    elif vimPendingG:
      vimPendingG = false
      jumpToTop()
    else:
      vimPendingG = true
    return true
  of XK_Escape:
    shouldExit = true
    return true
  of XK_j:
    vimPendingG = false
    moveSelectionBy(1)
    return true
  of XK_k:
    vimPendingG = false
    moveSelectionBy(-1)
    return true
  of XK_h:
    vimPendingG = false
    deleteLastInputChar()
    return true
  of XK_l:
    vimPendingG = false
    activateCurrentSelection()
    return true
  else:
    if text.len > 0:
      vimPendingG = false
      return true
    vimPendingG = false
    return false

# ── Main loop ───────────────────────────────────────────────────────────
proc main() =
  if not ensureSingleInstance():
    echo "NimLaunch is already running."
    quit 0
  benchMode = "--bench" in commandLineParams()
  dmenuMode = "--dmenu" in commandLineParams() or "-dmenu" in commandLineParams()

  timeIt "Init Config:": initLauncherConfig()
  
  if dmenuMode:
    allApps = @[]
    for line in stdin.lines:
      let clean = line.strip()
      if clean.len > 0:
        allApps.add DesktopApp(name: clean, exec: clean)
    allAppsIndex = initTable[string, DesktopApp]()
  else:
    timeIt "Load Applications:": loadApplications()
    when defined(icons):
      timeIt "Build Icon Index:":
        iconIndex = buildIconIndex(defaultIconRoots())
    timeIt "Load Recent Apps:": loadRecent()
  timeIt "Build Actions:": buildActions()

  vimPendingG = false
  vimCommandBuffer.setLen(0)
  vimCommandActive = false

  initGui()

  ## Theme parsing must happen after initGui opens the display but before the
  ## first redraw so Xft colours resolve correctly.
  timeIt "updateParsedColors:": updateParsedColors(config)
  timeIt "updateGuiColors:": gui.updateGuiColors()
  timeIt "Benchmark(Redraw Frame):": gui.redrawWindow()

  if benchMode: quit 0

  while not shouldExit:
    if XPending(display) == 0:
      ## Debounce wake-up: if we're in s: search, rebuild after idle
      let (cmd, rest, _) = parseCommand(inputText)
      if cmd == ckSearch:
        let sinceEdit = gui.nowMs() - lastInputChangeMs
        if rest.len >= 2 and sinceEdit >= SearchDebounceMs and
           lastSearchBuildMs < lastInputChangeMs:
          lastSearchBuildMs = gui.nowMs()
          buildActions()
          gui.redrawWindow()
          continue
      sleep(10)
      continue

    var ev: XEvent
    discard XNextEvent(display, ev.addr)
    case ev.theType
    of MapNotify:
      if ev.xmap.window == window: seenMapNotify = true
    of Expose:
      gui.redrawWindow()
    of KeyPress:
      var ks: KeySym
      var text = ""
      var ch: char = '\0'
      if not inputContext.isNil:
        var utfBuf: array[64, char]
        var status: Status = 0
        let cap = (utfBuf.len - 1).cint
        let count = Xutf8LookupString(inputContext, ev.xkey.addr,
                                      cast[cstring](utfBuf[0].addr), cap,
                                      ks.addr, addr status)
        if status == XBufferOverflow and count > 0:
          let needed = count.int
          var tmp = newString(needed)
          let actual = Xutf8LookupString(
            inputContext, ev.xkey.addr,
            cast[cstring](tmp.cstring), count,
            ks.addr, addr status)
          tmp.setLen(actual.int)
          text = tmp
        elif count > 0:
          let termIdx = min(count.int, utfBuf.len - 1)
          utfBuf[termIdx] = '\0'
          text = $cast[cstring](utfBuf[0].addr)
      else:
        var buf: array[64, char]
        let count = XLookupString(ev.xkey.addr, cast[cstring](buf[0].addr),
                                  (buf.len - 1).cint, ks.addr, nil)
        if count > 0:
          let termIdx = min(count.int, buf.len - 1)
          buf[termIdx] = '\0'
          text = $cast[cstring](buf[0].addr)
      if text.len > 0:
        ch = text[0]
      var handled = false
      if config.vimMode:
        handled = handleVimKey(ks, text, ch, ev.xkey.state)
      elif (ks == XK_u or ks == XK_U) and ((ev.xkey.state and ControlMask.cuint) != 0):
        clearInput()
        handled = true
      elif (ks == XK_h or ks == XK_H) and ((ev.xkey.state and ControlMask.cuint) != 0):
        deleteLastInputChar()
        handled = true
      if not handled:
        case ks
        of XK_Escape:
          shouldExit = true

        of XK_Return:
          activateCurrentSelection()

        of XK_BackSpace, XK_Left:
          deleteLastInputChar()

        of XK_Right:
          discard # no mid-string editing yet

        of XK_Up:
          moveSelectionBy(-1)

        of XK_Down:
          moveSelectionBy(1)

        of XK_Page_Up:
          if filteredApps.len > 0:
            moveSelectionBy(-max(1, config.maxVisibleItems))

        of XK_Page_Down:
          if filteredApps.len > 0:
            moveSelectionBy(max(1, config.maxVisibleItems))

        of XK_Home:
          jumpToTop()

        of XK_End:
          jumpToBottom()

        else:
          if text.len > 0:
            inputText.add(text)
            lastInputChangeMs = gui.nowMs()
            buildActions()

      if not shouldExit:
        gui.redrawWindow()

    of ButtonPress:
      shouldExit = true
    of FocusOut:
      let mode = ev.xfocus.mode
      if mode == NotifyGrab or mode == NotifyUngrab:
        discard
      elif seenMapNotify:
        seenMapNotify = false
      else:
        shouldExit = true
    else:
      discard

  if themePreviewActive:
    endThemePreviewSession(false)

  if not inputContext.isNil:
    XDestroyIC(inputContext)
    inputContext = nil
  if not inputMethod.isNil:
    discard XCloseIM(inputMethod)
    inputMethod = nil

  discard XDestroyWindow(display, window)
  discard XCloseDisplay(display)

when isMainModule:
  main()
