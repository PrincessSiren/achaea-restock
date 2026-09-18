# Why it is not called `rift`

`RIFT` is Achaea's own command, and a Mudlet alias on `^rift$` shadows the verb
it is named after.

`HELP 7.14` lists the surrounding grammar:

```
INR [<amount>|ALL] <item>        put something in
OUTR [<amount>|ALL] <item>       take something out
FILL <vial> WITH <fluid> FROM RIFT
POUR [# of sips] <container|fluid> INTO RIFT
RIFT (or IR) [item]              look
INFO RIFT [item]                 also look
```

So `rift`, `ir`, `inr` and `outr` are all spoken for, and any of them taken as
a command prefix would break the thing the package exists to help with.

`restock` was typed in game before it was chosen:

```
restock
I'm sorry, I don't know what "restock" does.
```

`HELP RESTOCK` finds no command either — only the word appearing in prose in
two unrelated scrolls, an Undeath scroll pointing at `PRAY TO THE DEMISE` and a
Historical Collection card description. So the front of that command line is
free, which is the whole requirement.

## Why not `AchaeaRift`

The package is named for the job rather than for the container. It is a
shopping list, not a rift browser, and a stranger reading a package listing
sees the name before the description. `AchaeaRestocker` was considered and
dropped for the opposite reason: the `-er` names *you*, the person doing the
restocking, and promises a tool that does the buying. This one sends a single
GMCP request and nothing else.

If it ever grows to send `BUY` lines at a shop, renaming it then is a change
that reads as the package having earned the name. Starting there and never
arriving is the version that misleads.
