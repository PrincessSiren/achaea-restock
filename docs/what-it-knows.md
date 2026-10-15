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

## Minerals: a reading, not a quotation

The capacity table caps "each type of herb, commodity, reagent, or crystal" and
never says *mineral*. The scroll's own "What Goes In The Rift?" paragraph, four
paragraphs earlier, lists "Herbs, minerals, inks, crystals, commodities,
shipcommodities and common fluids", naming minerals and crystals separately.

Through 0.1.x `M.CAP.Minerals` was `nil` for that reason, and the harness
failed if it stopped being `nil`. **Since 0.2.0 it is 2500**, on the owner's
reading that 7.14's "crystal" means the minerals, the edible stones `RIFT` lists
under that heading. That is a reading of the scroll by someone who plays the
game, not a capture of the game refusing the 2501st, and the package says so:
`M.CAP_NOTE.Minerals` is printed beside the cap, and the harness fails if the
note goes.

The listings agree as far as they reach. Ferrum sat at exactly 1000 in the
first, and potash at 2351 and then 2349 in the second, so whatever the cap is,
it is above 2350. A capture of the game refusing a deposit would settle it for
good.

## `M.GMCP_NAMES`: the same item, two names

GMCP and the `RIFT` listing do not always agree on what an item is called. The
first live run turned up nine items that `restock diag` could not place, each
held at exactly the amount a listing taken minutes earlier printed under another
name:

| GMCP | `RIFT` |
| --- | --- |
| `blueink`, `goldink`, `greenink`, `purpleink`, `redink`, `yellowink` | `blue ink` … `yellow ink` |
| `myrrh` | `myrrh gum` |
| `goldbar` | `gold` |
| `silver` | `silverore` |

The inks just lose a space, but the metals do not follow any rule.
GMCP's `silver` is the 34 of `silverore`, not the 2466 of `silver bar`. So the
table is a list of observed pairs and nothing more, and it is not derived by
rule.

`absorb()` translates as each frame lands. From there on, everything uses the
name `RIFT` prints: headings, caps, the cure pairs, and the targets you type,
which accept either spelling. Before this, the inks went uncapped and
`myrrh gum` read as zero in its cure pair.

**The listing held 72 items and GMCP 70.** So two items in the listing reached
GMCP under no name at all, or under one that was taken for something else.
Which two is not known yet. A `restock all` beside a `RIFT` listing would show
it.
