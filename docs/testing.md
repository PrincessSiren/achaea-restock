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
  target typed with either spelling lands on the same key.
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
- **The cure pairs, against the shape of `HELP 13.7.1`.** 21 rows, every
  mineral once, every herb once except skullcap, every herb one a listing has
  shown under Herbs, and no mineral filed under some other heading. The
  scroll is not in this repository, so the harness cannot read it; the shape
  is what it holds instead. Then the arithmetic on the October listing's own
  numbers: four cures under 500, a mineral making up a short herb, and
  skullcap counting toward both its pairs.
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
