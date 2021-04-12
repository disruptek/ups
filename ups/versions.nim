import std/hashes
import std/strutils
import std/tables
import std/options
import std/logging

import npeg

import ups/spec

type
  Version* = object
    major*: VersionField
    minor*: VersionField
    patch*: VersionField
  VersionField* = uint   # could it change? 🤔
  VersionIndex* = range[0 .. 2]

  VersionMask* = object ##
    ## a version mask may apply to any or all fields
    major*: VersionMaskField
    minor*: VersionMaskField
    patch*: VersionMaskField
  VersionMaskField* = Option[VersionField]

  Operator* = enum ##
    ## operators affect the bearing of a release
    Tag     = "#"
    Wild    = "*"
    Tilde   = "~"
    Caret   = "^"
    Equal   = "=="
    AtLeast = ">="
    Over    = ">"
    Under   = "<"
    NotMore = "<="

  Release* = object
    ## the specification of a version, release, or mask
    case kind*: Operator
    of Tag:
      reference*: string
    of Wild, Caret, Tilde:
      accepts*: VersionMask
    of Equal, AtLeast, Over, Under, NotMore:
      version*: Version

converter toVersion(t: (int|uint, int|uint, int|uint)): Version =
  ## internal converter to simplify expressions
  Version(major: t[0], minor: t[1], patch: t[2])

const
  invalidVersion = toVersion (0'u, 0'u, 0'u)  ## for comparison purposes
  Wildlings* = {Wild, Caret, Tilde}           ## mavericks of the version world

proc `<`*(a, b: Version): bool =
  (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)

proc `==`*(a, b: Version): bool =
  (a.major, a.minor, a.patch) == (b.major, b.minor, b.patch)

proc hash*(v: Version): Hash =
  hash (v.major, v.minor, v.patch)

proc `$`*(v: Version): string =
  result.add $v.major
  result.add '.'
  result.add $v.minor
  result.add '.'
  result.add $v.patch

proc bumpVersion*(ver: Version; major, minor, patch = false): Option[Version] =
  ## increment the version by the specified metric;
  ## returns none() if no bump occurred
  if major:
    result = some: Version (ver.major + 1'u, 0'u, 0'u)
  elif minor:
    result = some: Version (ver.major, ver.minor + 1'u, 0'u)
  elif patch:
    result = some: Version (ver.major, ver.minor, ver.patch + 1'u)

template starOrDigits(s: string): VersionMaskField =
  ## parse a star or digit as in a version mask
  if s == "*":
    # VersionMaskField is Option[VersionField]
    none: VersionField
  else:
    some: parseUInt s

proc parseDottedVersion*(input: string): Option[Version] =
  ## try to parse `1.2.3` into a `Version`; we'll ignore any
  ## extra values, but the first three must parse
  let dotted = split(input, '.')
  if dotted.len >= 3:
    try:
      let parsed = Version(major: dotted[0].parseUInt,
                           minor: dotted[1].parseUInt,
                           patch: dotted[2].parseUInt)
      if parsed > invalidVersion:
        result = some parsed
    except ValueError:
      discard

proc newVersionMask(input: string): VersionMask =
  ## try to parse `1.2` or `1.2.*` into a `VersionMask`
  let dotted = split(input, '.')
  if dotted.len > 0:
    result.major = dotted[0].starOrDigits
  if dotted.len > 1:
    result.minor = dotted[1].starOrDigits
  if dotted.len > 2:
    result.patch = dotted[2].starOrDigits

proc isValid*(v: Version): bool =
  ## true if the version seems legit
  (v.major, v.minor, v.patch) != invalidVersion

proc isValid*(release: Release): bool =
  ## true if the release seems plausible
  const sensible = @[
    [ on, off, off ],
    [ on,  on, off ],
    [ on,  on,  on ],
  ]
  case release.kind
  of Tag:
    result = release.reference != ""
  of Wild, Caret, Tilde:
    let pattern = [release.accepts.major.isSome,
                   release.accepts.minor.isSome,
                   release.accepts.patch.isSome]
    result = pattern in sensible
    # let's say that *.*.* is valid; it could be useful
    if release.kind == Wild:
      result = result or pattern == [off, off, off]
  else:
    result = release.version.isValid

proc newRelease*(version: Version): Release =
  ## create a new release using a version
  result = Release(kind: Equal, version: version)

proc newRelease*(reference: string; operator = Equal): Release

proc parseVersionLoosely*(content: string): Option[Release] =
  ## a very relaxed parser for versions found in tags, etc.
  ## only valid releases are emitted, however
  var release: Release
  let peggy = peg "document":
    ver <- +Digit * ('.' * +Digit)[0..2]
    record <- >ver * (!Digit | !1):
      if not release.isValid:
        release = newRelease($1, operator = Equal)
    document <- +(record | 1) * !1
  try:
    let parsed = peggy.match(content)
    if parsed.ok and release.isValid:
      result = some: release
  except Exception as e:
    warn "parse error in `$1`: $2" % [ content, e.msg ]

proc newRelease*(reference: string; operator = Equal): Release =
  ## parse a version, mask, or tag with an operator hint from the requirement
  if reference.startsWith("#") or operator == Tag:
    result = Release(kind: Tag, reference: reference)
    removePrefix(result.reference, {'#'})
  elif reference in ["", "any version"]:
    result = Release(kind: Wild, accepts: newVersionMask "*")
  elif "*" in reference:
    result = Release(kind: Wild, accepts: newVersionMask reference)
  elif operator in Wildlings:
    case operator
    of Wildlings:
      result = Release(kind: operator, accepts: newVersionMask reference)
    else:
      raise newException(Defect, "inconceivable!")
  elif count(reference, '.') < 2:
    result = Release(kind: Wild, accepts: newVersionMask reference)
  else:
    let parsed = parseDottedVersion reference
    if parsed.isSome:
      result = newRelease(get parsed)
    else:
      raise newException ValueError:
        "unable to parse release version `" & reference & "`"

proc `$`*(field: VersionMaskField): string =
  if field.isNone:
    result = "*"
  else:
    result = $field.get

proc `$`*(mask: VersionMask): string =
  result = $mask.major
  result &= "." & $mask.minor
  result &= "." & $mask.patch

proc omitStars*(mask: VersionMask): string =
  result = $mask.major
  if mask.minor.isSome:
    result &= "." & $mask.minor
  if mask.patch.isSome:
    result &= "." & $mask.patch

proc `$`*(spec: Release): string =
  case spec.kind
  of Tag:
    result = $spec.kind & $spec.reference
  of Equal, AtLeast, Over, Under, NotMore:
    result = $spec.version
  of Wild, Caret, Tilde:
    result = spec.accepts.omitStars

proc `==`*(a, b: VersionMaskField): bool =
  result = a.isNone == b.isNone
  if result and a.isSome:
    result = a.get == b.get

proc `<`*(a, b: VersionMaskField): bool =
  result = a.isNone == b.isNone
  if result and a.isSome:
    result = a.get < b.get

proc `==`*(a, b: VersionMask): bool =
  result = a.major == b.major
  result = result and a.minor == b.minor
  result = result and a.patch == b.patch

proc `==`*(a, b: Release): bool =
  if a.kind == b.kind and a.isValid and b.isValid:
    case a.kind
    of Tag:
      result = a.reference == b.reference
    of Wild, Caret, Tilde:
      result = a.accepts == b.accepts
    else:
      result = a.version == b.version

proc `<`*(a, b: Release): bool =
  if a.kind == b.kind and a.isValid and b.isValid:
    case a.kind
    of Tag:
      result = a.reference < b.reference
    of Equal:
      result = a.version < b.version
    else:
      raise newException(ValueError, "inconceivable!")

proc `<=`*(a, b: Release): bool =
  result = a == b or a < b

proc `==`*(a: VersionMask; b: Version): bool =
  if a.major.isSome and a.major.get == b.major:
    if a.minor.isSome and a.minor.get == b.minor:
      if a.patch.isSome and a.patch.get == b.patch:
        result = true

proc acceptable*(mask: VersionMaskField; op: Operator;
                 value: VersionField): bool =
  ## true if the versionfield value passes the mask
  case op
  of Wild:
    result = mask.isNone or value == mask.get
  of Caret:
    result = mask.isNone
    result = result or (value >= mask.get and mask.get > 0'u)
    result = result or (value == 0 and mask.get == 0)
  of Tilde:
    result = mask.isNone or value >= mask.get
  else:
    raise newException(Defect, "inconceivable!")

proc at*[T: Version | VersionMask](version: T; index: VersionIndex): auto =
  ## like [int] but clashless
  case index
  of 0: result = version.major
  of 1: result = version.minor
  of 2: result = version.patch

proc `[]=`*(mask: var VersionMask;
            index: VersionIndex; value: VersionMaskField) =
  case index
  of 0: mask.major = value
  of 1: mask.minor = value
  of 2: mask.patch = value

iterator items*[T: Version | VersionMask](version: T): auto =
  for i in VersionIndex.low .. VersionIndex.high:
    yield version.at(i)

iterator pairs*[T: Version | VersionMask](version: T): auto =
  for i in VersionIndex.low .. VersionIndex.high:
    yield (index: i, field: version.at(i))

proc isSpecific*(release: Release): bool =
  ## if the version/match specifies a full X.Y.Z version
  if release.kind in {Equal, AtLeast, NotMore} and release.isValid:
    result = true
  elif release.kind in Wildlings and release.accepts.patch.isSome:
    result = true
  else:
    result = false

proc specifically*(release: Release): Version =
  ## a full X.Y.Z version the release will match
  if release.isSpecific:
    if release.kind in Wildlings:
      result = Version(major: release.accepts.major.get,
                       minor: release.accepts.minor.get,
                       patch: release.accepts.patch.get)
    else:
      result = release.version
  else:
    raise newException Defect:
      "release `$#` is not specific" % [ $release ]

proc effectively*(mask: VersionMask): Version =
  ## replace * with 0 in wildcard masks
  if mask.major.isNone:
    result = (0'u, 0'u, 0'u)
  elif mask.minor.isNone:
    result = (mask.major.get, 0'u, 0'u)
  elif mask.patch.isNone:
    result = (mask.major.get, mask.minor.get, 0'u)
  else:
    result = (mask.major.get, mask.minor.get, mask.patch.get)

proc effectively*(release: Release): Version =
  ## convert a release to a version for rough comparisons
  case release.kind
  of Tag:
    let parsed = parseVersionLoosely(release.reference)
    if parsed.isNone:
      result = (0'u, 0'u, 0'u)
    elif parsed.get.kind == Tag:
      raise newException(Defect, "inconceivable!")
    result = effectively parsed.get
  of Wildlings:
    result = effectively release.accepts
  of Equal:
    result = release.version
  else:
    raise newException(Defect, "not implemented")

proc hash*(field: VersionMaskField): Hash =
  ## help hash version masks
  var h: Hash = 0
  if field.isNone:
    h = h !& hash('*')
  else:
    h = h !& hash(get field)
  result = !$h

proc hash*(mask: VersionMask): Hash =
  ## uniquely identify a version mask
  var h: Hash = 0
  h = h !& hash(mask.major)
  h = h !& hash(mask.minor)
  h = h !& hash(mask.patch)
  result = !$h

proc hash*(release: Release): Hash =
  ## uniquely identify a release
  var h: Hash = 0
  h = h !& release.kind.hash
  case release.kind
  of Tag:
    h = h !& release.reference.hash
  of Wild, Tilde, Caret:
    h = h !& release.accepts.hash
  of Equal, AtLeast, Over, Under, NotMore:
    h = h !& release.version.hash
  result = !$h

proc toMask*(version: Version): VersionMask =
  ## populate a versionmask with values from a version
  for i, field in version.pairs:
    result[i] = field.some

iterator likelyTags*(version: Version): string =
  ## produce tags with/without silly `v` prefixes
  let v = $version
  yield        v
  yield "v"  & v
  yield "V"  & v
  yield "v." & v
  yield "V." & v

iterator semanticVersionStrings*(mask: VersionMask): string =
  ## emit 3, 3.1, 3.1.4 (if possible)
  var last: string
  if mask.major.isSome:
    last =
      $mask.major.get
    yield last
    if mask.minor.isSome:
      last.add:
        "." & $mask.minor.get
      yield last
      if mask.patch.isSome:
        last.add:
          "." & $mask.patch.get
        yield last

iterator semanticVersionStrings*(version: Version): string =
  ## emit 3, 3.1, 3.1.4
  yield $version.major
  yield $version.major & "." & $version.minor
  yield $version.major & "." & $version.minor & "." & $version.patch
