version = "0.0.5"
author = "disruptek"
description = "a package handler"
license = "MIT"

requires "npeg >= 0.23.2 & < 1.0.0"

#when false:
#  when not defined(release):
#    requires "https://github.com/disruptek/testes >= 1.0.0 & < 2.0.0"

task test, "run tests":
  #when false:
  #  when defined(windows):
  #    exec "testes.cmd"
  #  else:
  #    exec findExe"testes"
  exec "nim check ups.nim"
