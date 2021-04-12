version = "0.0.7"
author = "disruptek"
description = "a package handler"
license = "MIT"

requires "npeg >= 0.23.2 & < 1.0.0"

#when false:
#  when not defined(release):
#    requires "https://github.com/disruptek/balls >= 2.0.0 & < 3.0.0"

task test, "run tests":
  when defined(windows):
    exec "balls.cmd"
  else:
    exec findExe"balls"
