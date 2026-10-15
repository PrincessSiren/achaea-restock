# Cure pairs: a herb and a mineral, counted together

`restock cures 500` reports every cure where the herb and the mineral that does
the same thing add up to less than 500. 300 ash and 300 stannum are 600 sanity
cures, not two items short of 500 each.

## Where the pairs come from

`HELP 13.7.1 Curatives and What They Cure or Cause` lists the herbs and then the
minerals, one line each. Every mineral's line is **word for word** one herb's
line:

```
Kelp          Cure for weakened muscles or lower general fitness.
...
Aurum         Cure for weakened muscles or lower general fitness.
```

That identity is the whole pairing. No row in `M.CURES` was matched because two
things sounded alike, and the scroll was paired by machine, not by eye, before
the table was written. It comes out clean: 21 minerals, each the twin of exactly
one herb.

**Skullcap is in two rows**, because the scroll gives it two lines and they are
two cures: eaten it gives deathsight, as azurite does; smoked it makes the
anti-weapon field, as malachite does. One stock of skullcap serves either, so it
counts in full toward both.

**Burdock is in the rift and not in 13.7.1**, so it pairs with nothing and the
cure report does not mention it.

## Why counting both is right

Server-side curing eats one kind or the other. `HELP 13.7.8` and the `CURING`
menu:

```
CURING TRANSMUTATION ON|OFF - Use Transmutation cures (on) or Concoctions (off).

CURING FALLBACK ON|OFF - Fall back to alternative curing methods if you do not
  have your selected type.
```

With fallback on, running out of ash means curing eats stannum instead, so
the pair is what you can actually cure with. **With fallback off, it is not**:
only one half is ever eaten, and an item target on that half
(`restock target ash 500`) is the better question to ask. `CURING STATUS` shows
both settings, as `Curing Method:` (`Concoctions` is herbs) and
`Fallback Curing:`.

## What it tells you to buy

Either half refills a pair, so by default the report only says how many. Which
half you *should* buy depends on which one curing eats first, which is that
`CURING TRANSMUTATION` setting, and nothing over GMCP says what it is. So it is
yours to state:

```
restock cures herbs       buy 251 cohosh
restock cures minerals    buy 251 gypsum
restock cures either      buy 251
```

## Rift names are not always the scroll's

The rift calls four herbs something shorter than 13.7.1 does:

| rift | 13.7.1 | how it is known |
| --- | --- | --- |
| `ash` | Prickly Ash | the scroll's own cross-reference, "Ash See Prickly Ash" |
| `elm` | Slippery Elm | "Elm See Slippery Elm" |
| `irid` | Irid Moss | "Moss See Irid Moss"; `lumic moss` is a reagent, not this |
| `pear` | Prickly Pear | elimination: it is under Herbs, and no other herb in 13.7.1 has the word |

Every herb in `M.CURES` is one a `RIFT` listing has shown under Herbs, and the
harness holds it to that.

**Twelve of the minerals have never appeared in a listing.** Nobody here has held
any stannum, arsenic, cuprum, magnesium, gypsum, dolomite, antimony, plumbum,
calamine, argentum, quicksilver or azurite, so the name used for each is the
scroll's, lowercased. Every mineral that *has* been listed so far matches its
scroll name like that, but that is no proof for the others. The report puts a
`?` after them, and `restock diag` lists them. If you hold some and the report
still says 0, the rift uses a different name, and `restock diag` will show it
as an item with no heading.
