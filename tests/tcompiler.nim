import std/options

import ups/compiler


let vnim = """Nim Compiler Version 2.1.1 [Linux: amd64]
Compiled at 2024-03-01
Copyright (c) 2006-2024 by Andreas Rumpf

git hash: 1e7ca2dc789eafccdb44304f7e42206c3702fc13
active boot switches: -d:release -d:danger
"""

let vskull = """Nimskull Compiler Version 0.1.0-dev.21234 [linux: amd64]

Source hash: 4948ae809f7d84ef6d765111a7cd0c7cf2ae77d2
Source date: 2024-02-18
"""

var nv: CompilerVersion

block:
  let nv = parseCompilerVersion vnim
  doAssert nv.isSome
  echo nv.get

block:
  let nv = parseCompilerVersion vskull
  doAssert nv.isSome
  echo nv.get
