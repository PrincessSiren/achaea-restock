# The rift over GMCP

This package declares no `<Trigger>`, creates no `tempTrigger`, and never reads
a line of game output. The rift arrives as data.

## The handshake is already done

Mudlet asks for `IRE.Rift` in its own opening negotiation. From
`src/ctelnet.cpp`, in the `Core.Hello` exchange:

```
Core.Supports.Set [ "Char 1", "Char.Skills 1", "Char.Items 1", "Room 1",
                    "IRE.Rift 1", "IRE.Composer 1", … ]
```

So unlike `IRE.Target` — which needs an explicit `Core.Supports.Add
["IRE.Target 1"]` before the game will say anything — the rift module is on
from the first frame, and this package sends no handshake at all.

## The two frames

```lua
sendGMCP("IRE.Rift.Request")   -- ask for the whole rift
gmcp.IRE.Rift.List             -- an array of { name, amount }
gmcp.IRE.Rift.Change           -- one { name, amount }, on a deposit or withdrawal
```

`List` is treated as the whole rift and **replaces** what is held, rather than
merging into it: an item taken to zero may simply stop being listed, and a
merge would leave it sitting at its last known value forever.

`Change` patches one item in place.

## What a live profile showed

The shape was first read off Orion's `Rift` script, which reads exactly
`item.name` and `item.amount`. **It held in a live profile on 15th October
2026.** `restock diag` reported four `List` frames and a hundred `Change` frames
absorbed, and 70 items with an amount each.

The same run showed that **GMCP's names are not always the listing's**:
`blueink` for "blue ink", `myrrh` for "myrrh gum", and `goldbar` and `silver`
for "gold" and "silverore". `M.GMCP_NAMES` maps them back. **Two listed items
never arrive at all**, `silver bar` and `shipwood`, and `M.GMCP_ABSENT` keeps
the report from reading them as none held. The details of both are in
[what-it-knows.md](what-it-knows.md).

**Buying into the rift sends no `Change`.** 1000 health was bought straight
into the rift, and a listing afterwards printed 2000 while the frames still
held 1000. A `restock refresh` brought the 2000 in. So the reports ask for a
`List` before answering, rather than trusting the `Change` stream to have
kept up. That costs one round trip, and a timeout covers a request that goes
unanswered.

**In a quiet room the answer waits.** 0.2.0 sent the request on its own, and in
a quiet room every report timed out and fell back to the frames held. Timed
with a one-shot handler on 15th October 2026, a request sent with nothing else
was answered after 10.07s, in the same batch as the next line of room text.
Two requests sent back to back were answered 1.20s after the second one,
followed by a prompt. The likeliest reading is that Achaea holds the answer
until something else gives it a reason to send, though two timings are not a
measurement of that.

From 0.2.1 a report sends a blank line after its request, and on the first live
run in a quiet room the `List` came back at once, with one extra prompt in the
main window. Mudlet's `send("")` sends a bare newline at both `Mudlet-4.22.0`
and `Mudlet-5.0.1` (`Host::send`, "allow sending blank commands"), and drops it
while disconnected. The request `M.start()` makes at load goes without one,
since the profile may be sitting at the login prompt. The timeout stays.

## What is still not verified

Three specific things nobody here has confirmed:

- **What else a blank line does in Achaea.** It was seen to print a prompt,
  once. Whether it breaks hiding, meditation or anything else that ends on a
  command has not been tried. Other Mudlet packages also see it go by as a
  sent command (`sysDataSendRequest` with `""`).

- **Whether `amount` is a number or a string.** Orion calls `tonumber()` on it,
  which is either caution or knowledge and reads the same either way. It
  matters, because `IRE.Target` is on record reporting an adventurer's id and
  health as the *strings* `"-1"` rather than as numbers, so a numeric-looking
  GMCP field in an IRE game is not safely a number. `absorb()` therefore
  `tonumber()`s and rejects what will not convert, and the harness drives both
  shapes.
- **Whether Achaea sends a `List` unasked at login.** It may well; nothing here
  knows. `M.start()` reads `gmcp.IRE.Rift.List` first — Mudlet keeps the last
  frame, so one that landed before this script was recompiled is still
  there — and only asks with `IRE.Rift.Request` if that came back empty. That
  ordering is correct whichever way the question resolves.

## Why `M.rift` is never saved

It is the game's answer, not a setting. A copy persisted at logout and reloaded
at login would be a plausible-looking shopping list built from whatever was
true yesterday, and it would be wrong exactly when you had been spending
curatives. Targets persist; stock does not.
