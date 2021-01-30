import std/strutils
import std/hashes
import std/os

import compiler/pathutils except toAbsoluteDir, toAbsolute
export pathutils except toAbsoluteDir, toAbsolute

#[

i'm still wary of the (loose) `==`(x, y: AnyPath) from the compiler, but
at least our hash() routines shouldn't equate AbsoluteDir to AbsoluteFile.

]#

when (NimMajor, NimMinor) >= (1, 1):
  proc normal*(path: string): string =
    joinPath(path, $DirSep, "")
  # we export this for consistency with the codepath below
  export normalizePathEnd
else:
  proc normal*(path: string): string =
    joinPath(path, "")

  proc normalizePathEnd*(path: var string; trailingSep = false) =
    ## this is an approximation to mimic the proc exposed in nim-1.1+
    if path != "" or trailingSep != true:
      path = joinPath(path, "")
      if not trailingSep and path.len > 1:
        removeSuffix(path, DirSep)

  proc normalizePathEnd*(path: string; trailingSep = false): string =
    ## an outplace version of the above
    result = path
    normalizePathEnd(result, trailingSep)

proc parentDir*(dir: AbsoluteDir): AbsoluteDir =
  result = dir / RelativeDir".."
  #assert not endsWith($result, DirSep)

proc parentDir*(dir: AbsoluteFile): AbsoluteDir =
  result = AbsoluteDir(dir).parentDir

proc hashCase(path: AbsoluteDir | AbsoluteFile): string =
  ## two paths of differing case should hash identically on
  ## case-insensitive filesystems
  when FilesystemCaseSensitive:
    result = path.string
  else:
    result = toLowerAscii path.string

proc hash*(p: AbsoluteDir): Hash =
  ## we force the hash to use a trailing DirSep on directories
  hash normalizePathEnd(hashCase p, trailingSep = true)

proc hash*(p: AbsoluteFile): Hash =
  ## we force the hash to omit a trailing DirSep on files
  hash normalizePathEnd(hashCase p, trailingSep = false)

proc toAbsoluteDir*(s: string): AbsoluteDir =
  ## make very, very sure our directories are very, very well-formed
  var s = absolutePath(s).normalizedPath
  normalizePathEnd(s, trailingSep = false)
  result = pathutils.toAbsoluteDir s
  #assert dirExists(result), $result & " is missing"
  #assert not endsWith($result, DirSep)

proc toAbsoluteFile*(s: string): AbsoluteFile =
  ## make very, very sure our file paths are very, very well-formed
  let dir = getCurrentDir().toAbsoluteDir
  var s = absolutePath(s, $dir).normalizedPath
  normalizePathEnd(s, trailingSep = false)
  result = pathutils.toAbsolute(s, dir)
  #assert fileExists result, $result & " is missing"

template withinDirectory*(path: AbsoluteDir; body: untyped): untyped =
  if not dirExists path:
    raise newException ValueError:
      $path & " is not a directory"
  let cwd = getCurrentDir()
  setCurrentDir $path
  try:
    body
  finally:
    setCurrentDir cwd

template withinDirectory*(path: string; body: untyped): untyped =
  withinDirectory path.toAbsoluteDir:
    body

proc startsWith*(path: AbsoluteDir; parent: AbsoluteDir): bool =
  ## true if path is a subdirectory of parent
  var path = path
  block done:
    while path != parent:
      if path.isEmpty:
        break done
      path = parentDir path
    result = true

proc startsWith*(path: AbsoluteDir; parent: string): bool =
  ## true if path is a subdirectory of parent
  var dir = toAbsoluteDir parent
  result = path.startsWith dir

proc startsWith*(path: AbsoluteFile; s: string): bool =
  ## true if path and s are equal; for generic use
  path == toAbsoluteFile s

proc endsWith*(path: AbsoluteDir; s: string): bool =
  ## true if the path ends with relative directory s
  result = parentDir(path) / RelativeDir(s) == path

proc endsWith*(path: AbsoluteFile; s: string): bool =
  ## true if the path ends with relative file s
  result = parentDir(path) / RelativeFile(s) == path

proc isRootDir*(path: AbsoluteDir): bool {.borrow.}
