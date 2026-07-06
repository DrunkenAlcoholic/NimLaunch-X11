import std/[os, unittest]
import ../src/icon_resolver

proc resetIconTestDir(): string =
  result = getTempDir() / "nimlaunch-x11-icon-tests"
  if dirExists(result):
    removeDir(result)

suite "icon resolver":
  test "resolves absolute paths":
    let dir = resetIconTestDir()
    createDir(dir)
    let iconPath = dir / "absolute.png"
    writeFile(iconPath, "")
    check resolveIconInRoots(iconPath, @[]) == iconPath

  test "tries common icon extensions":
    let dir = resetIconTestDir()
    createDir(dir)
    let iconPath = dir / "bare.xpm"
    writeFile(iconPath, "")
    check resolveIconInRoots(dir / "bare", @[]) == iconPath

  test "prefers configured icon theme":
    putEnv("ICON_THEME", "breeze")
    let dir = resetIconTestDir()
    let root = dir / "icons"
    let hicolor = root / "hicolor" / "24x24" / "apps"
    let breeze = root / "breeze" / "24x24" / "apps"
    createDir(hicolor)
    createDir(breeze)
    writeFile(hicolor / "themed.png", "")
    writeFile(breeze / "themed.png", "")
    let index = buildIconIndex(@[root])
    check resolveIconInIndex("themed", index, preferredSize = 24) ==
      breeze / "themed.png"

  test "prefers requested size and png":
    let dir = resetIconTestDir()
    let root = dir / "icons"
    let small = root / "hicolor" / "16x16" / "apps"
    let target = root / "hicolor" / "24x24" / "apps"
    let scalable = root / "hicolor" / "scalable" / "apps"
    createDir(small)
    createDir(target)
    createDir(scalable)
    writeFile(small / "sample.png", "")
    writeFile(target / "sample.png", "")
    writeFile(scalable / "sample.svg", "")
    check resolveIconInRoots("sample", @[root], preferredSize = 24) ==
      target / "sample.png"
    let index = buildIconIndex(@[root])
    check resolveIconInIndex("sample", index, preferredSize = 24) ==
      target / "sample.png"

  test "finds pixmaps fallback":
    let dir = resetIconTestDir()
    let pixmaps = dir / "pixmaps"
    createDir(pixmaps)
    writeFile(pixmaps / "legacy.xpm", "")
    check resolveIconInRoots("legacy", @[pixmaps]) == pixmaps / "legacy.xpm"
    let index = buildIconIndex(@[pixmaps])
    check resolveIconInIndex("legacy", index) == pixmaps / "legacy.xpm"
