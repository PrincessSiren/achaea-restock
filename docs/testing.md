# Testing

```bash
luajit test_harness.lua
```

`test_harness.lua` stubs enough of Mudlet to run the package under plain
luajit — `cecho`, `sendGMCP`, the two handler registrars, and a `gmcp` table —
and then **raises the real events**, so `M.onList` and `M.onChange` are reached
the way Mudlet would reach them rather than being called directly.

Mudlet embeds Lua 5.1 and `luajit` is that exact dialect. A 5.4 parser accepts
things Mudlet rejects, so check with `luajit` rather than `lua`.

## What it covers

- **The transcription.** 56 names, nine headings, the per-heading counts the
  capture printed, and every heading in `CATEGORY_ORDER` actually used. Two-word
  names (`myrrh gum`, `wyrm tongue`, `blue ink`) are checked by name, being the
  easy thing to lose.
- **The hole in `HELP 7.14`.** `M.CAP.Minerals` must still be `nil`. This is the
  point of the suite rather than a side effect: see
  [what-it-knows.md](what-it-knows.md).
- **Both GMCP shapes.** `amount` as a number and as a string, since nobody here
  has seen which Achaea sends and `IRE.Target` is on record sending `"-1"`.
- **That a `List` replaces rather than merges**, so an item that stopped being
  listed is gone rather than remembered at its last value.
- **The arithmetic** — shortfall ordering, `buy = target - have`, slack, item
  targets beating heading targets.
- **An unknown name surfacing** under `Unsorted` and being named by `diag`
  rather than vanishing or being guessed into a heading.
- **An empty rift**, which is the state at every login until the first frame
  lands, so every report has to survive it.
- **A recompile replacing its handlers** rather than registering a second set
  over the live one. Mudlet clears `mAnonymousEventHandlerFunctions` only in
  `Host::resetProfile`, so a package keeping ids in a file-local doubles every
  event on every reload — which is why `M.state` hangs off the module table.
- **The committed `.xml` wiring up every function the aliases name**, and
  reaching every heading the Lua knows. A heading added to one and not the other
  is a command that silently does nothing.

## What it cannot cover

None of it runs inside Mudlet, and none of it talks to Achaea.

The GMCP fixtures are **modelled on Orion's own `IRE.Rift` handlers**, not on a
capture of Achaea sending those frames. That is the best evidence available
without a live profile, and it is not the same thing as evidence. A green run
means the logic and the packaging hold; it does not mean the frames look like
that.

Treat any change to the GMCP handling as unverified until it has run in a real
profile.
