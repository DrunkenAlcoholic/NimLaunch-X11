version       = "0.8.1"
author        = "DrunkenAlcoholic"
description   = "A simple, fast, and highly configurable application launcher for X11"
license       = "MIT"
srcDir        = "src"
bin           = @["nimlaunch-x11"]

# — Dependencies ——————————————————————————————————————————————————————
requires "nim >= 2.2.0"
requires "parsetoml"
requires "x11"

# Build tasks
task release, "Build the application with release flags":
  mkDir("bin")
  exec "nim c -d:release -d:danger --passL:'-s' --opt:size -o:./bin/nimlaunch-x11 src/nimlaunch.nim"

task releaseIcons, "Build with optional Imlib2 icon rendering":
  mkDir("bin")
  exec "nim c -d:release -d:danger -d:icons --passL:'-s' --opt:size -o:./bin/nimlaunch-x11-icons src/nimlaunch.nim"

task zigit, "Build the application with Zig compiler":
  mkDir("bin")
  exec "nim c -d:release --cc:clang --clang.exe='./zigcc' --clang.linkerexe='./zigcc' --passL:'-s' -o:./bin/nimlaunch-x11 ./src/nimlaunch.nim"
  
task fast, "Build with speed optimizations (safer than danger), Using CachyOS v4 gcc":
  mkDir("bin")
  exec "nim c -d:release --opt:speed -o:./bin/nimlaunch-x11 src/nimlaunch.nim"

# Custom task to format all source files
task pretty, "Format all Nim files in src/ directory":
  exec "find src/ -name '*.nim' -exec nimpretty {} \\;"

task debug, "Build the application in debug mode":
  mkDir("bin")
  exec "nim c -o:./bin/nimlaunch-x11 src/nimlaunch.nim"

task debugIcons, "Build debug binary with optional Imlib2 icon rendering":
  mkDir("bin")
  exec "nim c -d:icons -o:./bin/nimlaunch-x11-icons src/nimlaunch.nim"

task test, "Run tests":
  exec "nim c -r tests/tparser.nim"
  exec "nim c -r tests/ticon_resolver.nim"

task clear, "Clean build artifacts":
  rmFile("bin/nimlaunch-x11")
  rmFile("bin/nimlaunch-x11-icons")
  rmFile("nimlaunch-x11")  # In case it's left in root
