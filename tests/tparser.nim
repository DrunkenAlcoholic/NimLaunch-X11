import std/[options, os, unittest]
import ../src/parser

suite "parser":
  test "stripFieldCodes":
    check stripFieldCodes("code %F") == "code "
    check stripFieldCodes("foo %u %c") == "foo  "
    check stripFieldCodes("echo %%") == "echo %"
    check stripFieldCodes("app %X %Y") == "app  "

  test "tokenize":
    check tokenize("foo bar") == @["foo", "bar"]
    check tokenize("sh -c \"echo hello\"") == @["sh", "-c", "echo hello"]
    check tokenize("'single quote' test") == @["single quote", "test"]
    check tokenize("env FOO=1 bar") == @["env", "FOO=1", "bar"]
    check tokenize("exec \\\"escaped\\\"") == @["exec", "\"escaped\""]

  test "getBaseExec":
    check getBaseExec("/usr/bin/kitty --single-instance") == "kitty"
    check getBaseExec("code %F") == "code"
    check getBaseExec("env FOO=1 VAR=2 /opt/app/bin/foo %U") == "foo"
    check getBaseExec("flatpak run com.app.Name") == "com.app.Name"
    check getBaseExec("sh -c 'prog --opt'") == "prog"
    check getBaseExec("sudo nano") == "nano"
    check getBaseExec("pkexec /usr/bin/gparted") == "gparted"

  test "parseDesktopFile includes launchable desktop actions":
    let dir = getTempDir() / "nimlaunch-x11-parser-tests"
    if dirExists(dir):
      removeDir(dir)
    createDir(dir)
    let desktopPath = dir / "sample.desktop"
    writeFile(desktopPath, """
[Desktop Entry]
Type=Application
Name=Sample App
Exec=sample %U
Icon=sample
Actions=NewWindow;HiddenAction;MissingAction;

[Desktop Action NewWindow]
Name=New Window
Exec=sample --new-window %U

[Desktop Action HiddenAction]
Name=Hidden
Exec=sample --hidden
NoDisplay=true
""")
    let parsed = parseDesktopFile(desktopPath)
    check parsed.isSome
    let app = parsed.get()
    check app.name == "Sample App"
    check app.exec == "sample %U"
    check app.icon == "sample"
    check app.hasIcon
    check app.desktopActions.len == 1
    check app.desktopActions[0].id == "NewWindow"
    check app.desktopActions[0].name == "New Window"
    check app.desktopActions[0].exec == "sample --new-window %U"

  test "parseDesktopFile skips missing TryExec":
    let dir = getTempDir() / "nimlaunch-x11-parser-tests"
    if dirExists(dir):
      removeDir(dir)
    createDir(dir)
    let desktopPath = dir / "tryexec.desktop"
    writeFile(desktopPath, """
[Desktop Entry]
Type=Application
Name=Missing Tool
Exec=missing-tool
TryExec=/definitely/not/a/real/nimlaunch/tool
""")
    check parseDesktopFile(desktopPath).isNone
