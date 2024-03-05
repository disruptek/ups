import std/options
import std/os
import std/osproc
import std/strutils

import pkg/npeg
export match

import ups/versions
import ups/runner

type
  CompilerLanguage* = enum Nim, NimSkull

  CompilerVersion* = object
    language*: CompilerLanguage
    version*: Version
    extra*: string
    os*: string
    cpu*: string
    date*: string
    git*: string
    boot_switches*: seq[string]


let compilerPeg* = peg("nimversion", nv: CompilerVersion):

  S <- *{' ','\t','\n','\r'}
  nimversion <- oldnim_version | nimskull_version
  four_digits <- {'0'..'9'}[4]

  oldnim_version <- header * S *
                    "Compiled at " * date * S *
                    "Copyright (c) " * four_digits * "-" * four_digits * S *
                    "by Andreas Rumpf" * S * "git hash:" * S * git * S *
                    "active boot switches:" * S * boot_switches

  nimskull_version <- header * S *
                      "Source hash: " * git * S *
                      "Source date: " * date

  header <- typ * S * "Compiler Version" * S * version * S * "[" * os * ":" * S * cpu * "]" * S

  typ <- typ_nimskull | typ_nim
  typ_nim <- "Nim": nv.language = CompilerLanguage.Nim
  typ_nimskull <- "Nimskull": nv.language = CompilerLanguage.NimSkull

  int <- +{'0'..'9'}
  os <- >+Alnum: nv.os = $1
  cpu <- >+Alnum: nv.cpu = $1
  git <- >+{'0'..'9','a'..'f'}: nv.git = $1
  boot_switches <- *(boot_switch * S)
  boot_switch <- >+Graph: nv.boot_switches.add($1)
  date <- >+{'0'..'9','-'}: nv.date = $1
  version <- >int * "." * >int * "." * >int * ?"-" * >*Graph:
    nv.version.major = parseUInt($1)
    nv.version.minor = parseUInt($2)
    nv.version.patch = parseUInt($3)
    nv.extra = $4

proc parseCompilerVersion*(s: string): Option[CompilerVersion] =
  var v: CompilerVersion
  let r = compilerPeg.match(s, v)
  if r.ok:
    result = some: v

proc runCompilerVersion*(exe: string = ""): Option[CompilerVersion] =
  ## recover the compiler version from the given executable
  var exe = if exe == "": findExe"nim" else: exe
  let ran = runSomething(exe, @["--version"], {poStdErrToStdOut})
  if ran.ok:
    result = parseCompilerVersion ran.output
