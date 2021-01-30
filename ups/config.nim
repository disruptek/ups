import std/osproc
import std/json
import std/nre
import std/strtabs
import std/hashes
import std/sets
import std/tables
import std/os
import std/options
import std/strutils
import std/logging

import compiler/ast
import compiler/idents
import compiler/nimconf
import compiler/options as compileropts
import compiler/condsyms
import compiler/lineinfos

export compileropts
export nimconf

import npeg

import ups/spec
import ups/runner
import ups/paths

when defined(debugPath):
  from std/sequtils import count

type
  ProjectCfgParsed* = object
    table*: TableRef[string, string]
    why*: string
    ok*: bool

  ConfigSection = enum
    LockerRooms = "lockfiles"

  SubType = enum                    ## tokens we use for path substitution
    stCache = "nimcache"
    stConfig = "config"
    stNimbleDir = "nimbledir"
    stNimblePath = "nimblepath"
    stProjectDir = "projectdir"
    stProjectPath = "projectpath"
    stLib = "lib"
    stNim = "nim"
    stHome = "home"

  SubstitutePath = distinct string  ##
  ## this is a path that /may/ have a $pathsub inside of it

proc `$`(path: SubstitutePath): string {.borrow.}

const
  readSubs = {SubType.low .. SubType.high}
  writeSubs =
    when writeNimbleDirPaths:
      readSubs
    else:
      {stCache, stConfig, stProjectDir, stLib, stNim, stHome}

template excludeAllNotes(config: ConfigRef; n: typed) =
  config.notes.excl n
  when compiles(config.mainPackageNotes):
    config.mainPackageNotes.excl n
  when compiles(config.foreignPackageNotes):
    config.foreignPackageNotes.excl n

template setDefaultsForConfig(result: ConfigRef) =
  # maybe we should turn off configuration hints for these reads
  when defined(debugPath):
    result.notes.incl hintPath
  elif not defined(debug):
    excludeAllNotes(result, hintConf)
  excludeAllNotes(result, hintLineTooLong)

proc parseConfigFile*(path: AbsoluteFile): Option[ConfigRef] =
  ## use the compiler to parse a nim.cfg without changing to its directory
  var
    cache = newIdentCache()
    config = newConfigRef()

  # define symbols such as, say, nimbabel;
  # this allows us to correctly parse conditions in nim.cfg(s)
  initDefines config.symbols

  setDefaultsForConfig config

  if readConfigFile(path, cache, config):
    result = some config

# a global that we set just once per invocation
var
  compilerPrefixDir: AbsoluteDir

proc findPrefixDir(): AbsoluteDir =
  ## determine the prefix directory for the current compiler
  if compilerPrefixDir.isEmpty:
    let compilerPath = findExe"nim"
    if compilerPath == "":
      raise newException OSError:
        "cannot find a nim compiler in the path"

    # start with the assumption that the compiler's parent directory works
    compilerPrefixDir = parentDir compilerPath.toAbsoluteFile

    if findExe"choosenim" == "":
      # if choosenim is not found, we are done
      result = compilerPrefixDir
    else:
      # if choosenim is in the path, we run the compiler to dump its config
      let compiler = runSomething(compilerPath,
                                  @["--hints:off", "--dump.format:json",
                                  "dump", "dummy"], {poDaemon})
      if not compiler.ok:
        warn "couldn't run the compiler to determine its location"
        warn "a choosenim-installed compiler might not work due to shims!"
      try:
        let js = parseJson compiler.output
        compilerPrefixDir = js["prefixdir"].getStr.toAbsoluteDir
      except JsonParsingError as e:
        warn "`nim dump` json parse error: " & e.msg
        raise
      except KeyError:
        warn "couldn't parse the prefix directory from `nim dump` output"
        warn "a choosenim-installed compiler might not work due to shims!"
  result = compilerPrefixDir

proc loadAllCfgs*(directory: string): ConfigRef =
  ## use the compiler to parse all the usual nim.cfgs;
  ## optionally change to the given (project?) directory first

  result = newConfigRef()

  # define symbols such as, say, nimbabel;
  # this allows us to correctly parse conditions in nim.cfg(s)
  initDefines result.symbols

  setDefaultsForConfig result

  # stuff the prefixDir so we load the compiler's config/nim.cfg
  # just like the compiler would if we were to invoke it directly
  result.prefixDir = findPrefixDir()

  withinDirectory directory:
    # stuff the current directory as the project path
    result.projectPath = AbsoluteDir getCurrentDir()

    # now follow the compiler process of loading the configs
    var cache = newIdentCache()

    # thanks, araq
    when (NimMajor, NimMinor) >= (1, 5):
      var idgen = IdGenerator()
      loadConfigs(NimCfg.RelativeFile, cache, result, idgen)
    else:
      loadConfigs(NimCfg.RelativeFile, cache, result)

  when defined(debugPath):
    debug "loaded", result.searchPaths.len, "search paths"
    debug "loaded", result.lazyPaths.len, "lazy paths"
    for path in result.lazyPaths.items:
      debug "\t", path
    for path in result.lazyPaths.items:
      if result.lazyPaths.count(path) > 1:
        raise newException(Defect, "duplicate lazy path: " & path.string)

proc createTemporaryFile*(prefix: string; suffix: string): AbsoluteFile =
  ## make a temp file in an appropriate spot, with a significant name;
  ## truncate any file unlucky enough to share the name we come up with.
  ## NOTE: if this is a problem for you, don't use this procedure.
  var temp = getTempDir()
  var fn = temp / "ups-" & $getCurrentProcessId() & "-" & prefix & suffix
  # ensure we can both read and write the temporary file
  open(fn, fmReadWrite).close
  # if we haven't thrown an exception by now, we're good to go
  result = fn.toAbsoluteFile

proc appendConfig*(path: AbsoluteFile; config: string): bool =
  # make a temp file in an appropriate spot, with a significant name
  let temp = createTemporaryFile(lastPathPart($path), dotNimble)
  debug "writing " & $temp
  # but remember to remove the temp file later
  try:
    block complete:
      try:
        # if there's already a config, we'll start there
        if fileExists $path:
          debug "copying $# to $#" % [ $path, $temp ]
          copyFile $path, $temp
      except Exception as e:
        warn "unable make a copy of $# to $#: $#" % [ $path, $temp, e.msg ]
        break complete

      block writing:
        # open our temp file for writing
        var writer = open($temp, fmAppend)
        try:
          # add our new content with a trailing newline;
          # the comment serves to ensure that `config` begins a new line
          writeLine(writer, "# added by ups:\n" & config)
        finally:
          # remember to close the temp file in any event
          close writer

      # make sure the compiler can parse our new config
      if parseConfigFile(temp).isSome:
        # copy the temp file over the original config
        try:
          debug "copying $# over $#" % [ $temp, $path ]
          copyFile $temp, $path
          # it worked, thank $deity
          result = true
        except Exception as e:
          warn "unable make a copy of $# to $#: $#" % [ $temp, $path, e.msg ]

  finally:
    debug "removing " & $temp
    if not tryRemoveFile $temp:
      warn "unable to remove temporary file `$#`" % [ $temp ]

proc parseProjectCfg*(input: AbsoluteFile): ProjectCfgParsed =
  ## parse a .cfg for any lines we are entitled to mess with
  result = ProjectCfgParsed(ok: false)
  if not fileExists $input:
    result.why = "config file `$#` doesn't exist" % [ $input ]
    return

  block success:
    var content = readFile $input
    if not content.endsWith("\n"):
      content.add "\n"
    var table = result.table    # for npeg reasons
    let peggy = peg "document":
      nl <- ?'\r' * '\n'
      white <- {'\t', ' '}
      equals <- *white * {'=', ':'} * *white
      assignment <- +(1 - equals)
      comment <- '#' * *(1 - nl)
      strvalue <- '"' * *(1 - '"') * '"'
      endofval <- white | comment | nl
      anyvalue <- +(1 - endofval)
      hyphens <- '-'[0..2]
      ending <- *white * ?comment * nl
      nimblekeys <- i"nimblePath" | i"clearNimblePath" | i"noNimblePath"
      otherkeys <- i"path" | i"p" | i"define" | i"d"
      keys <- nimblekeys | otherkeys
      strsetting <- hyphens * >keys * equals * >strvalue * ending:
        table[$1] = unescape($2)
      anysetting <- hyphens * >keys * equals * >anyvalue * ending:
        table[$1] = $2
      toggle <- hyphens * >keys * ending:
        table[$1] = "it's enabled, okay?"
      line <- strsetting | anysetting | toggle | (*(1 - nl) * nl)
      document <- *line * !1
    try:
      let parsed = match(peggy, content)
      result.ok = parsed.ok
      if not result.ok:
        result.why = repr parsed
    except Exception as e:
      result.why = "parse error in $#: $#" % [ $input, e.msg ]

template isStdlib*(config: ConfigRef; path: AbsoluteDir): bool =
  path.startsWith config.libpath

iterator likelySearch*(config: ConfigRef; libsToo: bool): AbsoluteDir =
  ## yield absolute directory paths likely added via --path
  for search in items(config.searchPaths):
    # we don't care about library paths
    if libsToo or not config.isStdLib(search):
      yield search

iterator likelySearch*(config: ConfigRef; repo: AbsoluteDir;
                       libsToo: bool): AbsoluteDir =
  ## yield absolute directory paths likely added via --path
  for search in likelySearch(config, libsToo = libsToo):
    # limit ourselves to the repo?
    when WhatHappensInVegas:
      if startsWith($search, $repo):
        yield search
    else:
      yield search

iterator likelyLazy*(config: ConfigRef; least = 0): AbsoluteDir =
  ## yield absolute directory paths likely added via --nimblePath
  # build a table of sightings of directories
  var popular = newCountTable[AbsoluteDir]()
  for search in config.lazyPaths.items:
    let
      parent = parentDir(search)
    when defined(debugPath):
      if search in popular:
        raise newException(Defect, "duplicate lazy path: " & $search)
    if search notin popular:
      popular.inc search
    if search != parent:               # silly: elide /
      if parent in popular:            # the parent has to have been added
        popular.inc parent

  # sort the table in descending order
  sort popular

  # yield the directories that exist
  for search, count in popular.pairs:
    # maybe we can ignore unpopular paths
    if least <= count:
      yield search

iterator likelyLazy*(config: ConfigRef; repo: AbsoluteDir;
                     least = 0): AbsoluteDir =
  ## yield absolute directory paths likely added via --nimblePath
  for search in config.likelyLazy(least = least):
    # limit ourselves to the repo?
    when WhatHappensInVegas:
      if startsWith($search, $repo):
        yield search
    else:
      yield search

iterator packagePaths*(config: ConfigRef; exists = true): AbsoluteDir =
  ## yield package paths from the configuration as absolute directories;
  ## if the exists flag is passed, then the path must also exist.
  ## this should closely mimic the compiler's search
  if config.isNil:
    raise newException Defect:
      "attempt to load search paths from nil config"

  var dedupe = initHashSet[AbsoluteDir]()

  # yield search paths first; these are more likely to be explicit
  for path in config.searchPaths:
    if not dedupe.containsOrIncl path:
      if not exists or path.dirExists:
        yield path

  for path in config.lazyPaths:
    if not containsOrIncl(dedupe, path):
      if not exists or dirExists(path):
        yield path

proc suggestNimbleDir*(config: ConfigRef;
                       local: AbsoluteDir ; global: AbsoluteDir): AbsoluteDir =
  ## come up with a useful nimbleDir based upon what we find in the
  ## current configuration, the location of the project, and the provided
  ## suggestions for local or global package directories
  block either:
    # if a local directory is suggested, see if we can confirm its use
    if not local.isEmpty and dirExists(local):
      for search in config.likelySearch(libsToo = false):
        if startsWith(search, local):
          # we've got a path statement pointing to a local path,
          # so let's assume that the suggested local path is legit
          result = local
          break either

    # nim 1.1.1 supports nimblePath storage in the config;
    # the last-added --nimblePath (first in the list) wins
    when (NimMajor, NimMinor) >= (1, 1):
      if len(config.nimblePaths) > 0:
        result = config.nimblePaths[0]
        break either

    # otherwise, try to pick a global .nimble directory based upon lazy paths
    for search in config.likelyLazy:
      if endsWith(search, PkgDir):
        result = parentDir(search) # ie. the parent of pkgs
      else:
        result = search            # doesn't look like pkgs... just use it
      break either

    # otherwise, try to make one up using the suggestion
    if global.isEmpty:
      raise newException(ValueError, "can't guess global {dotNimble} path")
    result = global
    break either

iterator pathSubsFor(config: ConfigRef; sub: SubType;
                     conf: AbsoluteDir): AbsoluteDir =
  ## a convenience to work around the compiler's broken pathSubs; the `conf`
  ## string represents the path to the "current" configuration file
  if sub notin {stNimbleDir, stNimblePath}:
    # if we don't need to handle a nimbledir or nimblepath, it's one and done
    yield config.pathSubs("$" & $sub, $conf).toAbsoluteDir
  else:
    when declaredInScope nimbleSubs:
      # use the later compiler's nimbleSubs()
      for path in config.nimbleSubs(&"${sub}"):
        yield path.toAbsoluteDir
    else:
      # earlier compilers don't have nimbleSubs(), so we'll emulate it;
      # we have to pick the first lazy path because that's what Nimble does
      for search in config.lazyPaths:
        if endsWith(search, PkgDir):
          yield parentDir(search)
        else:
          yield search
        break

iterator pathSubstitutions(config: ConfigRef; path: AbsoluteDir;
                           conf: AbsoluteDir; write: bool): SubstitutePath =
  ## compute the possible path substitions, including the original path
  var
    matchedPath = false
  when defined(debug):
    if not dirExists(conf):
      raise newException(Defect, "passed a config file and not its path")
  let
    conf = if dirExists(conf): conf else: parentDir(conf)
    substitutions = if write: writeSubs else: readSubs

  for sub in items(substitutions):
    for attempt in pathSubsFor(config, sub, conf):
      # ignore any empty substitutions
      if not attempt.isEmpty and not attempt.isRootDir:
        # note if any substitution matches the path
        if path == attempt:
          matchedPath = true
        if startsWith(path, attempt):
          # it's okay if paths that we yield here don't end in a DirSep
          yield replace($path, $attempt, "$" & $sub).SubstitutePath
  # if we never matched the path,
  if not matchedPath:
    # simply return the path we were provided
    yield path.SubstitutePath

proc bestPathSubstitution(config: ConfigRef; path: AbsoluteDir;
                          conf: AbsoluteDir): SubstitutePath =
  ## compute the best path substitution, if any
  block found:
    for sub in config.pathSubstitutions(path, conf, write = true):
      result = sub
      break found
    result = path.SubstitutePath

proc removePathImpl(config: ConfigRef; nimcfg: AbsoluteFile;
                    path: AbsoluteDir; parsed: ProjectCfgParsed): bool =
  ## perform a path substitution in a config file
  var content = readFile $nimcfg
  # iterate over the entries we parsed naively,
  for key, value in parsed.table.pairs:
    # skipping anything that isn't a path,
    if key.toLowerAscii in ["p", "path", "nimblepath"]:
      let normalized = normal $value
      # and perform substitutions to see if one might match the value
      # we are trying to remove; the write flag is false so that we'll
      # use any $nimbleDir substitutions available to us, if possible
      for sub in pathSubstitutions(config, path, parentDir nimcfg,
                                   write = false):
        if normalized == normal $sub:
          # perform a regexp substition to remove the entry from the content
          let
            regexp = re("(*ANYCRLF)(?i)(?s)(-{0,2}" & key.escapeRe &
                        "[:=]\"?" & value.escapeRe & "/?\"?)\\s*")
            swapped = replace(content, regexp, "")
          # if that didn't work, cry a bit and move on
          if swapped == content:
            notice "failed regex edit to remove path `$#`" % [ $value ]
          else:
            # make sure we search the new content next time through the loop
            content = swapped
            result = true
          # keep performing more substitutions...

  # finally, write the edited content
  writeFile(nimcfg, content)

proc removeSearchPath*(config: ConfigRef; nimcfg: AbsoluteFile;
                       path: AbsoluteDir): bool =
  ## try to remove a path from a nim.cfg; true if it was
  ## successful and false if any error prevented success

  if fileExists nimcfg:
    # make sure we can parse the configuration with the compiler
    if parseConfigFile(nimcfg).isNone:
      error "the compiler couldn't parse $#" % [ $nimcfg ]
      return false

    # make sure we can parse the configuration using our "naive" npeg parser
    let parsed = parseProjectCfg nimcfg
    if not parsed.ok:
      error "could not parse $# naïvely:" % [ $nimcfg ]
      error parsed.why
    else:
      # this is the meat of the operation; go forth and conquer
      result = removePathImpl(config, nimcfg, path, parsed)

proc addSearchPath*(config: ConfigRef; nimcfg: AbsoluteFile;
                    path: AbsoluteDir): bool =
  ## add the given path to the given config file, using the compiler's
  ## configuration as input to determine the best path substitution
  let best = config.bestPathSubstitution(path, parentDir nimcfg)
  result = appendConfig(nimcfg, """--path="$#"""" % [ $best ])

proc excludeSearchPath*(config: ConfigRef; nimcfg: AbsoluteFile;
                        path: AbsoluteDir): bool =
  ## add an exclusion for the given path to the given config file, using the
  ## compiler's configuration as input to determine the best path substitution
  let best = bestPathSubstitution(config, path, parentDir nimcfg)
  result = appendConfig(nimcfg, """--excludePath="$#"""" % [ $best ])

iterator extantSearchPaths*(config: ConfigRef; least = 0): AbsoluteDir =
  ## yield existing search paths from the configuration as /-terminated strings;
  ## this will yield library paths and nimblePaths with at least `least` uses
  if config == nil:
    raise newException(Defect, "attempt to load search paths from nil config")
  # path statements
  for path in likelySearch(config, libsToo = true):
    if dirExists path:
      yield path
  # nimblePath statements
  for path in likelyLazy(config, least = least):
    if dirExists path:
      yield path

proc isEmpty(js: JsonNode): bool = js.isNil or js.kind == JNull

proc addLockerRoom*(js: var JsonNode; name: string; room: JsonNode) =
  ## add the named lockfile (in json form) to the configuration file
  if js.isEmpty:
    js = newJObject()
  if $LockerRooms notin js:
    js[$LockerRooms] = newJObject()
  js[$LockerRooms][name] = room

proc getAllLockerRooms*(js: JsonNode): JsonNode =
  ## retrieve a JObject holding all lockfiles in the configuration file
  block found:
    if not js.isEmpty and js.kind == JObject:
      if $LockerRooms in js:
        result = js[$LockerRooms]
        break
    result = newJObject()

proc getLockerRoom*(js: JsonNode; name: string): JsonNode =
  ## retrieve the named lockfile (or JNull) from the configuration
  let rooms = getAllLockerRooms js
  result =
    if name in rooms:
      rooms[name]
    else:
      newJNull()
