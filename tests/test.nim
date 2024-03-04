import std/os

import pkg/balls

import ups

suite "sanitizer":

  block:
    ## is valid nim identifier?
    for bad in ["", "__", "_a", "_a_", "a_", "0a", "0_a", "0_9"]:
      check not bad.isValidNimIdentifier
    for good in ["_", "a", "A", "aA", "a_A", "A_9", "A9"]:
      check good.isValidNimIdentifier

    check "identifiers":
      NimIdentifier"a" != NimIdentifier"A"
      NimIdentifier"Aa" != NimIdentifier"aa"
      NimIdentifier"aA" == NimIdentifier"aa"
      NimIdentifier"a_A" == NimIdentifier"aA"
      NimIdentifier"A_a" == NimIdentifier"AA"

suite "paths":

  block:
    ## normalizePathEnd consistency between nim-1.0, nim-1.2+
    when not defined(posix):
      skip"we test this logic on posix only"
    else:
      # tests from std/os around line 140
      assert normalizePathEnd("/lib//.//", trailingSep = true) == "/lib/"
      assert normalizePathEnd("lib/./.", trailingSep = false) == "lib"
      assert normalizePathEnd(".//./.", trailingSep = false) == "."
      assert normalizePathEnd("", trailingSep = true) == "" # not / !
      assert normalizePathEnd("/", trailingSep = false) == "/" # not "" !
