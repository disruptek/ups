import testes

import ups/sanitize

testes:

  block:
    ## is valid nim identifier?
    for bad in ["", "__", "_a", "_a_", "a_", "0a", "0_a", "0_9"]:
      check not bad.isValidNimIdentifier
    for good in ["_", "a", "A", "aA", "a_A", "A_9", "A9"]:
      check good.isValidNimIdentifier
