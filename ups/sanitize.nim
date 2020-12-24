import std/options
import std/strutils

const
  nimIdentStartChars = {'a'..'z', 'A'..'Z'}  # no '_'

proc isValidNimIdentifier*(s: string): bool =
  ## true for strings that are valid identifier names
  if s == "_":     # special case
    return true
  if s.len > 0 and s[0] in nimIdentStartChars:
    # cannot start or end with '_'
    if '_' in {s[0], s[^1]}:
      return false
    for i, c in s.pairs:
      # all characters must be valid
      if c notin IdentChars:
        return false
      # two _ is too many
      if i > 0:
        if {'_'} == {c, s[i-1]}:
          return false
    result = true

template cappableAdd(s: var string; c: char) =
  ## add a char to a string, perhaps capitalizing it
  if s.len > 0 and s[^1] == '_':
    s.add c.toUpperAscii
  else:
    s.add c

proc sanitizeIdentifier*(name: string; capsOkay=false): Option[string] =
  ## convert any string to a valid nim identifier
  if name.len == 0:
    return none(string)
  elif name == "_":      # special case
    return some(name)
  var id = ""
  for c in name.items:
    if c in nimIdentStartChars:
      id.cappableAdd c
    elif c in {'0'..'9'} and id.len > 0:
      id.cappableAdd c
    else:
      # helps differentiate words case-insensitively
      id.add '_'
  while "__" in id:
    id = id.replace("__", "_")
  if id.len > 1:
    id.removeSuffix {'_'}
    id.removePrefix {'_'}
  # if we need to lowercase the first letter, we'll lowercase
  # until we hit a word boundary (_, digit, or lowercase char)
  if not capsOkay and id.len > 0 and id[0].isUpperAscii:
    for c in id.mitems:
      let lower = c.toLowerAscii
      if c in {'_', lower}:
        break
      else:
        c = lower

  if id.isValidNimIdentifier:
    result = id.some
