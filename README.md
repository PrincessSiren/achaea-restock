# AchaeaRestock

[![release](https://img.shields.io/github/v/release/PrincessSiren/achaea-restock)](../../releases/latest)

What to buy before you go out.

It reads your rift over GMCP, compares it against targets you set, and prints
what is short and how much of it to buy. It sends one thing —
`IRE.Rift.Request` — and triggers on nothing at all, because the rift arrives
as data rather than as text to parse.

**Nothing ships with a target.** How much bloodroot you want is a preference,
not a fact about the game, so the package cannot invent one for you. Setting a
target is what opts a heading or an item into the report.

## Install

In Mudlet, install `AchaeaRestock.mpackage` from the
[latest release](../../releases/latest), or build it yourself with
`python3 build.py`. Then say what you want to be holding:

```
restock target herbs 500
restock target health 1500
restock
```

Or watch cures rather than items. Every mineral does exactly what one herb
does (`HELP 13.7.1`), and server-side curing falls back to the other when one
runs out, so this counts each pair together and names the herb to buy:

```
restock cures 500
restock cures herbs
restock
```

A release is one pinned version: it is tagged `v<version>`, the `.mpackage`
attached to it is built from that tag, and `restock help` prints the same
version back. The version alone cannot tell you whether Mudlet is running what
is on disk, though — it says what you expect whether or not anything was
rebuilt. `restock diag` prints the build stamp for that, the one `build.py`
printed when it built the package. If the two differ, Mudlet is running an
older install.

## Commands

| Command | What it does |
| --- | --- |
| `restock` | What is below target, worst shortfall first |
| `restock all` | Everything in the rift, grouped the way `RIFT` groups it |
| `restock <heading>` | One heading: what you hold, and what is short |
| `restock target` | Every target you have set |
| `restock target <heading\|item> <n>` | Hold n of it — this is what opts it in |
| `restock forget <heading\|item>` | Drop a target again |
| `restock cures [n]` | Herb + mineral pairs under n together; n sets it, 0 turns it off |
| `restock cures all` | Every pair, stocked or not |
| `restock cures herbs\|minerals\|either` | Which half the cure report says to buy |
| `restock slack [n]` | How far below target still counts as stocked |
| `restock refresh` | Ask the game for the whole rift again |
| `restock diag` | Build stamp, frames seen, and any held item with no heading |
| `restock help` | This list |

The headings are the game's own, from `RIFT` listings: Herbs, Minerals,
Elixirs, Salves, Inks, Reagent (or Reagents), Ingredients, Commodities,
Shipcomm, Misc.

## Two things it is honest about

**It knows a lower bound of item names.** GMCP sends `{ name, amount }` per
item and no category at all, so which heading a name belongs under comes from a
captured `RIFT` listing — which holds what one character happened to be
carrying. Anything outside that lands under `Unsorted`, where `restock diag`
names it, rather than being guessed into a heading.

**It does not know what a mineral caps at.** Capacities come from `HELP 7.14`,
which caps "each type of herb, commodity, reagent, or crystal" and never
mentions minerals, though its own contents paragraph lists them separately from
crystals. So that cap is missing rather than assumed, and the test suite fails
if anybody fills it in without a capture to point at.

Why it is built this way is in [docs/](docs/). To send a patch, see
[CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE), which is also shipped inside the
built `.mpackage` — Mudlet's package format has no licence field, so the file
is the only way the terms reach anyone who installs it.

You may use, change and pass this on. If you pass on a changed version it has
to stay under the same licence, with its source available.
