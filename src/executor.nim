## executor.nim — process and command execution helpers
## MIT; see LICENSE for details.

import std/[os, osproc, strutils]
import ./[parser, utils]

proc hasHoldFlagLocal*(args: seq[string]): bool =
  ## Detect common "keep window open" flags passed to terminals.
  for a in args:
    case a
    of "--hold", "-hold", "--keep-open", "--wait", "--noclose",
       "--stay-open", "--keep", "--keepalive":
      return true
    else:
      discard
  false

proc appendShellArgs*(argv: var seq[string]; shExe: string; shArgs: seq[string]) =
  ## Append shell executable and its arguments to `argv`.
  argv.add shExe
  for a in shArgs: argv.add a

proc buildTerminalArgs*(base: string; termArgs: seq[string]; shExe: string;
                       shArgs: seq[string]): seq[string] =
  ## Normalize command-line to launch a shell inside major terminals.
  var argv = termArgs
  case base
  of "gnome-terminal", "kgx":
    argv.add "--"
  of "wezterm":
    argv = @["start"] & argv
  else:
    argv.add "-e"
  appendShellArgs(argv, shExe, shArgs)
  argv

proc buildShellCommand*(cmd, shExe: string; hold = false):
    tuple[fullCmd: string, shArgs: seq[string]] =
  ## Run user's command in a group, and add a robust hold prompt when needed.
  let suffix = (if hold: "" else: "; printf '\\n[Press Enter to close]\\n'; read -r _")
  let fullCmd = "{ " & cmd & " ; }" & suffix
  let shArgs = if shExe.endsWith("bash"): @["-lc", fullCmd] else: @["-c", fullCmd]
  (fullCmd, shArgs)

proc runCommand*(cmd: string) =
  ## Run `cmd` in the user's terminal; fall back to /bin/sh if none.
  let bash = findExe("bash")
  let shExe = if bash.len > 0: bash else: "/bin/sh"

  var parts = parser.tokenize(chooseTerminal())
  if parts.len == 0:
    let (_, shArgs) = buildShellCommand(cmd, shExe)
    discard startProcess(shExe, args = shArgs,
                         options = {poDaemon, poParentStreams})
    return

  let exe = parts[0]
  let exePath = findExe(exe)
  if exePath.len == 0:
    let (_, shArgs) = buildShellCommand(cmd, shExe)
    discard startProcess(shExe, args = shArgs,
                         options = {poDaemon, poParentStreams})
    return

  var termArgs = if parts.len > 1: parts[1..^1] else: @[]
  let base = exe.extractFilename()
  let hold = hasHoldFlagLocal(termArgs)
  let (_, shArgs) = buildShellCommand(cmd, shExe, hold)
  let argv = buildTerminalArgs(base, termArgs, shExe, shArgs)
  discard startProcess(exePath, args = argv,
                       options = {poDaemon, poParentStreams})

proc spawnShellCommand*(cmd: string): bool =
  ## Execute *cmd* via /bin/sh in the background; return success.
  try:
    discard startProcess("/bin/sh", args = ["-c", cmd],
                         options = {poDaemon, poParentStreams})
    true
  except CatchableError as e:
    echo "spawnShellCommand failed: ", cmd, " (", e.name, "): ", e.msg
    false

proc openUrl*(url: string) =
  ## Open *url* via xdg-open (no shell involved). Log failures for diagnosis.
  try:
    discard startProcess("/usr/bin/env", args = @["xdg-open", url],
                         options = {poDaemon, poParentStreams})
  except CatchableError as e:
    echo "openUrl failed: ", url, " (", e.name, "): ", e.msg
