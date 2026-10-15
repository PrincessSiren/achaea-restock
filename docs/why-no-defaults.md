# Why nothing ships with a target

Install this package and `restock` tells you there is nothing to be short of.
That is deliberate, and it is the one design decision most likely to read as an
oversight.

## A cap is a fact; a target is a preference

`HELP 7.14` says the rift holds 2500 of each herb. That is the game speaking,
it is the same for everyone, and the package carries it.

How much bloodroot *you* want to be carrying is not that. It depends on what
you do with your evenings — 2500 ash is absurd for anyone, 800 health is
sensible for someone who fights and wasteful for someone who does not, and
there is no number the package could pick that would be right for two people.

Shipping a default would dress a guess up as a recommendation. Worse, it would
be a guess printed in green beside real numbers the game supplied, which is
exactly the kind of claim that gets believed because of the company it keeps.

## Setting a target is the opt-in

Rather than a separate "which headings do I check?" setting, the target *is*
the setting:

```
restock target herbs 500        # herbs are now checked, at 500 each
restock target health 1500      # one item, overriding its heading
restock forget herbs            # and no longer checked
```

That removes a whole concept. There is no way to be watching a heading with no
target, or to have a target that is not watched, because those are the same
fact stored once.

An item's own target beats its heading's, which is what `restock target health
1500` is for when `Elixirs` is already set to 600.

## `restock all` still works

A rift you have set no targets on is not useless to look at, so `restock all`
prints the whole thing grouped the way `RIFT` groups it, with no targets
involved. The difference from typing `RIFT` in game is that it is grouped,
sorted, and available without a round trip.

## The same rule, elsewhere

This is the house rule rather than a one-off. `M.CATEGORY` and
`M.GMCP_NAMES` hold only names a capture showed, the one cap read rather than
quoted says so wherever it is printed, and nothing gets extended from memory. A target list nobody typed would be the same mistake in a place where
it is harder to notice, because a wrong threshold does not look wrong — it
looks like advice.
