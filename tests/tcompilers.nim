import std/options

import ups


let vnim = """Nim Compiler Version 2.1.1 [Linux: amd64]
Compiled at 2024-03-01
Copyright (c) 2006-2024 by Andreas Rumpf

git hash: 1e7ca2dc789eafccdb44304f7e42206c3702fc13
active boot switches: -d:release -d:danger
"""

let vnim2 = """Nim Compiler Version 1.6.11 [Linux: amd64]
Compiled at 2022-12-02
Copyright (c) 2006-2021 by Andreas Rumpf

git hash: 76c347515aaf1201c1307422b64494514c6301f9
active boot switches: -d:release
"""

let vskull = """Nimskull Compiler Version 0.1.0-dev.21234 [linux: amd64]

Source hash: 4948ae809f7d84ef6d765111a7cd0c7cf2ae77d2
Source date: 2024-02-18
"""

block:
  let nv = parseCompilerVersion vnim
  doAssert nv.isSome
  echo nv.get

block:
  let nv = parseCompilerVersion vnim2
  doAssert nv.isSome
  echo nv.get

block:
  let nv = parseCompilerVersion vskull
  doAssert nv.isSome
  echo nv.get
