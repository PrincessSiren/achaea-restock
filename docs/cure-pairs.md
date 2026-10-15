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
| `irid` | Irid Moss | "Moss See Irid Moss"; `lumic moss` is a reagent, not this. GMCP probably sends `moss`, below |
| `pear` | Prickly Pear | elimination: it is under Herbs, and no other herb in 13.7.1 has the word |

Every herb in `M.CURES` is one a `RIFT` listing has shown under Herbs, and the
harness holds it to that. GMCP does not always use those names: it sends
`myrrh` for myrrh gum, and `M.GMCP_NAMES` maps it back before the pair is
counted.

**The minerals' names are the game's own short names.** `HELP 18.5.1 Minerals`
lists every mineral as a short name and a description, `Stannum` for "a stannum
flake", and its twenty-one are exactly the twenty-one here. When the pairs were
first written, twelve of them had never been seen in the rift, so their names
were the scroll's, lowercased, and the report marked them with a `?`. 18.5.1
took the guesswork out. Each of the ten minerals held so far reached GMCP
under its short name, including stannum, which was bought on 15th October
2026 to test exactly that. So the `?` is gone, and the harness holds `M.CURES`
to the short-name list both ways.

That is not the same as every name lining up everywhere. `HELP 18.5 Plants and
Herbs` gives the herbs' short names too, and two differ from what the listing
prints: `Myrrh` ("a ball of myrrh gum") where the listing says "myrrh gum",
and `Moss` ("some irid moss") where it says "irid". GMCP has been seen sending
`myrrh`, the short name. Irid has not been held since the package went live,
so `moss → irid` is in `M.GMCP_NAMES` as a prediction, and `restock diag`
says whether it has been seen. If GMCP sends `irid` after all, the row
never fires.
