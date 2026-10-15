# What it knows, and what it does not

Two tables carry everything this package claims about Achaea. Both come from
captures, and both have holes that are recorded rather than filled. A third,
`M.CURES`, is in [cure-pairs.md](cure-pairs.md).

## `M.CATEGORY` — which heading a name sits under

GMCP sends `{ name, amount }` and **no category**. There is no second frame
that supplies one. So the only place the grouping exists is the `RIFT` listing
itself:

```
Herbs
[  404] ash                    [  398] bayberry               [  195] bellwort
...
Minerals
[   85] bisemutum              [  378] calcite                [ 1000] ferrum
```

`M.CATEGORY` is a transcription of two such listings — 75 names under ten
headings, captured 18th September and 15th October 2026. Neither is a superset
of the other: kelp and irid were held the first time and not the second, and
were simply not listed. That is also the best evidence on file that an item at
zero drops out of the listing, which is why a `List` replaces rather than
merges. `M.CATEGORY_ORDER` is the game's own
order, which the reports walk rather than sorting, so the output reads the way
`RIFT` does.

**It is a lower bound, and always will be.** A listing shows what one character
was carrying, so a herb nobody has ever held is not in it. That is why an
unrecognised name goes under `Unsorted` and is named by `restock diag`, rather
than being sorted into whichever heading looks right. Extending the table means
capturing a listing that shows the heading — type `RIFT` in game — not
recalling one.

`Reagent` is worth one note: the first listing printed it over one row and the
second printed `Reagents` over two, so the heading agrees with its count. The
key stays `Reagent`, so a target saved by 0.1.x still applies, and
`restock reagent` and `restock reagents` both work.

`Misc` appeared in the second listing, over one row (`gleam`). `HELP 7.14`
states no cap for it.

## `M.CAP` — what the rift will hold

`HELP 7.14 The Rift` prints a capacity table, which is unusual for a `HELP`
file and is the reason this package can talk about ceilings at all without
inventing a number:

```
   750 of each type of ink
  1000 of each type of cooking ingredient
  2500 of each type of herb, commodity, reagent, or crystal.
  2000 sips of health and mana
  1000 sips of most curatives, venoms, and other fluids.
   500 of each ship commodities
```

Health and mana are named individually at 2000 against the 1000 every other
fluid gets, so they are `M.ITEM_CAP` entries rather than a heading's cap. The
captured listing agrees: every fluid in it is at or under 1000 except health at
1308 and mana at 1847.

Where the scroll hedges, `M.CAP_NOTE` carries the hedge rather than dropping
it — "most curatives, venoms, and other fluids" is not the same as *all* of
them.

## The hole: minerals

**`M.CAP.Minerals` is `nil` on purpose, and the harness fails if it stops
being `nil`.**

The capacity table caps "each type of herb, commodity, reagent, or crystal" and
never says *mineral*. The scroll's own "What Goes In The Rift?" paragraph, four
paragraphs earlier, lists "Herbs, minerals, inks, crystals, commodities,
shipcommodities and common fluids" — minerals and crystals as separate things.
So either minerals *are* the capacity table's crystals, at 2500, or their cap
is simply unstated. One scroll cannot tell you which.

2500 is the obvious guess and may well be right, which is precisely why it is
not in the table. A cap that is wrong by being too high is a `restock` that
cheerfully tells you to buy ore the rift will refuse.

The captures narrow it without closing it: ferrum sat at exactly 1000 in the
first, and potash at 2351 in the second. So if minerals have a cap it is above
2350, which rules out the fluids' 1000 and is consistent with 2500, and says
nothing more.

**To close it**, put minerals into the rift until the game refuses, and capture
what it says. Then change `M.CAP` and the assertion in `test_harness.lua` in
the same commit.
