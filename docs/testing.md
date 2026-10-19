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

- **The transcription.** 75 names, ten headings, the per-heading counts the
  two captures printed, and every heading in `CATEGORY_ORDER` actually used. Two-word
  names (`myrrh gum`, `wyrm tongue`, `blue ink`) are checked by name, being the
  easy thing to lose.
- **`HELP 7.14`'s caps**, including minerals at the "crystal" 2500. That row
  is a reading rather than a quotation, so the harness also fails if
  `M.CAP_NOTE.Minerals` stops saying so: see
  [what-it-knows.md](what-it-knows.md).
- **GMCP's names.** The nine names a live `restock diag` could not place, at
  the amounts it printed, held against the listing's amounts under the names
  `M.GMCP_NAMES` gives. Each arrives under the listed name and takes that
  name's heading and cap. GMCP's `myrrh` counts toward its cure pair, and a
  target typed with either spelling lands on the same key. The one predicted
  row, `moss → irid` from `HELP 18.5`, is counted separately so that a second
  one cannot slip in. When `moss` arrives it lands on irid, and `diag` reports
  it seen.
- **Reports ask first.** With a stub timer, a report sends
  `IRE.Rift.Request`, waits, and runs against the `List` that answers. It runs
  once, cancels its timeout, and runs anyway, saying so, if nothing answers.
  Two asks leave one report waiting. `stop` drops it, and setting a threshold
  does not wait at all.
- **What GMCP does not send.** An item target on something at zero is reported
  short by the whole target. A heading target is not, since it names no items.
  The two never-sent items are never reported as none held, a target on one
  warns, and `diag` names them, and says so if one ever arrives.
- **Both GMCP shapes.** `amount` as a number and as a string, since nobody here
  has seen which Achaea sends and `IRE.Target` is on record sending `"-1"`.
- **That a `List` replaces rather than merges**, so an item that stopped being
  listed is gone rather than remembered at its last value.
- **The arithmetic** — shortfall ordering, `buy = target - have`, slack, item
  targets beating heading targets.
- **The distance to the cap**, on short rows and on every `restock all` row:
  health and mana against their own 2000, another fluid against 1000, a row
  at the cap reading `at cap`, one above it said as such rather than as a
  negative, Misc printing no cap column, and a stocked row in `restock
  <heading>` lining its cap up under a short one's.
- **The cure pairs, against the shape of `HELP 13.7.1`.** 21 rows, every
  mineral once, every herb once except skullcap, every herb one a listing has
  shown under Herbs, and no mineral filed under some other heading. The
  scroll is not in this repository, so the harness cannot read it; the shape
  is what it holds instead. Then the arithmetic on the October listing's own
  numbers: four cures under 500, a mineral making up a short herb, and
  skullcap counting toward both its pairs.
- **Settings round-tripping through the file**, every key `save` writes read
  back by `load`, with a hand-edited `cureBuy` or `cureLow` that no command
  could have set falling back to its default. Also that an item target on a
  name nothing has shown is called out as a possible typo when it is set,
  since it would otherwise read as none held for ever.
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
