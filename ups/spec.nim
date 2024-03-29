import std/options
import std/strutils
import std/hashes
import std/uri
import std/os
import std/times

import ups/paths
import ups/sanitize

type
  ForkTargetResult* = object
    ok*: bool
    why*: string
    owner*: string
    repo*: string
    url*: Uri

  ImportName* = distinct NimIdentifier  ## a valid nim import
  PackageName* = distinct ImportName    ## a valid nimble package
  DotNimble* = distinct AbsoluteFile

const
  dotNimble* {.strdefine.} = "".addFileExt("nimble")
  dotNimbleLink* {.strdefine.} = "".addFileExt("nimble-link")
  dotGit* {.strdefine.} = "".addFileExt("git")
  dotHg* {.strdefine.} = "".addFileExt("hg")
  DepDir* {.strdefine.} = "deps"
  PkgDir* {.strdefine.} = "pkgs"
  NimCfg* {.strdefine.} = "nim".addFileExt("cfg")
  ghTokenFn* {.strdefine.} = "github_api_token"
  ghTokenEnv* {.strdefine.} = "GITHUB_TOKEN"
  nimbleMeta* {.strdefine.} = "nimblemeta".addFileExt("json")
  officialPackages* {.strdefine.} = "packages_official".addFileExt("json")
  emptyRelease* {.strdefine.} = "#head"
  defaultRemote* {.strdefine.} = "origin"
  upstreamRemote* {.strdefine.} = "upstream"
  excludeMissingSearchPaths* {.booldefine.} = false
  excludeMissingLazyPaths* {.booldefine.} = true
  writeNimbleDirPaths* {.booldefine.} = false

  # when true, try to clamp analysis to project-local directories
  WhatHappensInVegas* = false

proc `$`*(file: DotNimble): string {.borrow.}
proc `$`*(name: ImportName): string {.borrow.}
proc `$`*(name: PackageName): string {.borrow.}

proc `==`*(a, b: ImportName): bool {.borrow.}
proc `==`*(a, b: PackageName): bool {.borrow.}
proc `<`*(a, b: ImportName): bool {.borrow.}
proc `<`*(a, b: PackageName): bool {.borrow.}

proc hash*(name: ImportName): Hash {.borrow.}
proc hash*(name: PackageName): Hash {.borrow.}

template repo*(file: DotNimble): string =
  $parentDir(file.AbsoluteFile)

template package*(file: DotNimble): string =
  lastPathPart($file).changeFileExt("")

template ext*(file: DotNimble): string =
  splitFile($file).ext

proc toDotNimble*(file: AbsoluteFile): DotNimble =
  file.DotNimble

proc fileExists*(file: DotNimble): bool {.borrow.}

template isValid*(url: Uri): bool = url.scheme.len != 0

proc isGitHub(url: Uri): bool =
  url.hostname.toLowerAscii == "github.com"

proc normalizeGitHub(uri: Uri): Uri =
  ## github paths are not case-sensitive, so we normalize them.
  ## NOTE: this is safe for repo URLs but i dunno if it's okay elsewhere...
  result = uri
  if uri.isGitHub:
    result.path = result.path.toLowerAscii

proc hash*(url: Uri): Hash =
  ## help hash URLs
  var h: Hash = 0
  let url = normalizeGitHub url
  for name, field in url.fieldPairs:
    when field is string:
      h = h !& field.hash
    elif field is bool:
      h = h !& field.hash
  result = !$h

proc bare*(url: Uri): Uri =
  result = normalizeGitHub url
  result.anchor = ""

proc bareUrlsAreEqual*(a, b: Uri): bool =
  ## compare two urls without regard to their anchors
  if a.isValid and b.isValid:
    var
      x = a.bare
      y = b.bare
    result = $x == $y

proc normalizeUrl*(uri: Uri): Uri =
  result = uri
  if result.scheme == "" and result.path.contains("@"):
    let
      usersep = result.path.find("@")
      pathsep = result.path.find(":")
    result.path = uri.path[pathsep+1 .. ^1]
    result.username = uri.path[0 ..< usersep]
    result.hostname = uri.path[usersep+1 ..< pathsep]
    result.scheme = "ssh"
  else:
    if result.scheme.startsWith("http"):
      result.scheme = "git"

proc convertToGit*(uri: Uri): Uri =
  result = normalizeUrl uri
  if result.scheme == "" or result.scheme == "ssh":
    result.scheme = "git"
  if result.scheme == "git" and not result.path.endsWith(".git"):
    result.path &= ".git"
  result.username = ""

proc convertToSsh*(uri: Uri): Uri =
  result = convertToGit uri
  if not result.path[0].isAlphaNumeric:
    result.path = result.path[1..^1]
  if result.username == "":
    result.username = "git"
  result.path = result.username & "@" & result.hostname & ":" & result.path
  result.username = ""
  result.hostname = ""
  result.scheme = ""

proc packageName*(name: string; capsOkay = true): PackageName =
  ## return a string that is plausible as a package name
  let sane = sanitizeIdentifier(strip name, capsOkay = capsOkay)
  if sane.isSome:
    result = PackageName get sane
  else:
    raise newException(ValueError, "invalid package name `" & name & "`")

proc packageName*(url: Uri): PackageName =
  ## guess the name of a package from a url
  when defined(debug) or defined(debugPath):
    assert url.isValid
  # ensure the path doesn't end in a slash
  var path = url.path
  removeSuffix path, {'/'}
  result = packageName path.extractFilename.changeFileExt("")

proc importName*(s: string; capsOkay = true): ImportName =
  ## turns any string into a valid nim identifier
  let sane = sanitizeIdentifier(strip s, capsOkay = capsOkay)
  if sane.isSome:
    # if it's a sane identifier, use it
    result = ImportName get sane
  else:
    # otherwise, this is a serious problem!
    raise newException ValueError:
      "unable to determine import name for `$#`" % [ s ]

proc importName*(name: ImportName): ImportName = name

proc importName*(name: PackageName): ImportName =
  ## calculate how a package will be imported by the compiler
  result = name.ImportName

proc importName*(path: AbsoluteFile): ImportName =
  ## calculate how a file will be imported by the compiler
  assert not path.isEmpty
  # strip any leading directories and extensions
  result = importName splitFile($path).name

proc importName*(path: AbsoluteDir): ImportName =
  ## calculate how a path will be imported by the compiler
  assert not path.isEmpty
  var path = normalizePathEnd($path, trailingSep = false)
  # strip off any -1.2.3 or -#branch garbage
  result = importName path.lastPathPart.changeFileExt("").split("-")[0]

proc importName*(file: DotNimble): ImportName =
  ## calculate how a file will be imported by the compiler
  result = importName file.AbsoluteFile

proc importName*(url: Uri): ImportName =
  ## a uniform name usable in code for imports
  let url = normalizeUrl url
  if not url.isValid:
    raise newException(ValueError, "invalid url: " & $url)
  elif url.scheme == "file":
    result = importName url.path.toAbsoluteDir
  else:
    result = importName packageName(url)

proc forkTarget*(url: Uri): ForkTargetResult =
  result.url = normalizeUrl url
  block failure:
    if not result.url.isValid:
      result.why = "url is invalid"
      break failure
    if not result.url.isGitHub:
      result.why = "url $# does not point to github" % [ $result.url ]
      break failure
    if result.url.path.len < 1:
      result.why = "unable to parse url $#" % [ $result.url ]
      break failure
    # split /foo/bar into (bar, foo)
    let start = if result.url.path.startsWith("/"): 1 else: 0
    (result.owner, result.repo) = result.url.path[start..^1].splitPath
    # strip .git
    if result.repo.endsWith".git":
      result.repo = result.repo[0..^len"git+2"]
    result.ok = result.owner.len > 0 and result.repo.len > 0
    if not result.ok:
      result.why = "unable to parse url $#" % [ $result.url ]

const
  # these are used by the isVirtual(): bool test in requirements
  virtualNimImports* = [importName"nim", importName"Nim"]
