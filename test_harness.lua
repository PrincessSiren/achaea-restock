-- Drives AchaeaRestock.lua under plain luajit, with enough of Mudlet stubbed
-- to run it. Mudlet embeds Lua 5.1 and luajit is that exact dialect.
--
-- What this proves is the logic and the tables. What it cannot prove is that
-- Achaea sends what the GMCP fixtures below say it sends: those are modelled
-- on Orion's own IRE.Rift handlers, not captured. Their { name, amount } shape
-- held in a live profile on 15th October 2026 (docs/the-rift-over-gmcp.md),
-- but whether amount is a number or a string is still unknown. The amount
-- arriving as a *string* is tested for that reason -- IRE.Target is on record
-- handing numbers over as strings, so neither shape is assumed.
--
--   luajit test_harness.lua
--
-- Resolves its own directory, so it runs from anywhere rather than only
-- from the repository root.

local passed, failed = 0, 0

local function ok(condition, label)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        io.write("FAIL: ", label, "\n")
    end
end

local function eq(got, want, label)
    if got ~= want then
        failed = failed + 1
        io.write("FAIL: ", label, " -- got ", tostring(got),
            ", wanted ", tostring(want), "\n")
    else
        passed = passed + 1
    end
end

-- ---------------------------------------------------------------------------
-- the Mudlet stub
-- ---------------------------------------------------------------------------

local echoed = {}
local sent = {}
local handlers = {}
local nextHandler = 0

function cecho(text) echoed[#echoed + 1] = text end
function sendGMCP(what) sent[#sent + 1] = what end
local typed = {}
function send(what, echo)
    typed[#typed + 1] = { what = what, echo = echo, after = #sent }
end

function registerAnonymousEventHandler(event, fn)
    nextHandler = nextHandler + 1
    handlers[nextHandler] = { event = event, fn = fn }
    return nextHandler
end

function killAnonymousEventHandler(id)
    handlers[id] = nil
end

gmcp = { IRE = { Rift = {} } }

local function clearEcho() echoed = {} end

local function echoedText()
    return table.concat(echoed, "")
end

--- Fire whatever is registered for an event, the way Mudlet would.
local function raise(event)
    local fired = 0
    for _, h in pairs(handlers) do
        if h.event == event then
            h.fn()
            fired = fired + 1
        end
    end
    return fired
end

-- ---------------------------------------------------------------------------

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\]")) or "."

dofile(HERE .. "/AchaeaRestock.lua")
local M = restock

-- ---------------------------------------------------------------------------
-- the tables, against the capture they were transcribed from
-- ---------------------------------------------------------------------------

do
    eq(#M.CATEGORY_ORDER, 10, "ten headings in the listing's order")
    eq(M.CATEGORY_ORDER[1], "Herbs", "Herbs is first, as RIFT prints it")
    eq(M.CATEGORY_ORDER[9], "Shipcomm", "Shipcomm is ninth")
    eq(M.CATEGORY_ORDER[10], "Misc", "Misc is last")

    -- Every heading in the order list is one something is actually filed
    -- under, and every category used is a heading in the order list. A typo in
    -- either direction shows up here rather than as a silently empty section.
    local used = {}
    local total = 0
    for _, category in pairs(M.CATEGORY) do
        used[category] = (used[category] or 0) + 1
        total = total + 1
    end
    -- 56 from the September listing, 19 more from October's first,
    -- stannum from October's last, and rawstone from the 19th's.
    eq(total, 77, "77 names transcribed from RIFT listings")
    for _, head in ipairs(M.CATEGORY_ORDER) do
        ok(used[head], "heading has at least one name: " .. head)
        used[head] = nil
    end
    eq(next(used), nil, "no name filed under a heading not in the order list")

    -- The per-heading counts of the captures together. No listing is a
    -- superset of another: kelp and irid were held in September and not in
    -- October, health not on the 19th, which is why the union is counted.
    local want = {
        Herbs = 21, Minerals = 10, Elixirs = 7, Salves = 5, Inks = 6,
        Reagent = 3, Ingredients = 6, Commodities = 17, Shipcomm = 1,
        Misc = 1,
    }
    local got = {}
    for _, category in pairs(M.CATEGORY) do
        got[category] = (got[category] or 0) + 1
    end
    for head, n in pairs(want) do
        eq(got[head], n, "rows under " .. head)
    end

    -- Two-word names are the easy transcription to lose.
    eq(M.CATEGORY["myrrh gum"], "Herbs", "myrrh gum keeps its space")
    eq(M.CATEGORY["wyrm tongue"], "Reagent", "wyrm tongue keeps its space")
    eq(M.CATEGORY["blue ink"], "Inks", "blue ink keeps its space")
    eq(M.CATEGORY["silver bar"], "Commodities", "silver bar keeps its space")
    eq(M.CATEGORY["lumic moss"], "Reagent", "lumic moss is a reagent, not irid")
end

-- ---------------------------------------------------------------------------
-- the cure pairs, against the shape of HELP 13.7.1
-- ---------------------------------------------------------------------------

do
    -- 13.7.1 lists twenty-one minerals and gives each the exact line of one
    -- herb. So: twenty-one rows, every mineral once, every herb once except
    -- skullcap, which is two cures (eaten and smoked) and so two rows.
    eq(#M.CURES, 21, "one row per mineral in 13.7.1")
    local herbs, minerals = {}, {}
    for _, pair in ipairs(M.CURES) do
        local herb, mineral = pair[1], pair[2]
        herbs[herb] = (herbs[herb] or 0) + 1
        minerals[mineral] = (minerals[mineral] or 0) + 1
        -- Every herb is one a listing has shown under Herbs. That is what
        -- makes the rift's short names (ash, elm, irid, pear) safe to use.
        eq(M.CATEGORY[herb], "Herbs", "the cure herb is a rift herb: " .. herb)
        -- A mineral is either one a listing has shown under Minerals or one
        -- no listing has shown at all -- never a name filed somewhere else.
        local filed = M.CATEGORY[mineral]
        ok(filed == nil or filed == "Minerals",
            "the cure mineral is not filed under another heading: " .. mineral)
    end
    for mineral, n in pairs(minerals) do
        eq(n, 1, "each mineral pairs once: " .. mineral)
    end
    for herb, n in pairs(herbs) do
        eq(n, herb == "skullcap" and 2 or 1, "rows for " .. herb)
    end
    eq(herbs.burdock, nil, "burdock is not in 13.7.1, so it pairs with nothing")

    -- Every mineral the listings have shown is in a pair. Ten of them; if an
    -- eleventh appears under Minerals and is not a cure, this is where it shows.
    local seen = 0
    for name, category in pairs(M.CATEGORY) do
        if category == "Minerals" then
            seen = seen + 1
            ok(minerals[name], "a listed mineral is in a pair: " .. name)
        end
    end
    eq(seen, 10, "ten minerals seen in a listing")

    -- HELP 18.5.1 lists every mineral by a short name, and M.CURES is held
    -- to that list both ways: each pair's mineral is a short name, and each
    -- short name is in a pair. These are the scroll's own words, lowercased.
    local SHORT = {
        "antimony", "argentum", "arsenic", "aurum", "azurite", "bisemutum",
        "calamine", "calcite", "cinnabar", "cuprum", "dolomite", "ferrum",
        "gypsum", "magnesium", "malachite", "plumbum", "potash", "quartz",
        "quicksilver", "realgar", "stannum",
    }
    local short = {}
    for _, name in ipairs(SHORT) do
        short[name] = true
        eq(minerals[name], 1, "18.5.1's short name is in one pair: " .. name)
    end
    for name in pairs(minerals) do
        ok(short[name], "the pair's mineral is an 18.5.1 short name: " .. name)
    end
end

-- ---------------------------------------------------------------------------
-- stannum, bought to test a short name against GMCP
-- ---------------------------------------------------------------------------

do
    -- 15th October 2026: 500 stannum bought, and GMCP sent it as `stannum`,
    -- the short name. It counts toward ash's pair.
    gmcp.IRE.Rift.List = {
        { name = "ash", amount = 318 },
        { name = "stannum", amount = 500 },
    }
    raise("gmcp.IRE.Rift.List")
    for _, row in ipairs(M.cureShortfall()) do
        if row.herb == "ash" then
            eq(row.have, 818, "ash 318 + stannum 500")
        end
    end
    M.config.cureLow = 900
    M.config.cureBuy = "either"
    clearEcho()
    M.cures("")
    ok(echoedText():find("stannum", 1, true), "the pair prints with stannum")
    M.config.cureLow = 0
end

-- ---------------------------------------------------------------------------
-- what GMCP does not send: items at zero, and two that never arrive
-- ---------------------------------------------------------------------------

do
    gmcp.IRE.Rift.List = {
        { name = "ash", amount = 318 },
        { name = "cloth", amount = 2399 },
    }
    raise("gmcp.IRE.Rift.List")
    local realSave = M.save
    M.save = function() return true end
    M.targets = {}
    M.config.slack = 0

    -- Kelp went from 298 to unlisted between two captures. A target on it
    -- has to report the whole amount, which 0.1.x never did.
    M.targets.kelp = 300
    local rows = M.shortfall()
    eq(#rows, 1, "a target on an item at zero is reported")
    eq(rows[1].name, "kelp", "...by name")
    eq(rows[1].have, 0, "...as none held")
    eq(rows[1].buy, 300, "...short the whole target")
    eq(#M.shortfall("Herbs"), 1, "...and under its heading")
    eq(#M.shortfall("Minerals"), 0, "...and not under another")

    -- A heading target names no items, so it cannot reach one at zero.
    M.targets = { Herbs = 500 }
    eq(#M.shortfall(), 1, "a heading target sees only what is held")

    -- Silver bar and shipwood are in every October listing and in no frame.
    -- Reporting them short would call for the whole target while 2466 bars
    -- sit in the rift.
    M.targets = {}
    clearEcho()
    ok(M.setTarget("silver bar", "2500"), "a target on a never-sent item is kept")
    ok(echoedText():find("never sent over GMCP", 1, true), "...with a warning")
    M.targets.shipwood = 100
    eq(#M.shortfall(), 0, "neither is reported as none held")

    clearEcho()
    M.diag()
    ok(echoedText():find("never sent over GMCP: shipwood, silver bar", 1, true),
        "diag names both")
    gmcp.IRE.Rift.Change = { name = "shipwood", amount = 85 }
    raise("gmcp.IRE.Rift.Change")
    clearEcho()
    M.diag()
    ok(echoedText():find("now sent over GMCP after all", 1, true),
        "diag says when one turns up after all")
    M.targets = {}
    M.save = realSave
end

-- ---------------------------------------------------------------------------
-- HELP 7.14's capacity table
-- ---------------------------------------------------------------------------

do
    -- 7.14 caps "each type of herb, commodity, reagent, or crystal" and never
    -- says mineral. This row was held empty through 0.1.x for that reason, and
    -- is 2500 since 0.2.0 on the owner's reading that the scroll's crystals are
    -- the minerals. It is a reading, so the note that says so must stay with
    -- it: a cap printed without it would claim the scroll says something it
    -- does not.
    eq(M.CAP.Minerals, 2500, "Minerals takes 7.14's crystal cap")
    ok(M.CAP_NOTE.Minerals and M.CAP_NOTE.Minerals:find("crystal", 1, true),
        "...and carries the note that it is read from \"crystal\"")

    eq(M.CAP.Herbs, 2500, "herbs cap, 7.14")
    eq(M.CAP.Inks, 750, "inks cap, 7.14")
    eq(M.CAP.Ingredients, 1000, "cooking ingredients cap, 7.14")
    eq(M.CAP.Shipcomm, 500, "ship commodities cap, 7.14")
    eq(M.CAP.Elixirs, 1000, "fluids cap, 7.14")

    -- "2000 sips of health and mana", named individually against the 1000 the
    -- rest of the fluids get.
    eq(M.capOf("health"), 2000, "health is one of the two named at 2000")
    eq(M.capOf("mana"), 2000, "mana is one of the two named at 2000")
    eq(M.capOf("frost"), 1000, "another elixir falls back to the fluid cap")
    eq(M.capOf("ash"), 2500, "an item takes its heading's cap")
    eq(M.capOf("Herbs"), 2500, "a heading takes its own cap")
    eq(M.capOf("ferrum"), 2500, "a mineral takes the crystal cap")
    eq(M.capOf("nonesuch"), nil, "an unknown name has no cap")

    -- Where the scroll hedges, the package says so rather than dropping it.
    ok(M.CAP_NOTE.Elixirs, "the \"most curatives\" hedge is carried")
end

-- ---------------------------------------------------------------------------
-- GMCP
-- ---------------------------------------------------------------------------

do
    eq(#M.state.handlers, 3, "three handlers registered: List, Change and the uninstall")

    -- Numbers as numbers.
    gmcp.IRE.Rift.List = {
        { name = "ash", amount = 404 },
        { name = "bloodroot", amount = 188 },
        { name = "health", amount = 1308 },
    }
    eq(raise("gmcp.IRE.Rift.List"), 1, "the List handler is reachable by event")
    eq(M.rift.ash, 404, "ash absorbed")
    eq(M.rift.health, 1308, "health absorbed")

    -- ...and as strings. IRE.Target reports "-1" as a string for an adventurer,
    -- so a numeric-looking GMCP field is not assumed to be a number.
    gmcp.IRE.Rift.List = {
        { name = "ash", amount = "404" },
        { name = "kelp", amount = "298" },
    }
    raise("gmcp.IRE.Rift.List")
    eq(M.rift.ash, 404, "a string amount is still a number here")
    eq(M.rift.kelp, 298, "a string amount is still a number here")

    -- A List is the whole rift, so it replaces: an item that stopped being
    -- listed is gone rather than remembered at its last value.
    eq(M.rift.bloodroot, nil, "a List replaces rather than merging")
    eq(M.rift.health, nil, "a List replaces rather than merging")

    -- A Change is one item, patched in place.
    gmcp.IRE.Rift.Change = { name = "ash", amount = 350 }
    eq(raise("gmcp.IRE.Rift.Change"), 1, "the Change handler is reachable")
    eq(M.rift.ash, 350, "a Change patches one item")
    eq(M.rift.kelp, 298, "a Change leaves the rest alone")

    -- Junk is dropped rather than stored.
    local before = M.rift.ash
    gmcp.IRE.Rift.Change = { name = "ash" }
    raise("gmcp.IRE.Rift.Change")
    eq(M.rift.ash, before, "a Change with no amount changes nothing")
    gmcp.IRE.Rift.Change = "ash"
    ok(M.onChange() == false, "a Change that is not a table is refused")
    gmcp.IRE.Rift.List = nil
    ok(M.onList() == false, "an absent List is refused")
end

-- ---------------------------------------------------------------------------
-- targets and arithmetic
-- ---------------------------------------------------------------------------

do
    gmcp.IRE.Rift.List = {
        { name = "ash", amount = 404 },
        { name = "bloodroot", amount = 188 },
        { name = "kelp", amount = 298 },
        { name = "ferrum", amount = 1000 },
        { name = "health", amount = 1308 },
    }
    raise("gmcp.IRE.Rift.List")
    M.targets = {}
    M.config.slack = 0

    eq(M.targetOf("ash"), nil, "no target until one is set")

    M.targets.Herbs = 500
    eq(M.targetOf("ash"), 500, "an item takes its heading's target")
    local _, how = M.targetOf("ash")
    eq(how, "category", "...and says where it came from")

    M.targets.ash = 900
    eq(M.targetOf("ash"), 900, "an item's own target beats its heading's")
    local _, how2 = M.targetOf("ash")
    eq(how2, "item", "...and says so")
    M.targets.ash = nil

    local rows = M.shortfall()
    -- ash 404, bloodroot 188, kelp 298 are all under 500; ferrum and health
    -- are not herbs and have no target of their own.
    eq(#rows, 3, "three herbs short of 500")
    eq(rows[1].name, "bloodroot", "worst shortfall first")
    eq(rows[1].buy, 312, "buy = target - have")
    eq(rows[3].name, "ash", "least short last")
    eq(rows[3].buy, 96, "buy = target - have")

    -- Slack is what stops a list of trivia. bloodroot is 312 short, kelp 202,
    -- ash 96 -- so a slack of 100 drops only ash.
    M.config.slack = 100
    eq(#M.shortfall(), 2, "slack drops what is nearly stocked")
    M.config.slack = 400
    eq(#M.shortfall(), 0, "enough slack drops everything")
    M.config.slack = 0

    -- One heading at a time.
    M.targets.Minerals = 2000
    eq(#M.shortfall("Minerals"), 1, "ferrum is short of 2000")
    eq(#M.shortfall("Herbs"), 3, "and the herbs are unaffected")
    M.targets.Minerals = nil

    -- An item target on something whose heading has none still counts.
    M.targets.health = 1500
    local only = M.shortfall("Elixirs")
    eq(#only, 1, "an item target works without a heading target")
    eq(only[1].buy, 192, "buy = 1500 - 1308")
    M.targets.health = nil
    M.targets.Herbs = nil
end

-- ---------------------------------------------------------------------------
-- cure arithmetic, on the herbs and minerals of RIFT 2026-10-15
-- ---------------------------------------------------------------------------

local OCTOBER = {
    ash = 318, bayberry = 398, bellwort = 641, bloodroot = 2072, burdock = 599,
    cohosh = 249, echinacea = 554, elm = 1185, ginger = 456, ginseng = 671,
    goldenseal = 613, hawthorn = 511, kola = 2150, lobelia = 1625,
    ["myrrh gum"] = 684, pear = 155, sileris = 2447, skullcap = 1561,
    valerian = 353,
    aurum = 576, bisemutum = 564, calcite = 678, cinnabar = 299,
    ferrum = 1000, malachite = 260, potash = 2351, quartz = 30, realgar = 249,
}

do
    local list = {}
    for name, amount in pairs(OCTOBER) do
        list[#list + 1] = { name = name, amount = amount }
    end
    gmcp.IRE.Rift.List = list
    raise("gmcp.IRE.Rift.List")
    M.targets = {}
    M.config.slack = 0
    M.config.cureBuy = "either"

    -- Under 500 together: cohosh 249, ash 318, bayberry 398 and ginger 456,
    -- none with a mineral held. Valerian 353 is short alone and not with
    -- realgar's 249; pear 155 is short alone and not with calcite's 678.
    local rows = M.cureShortfall(500)
    eq(#rows, 4, "four cures under 500, herb and mineral together")
    eq(rows[1].herb, "cohosh", "worst first")
    eq(rows[1].buy, 251, "buy = threshold - herb - mineral")
    eq(rows[4].herb, "ginger", "least short last")
    eq(rows[4].buy, 44, "buy = 500 - 456")
    for _, row in ipairs(rows) do
        ok(row.herb ~= "valerian" and row.herb ~= "pear",
            "a mineral makes up a short herb: " .. row.herb)
    end

    -- Kelp and irid are not listed at all: an item at zero drops out of a
    -- List. Their minerals carry them.
    local all = M.cureShortfall()
    eq(#all, 21, "every pair, with no threshold")
    for _, row in ipairs(all) do
        if row.herb == "irid" then
            eq(row.have, 2351, "no irid, all potash")
        elseif row.herb == "valerian" then
            eq(row.have, 602, "valerian 353 + realgar 249")
        end
    end

    -- Skullcap counts toward both its cures, since one stock serves either.
    local skull = 0
    for _, row in ipairs(all) do
        if row.herb == "skullcap" then
            skull = skull + 1
            eq(row.herbHave, 1561, "skullcap counts in full toward " .. row.mineral)
        end
    end
    eq(skull, 2, "skullcap appears under both its minerals")

    -- Slack applies here as it does to item targets: ginger is 44 short.
    M.config.slack = 50
    eq(#M.cureShortfall(500), 3, "slack drops what is nearly stocked")
    M.config.slack = 0

    -- The dispatcher.
    M.config.cureLow = 0
    clearEcho()
    ok(not M.cures(""), "no threshold, nothing to report")
    ok(echoedText():find("restock cures 500", 1, true), "...and says how to set one")
    ok(M.cures("500"), "a number sets the threshold")
    eq(M.config.cureLow, 500, "...and it is kept")

    clearEcho()
    ok(M.cures(""), "the report runs")
    local text = echoedText()
    ok(text:find("cohosh"), "...naming the worst")
    ok(not text:find("?", 1, true), "...with no name marked as a guess")
    ok(text:find("either half", 1, true), "...saying either half will do")
    ok(not text:find("buy 251 cohosh", 1, true), "...without picking one")

    ok(M.cures("herb"), "herb is accepted")
    eq(M.config.cureBuy, "herbs", "...as herbs")
    clearEcho()
    M.cures("")
    ok(echoedText():find("buy 251 cohosh", 1, true), "herbs names the herb")
    ok(M.cures("minerals"), "minerals is accepted")
    clearEcho()
    M.cures("")
    ok(echoedText():find("buy 251 gypsum", 1, true), "minerals names the mineral")
    ok(M.cures("either"), "either is accepted")

    ok(not M.cures("bogus"), "anything else is refused")
    ok(not M.cures("-5"), "a negative threshold is refused")
    eq(M.config.cureLow, 500, "...and changes nothing")

    clearEcho()
    ok(M.cures("all"), "all prints every pair")
    ok(echoedText():find("potash"), "...stocked ones included")

    M.config.cureLow = 100
    clearEcho()
    ok(M.cures(""), "the report runs when nothing is short")
    ok(echoedText():find("Every cure has at least 100", 1, true), "...and says so")

    -- The main report carries the cure section, and a threshold alone is
    -- enough to opt into it.
    M.config.cureLow = 500
    clearEcho()
    ok(M.report(), "restock reports on cures with no item target set")
    ok(echoedText():find("cohosh"), "...naming the short ones")
    M.targets.Herbs = 300
    clearEcho()
    ok(M.report(), "...and alongside item targets")
    text = echoedText()
    ok(text:find("Below target", 1, true) and text:find("Cures below", 1, true),
        "...both sections")
    M.targets = {}
    ok(M.cures("0"), "0 turns it off")
    clearEcho()
    ok(not M.report(), "off, and with no targets, the report declines again")
end

-- ---------------------------------------------------------------------------
-- GMCP's names, which are not always the listing's
-- ---------------------------------------------------------------------------

do
    -- The nine names `restock diag` could not place in a live profile on 15th
    -- October 2026, at the amounts it printed. The RIFT listing taken minutes
    -- before had each amount under the name M.GMCP_NAMES gives.
    local DIAG = {
        blueink = 58, goldbar = 7, goldink = 67, greenink = 32, myrrh = 684,
        purpleink = 34, redink = 26, silver = 34, yellowink = 10,
    }
    local LISTED = {
        ["blue ink"] = 58, gold = 7, ["gold ink"] = 67, ["green ink"] = 32,
        ["myrrh gum"] = 684, ["purple ink"] = 34, ["red ink"] = 26,
        silverore = 34, ["yellow ink"] = 10,
    }
    local n, predicted = 0, 0
    for gmcpName, listed in pairs(M.GMCP_NAMES) do
        ok(M.CATEGORY[listed], "a GMCP name maps onto a listed name: " .. gmcpName)
        eq(M.CATEGORY[gmcpName], nil,
            "a GMCP name is not itself a listed name: " .. gmcpName)
        if M.GMCP_PREDICTED[gmcpName] then
            predicted = predicted + 1
        else
            n = n + 1
            eq(LISTED[listed], DIAG[gmcpName],
                "the diag and the listing agree on the amount: " .. gmcpName)
        end
    end
    eq(n, 9, "nine observed GMCP names, all from one diag")
    -- One predicted row, from HELP 18.5's short name for irid moss. A second
    -- needs a scroll to come from, and the comment above M.GMCP_NAMES says
    -- which one; this count is what makes adding it a deliberate act.
    eq(predicted, 1, "one predicted GMCP name")
    eq(M.GMCP_NAMES.moss, "irid", "18.5: Moss is some irid moss")
    for name in pairs(M.GMCP_PREDICTED) do
        ok(M.GMCP_NAMES[name], "a predicted name is a GMCP_NAMES row: " .. name)
    end

    local list = { { name = "bisemutum", amount = 564 } }
    for name, amount in pairs(DIAG) do
        list[#list + 1] = { name = name, amount = amount }
    end
    gmcp.IRE.Rift.List = list
    raise("gmcp.IRE.Rift.List")
    eq(M.rift["blue ink"], 58, "blueink arrives as blue ink")
    eq(M.rift.blueink, nil, "...and not under its GMCP name")
    eq(M.rift.silverore, 34, "GMCP's silver is RIFT's silverore")
    eq(M.rift.gold, 7, "GMCP's goldbar is RIFT's gold")
    local _, unsorted = M.grouped()
    eq(#unsorted, 0, "nothing from that diag is unsorted any more")
    eq(M.capOf("blue ink"), 750, "and the inks take the ink cap")

    -- The pair that was reading wrong: myrrh gum is GMCP's myrrh.
    for _, row in ipairs(M.cureShortfall()) do
        if row.mineral == "bisemutum" then
            eq(row.have, 1248, "myrrh gum 684 + bisemutum 564")
        end
    end

    -- The predicted row: irid arriving as `moss` lands on irid, counts in
    -- its pair, and diag says it has now been seen.
    clearEcho()
    M.diag()
    ok(echoedText():find("predicted from HELP 18.5, not seen yet", 1, true),
        "diag says moss -> irid is not seen yet")
    gmcp.IRE.Rift.Change = { name = "moss", amount = 373 }
    raise("gmcp.IRE.Rift.Change")
    eq(M.rift.irid, 373, "moss arrives as irid")
    eq(M.rift.moss, nil, "...and not as moss")
    clearEcho()
    M.diag()
    ok(echoedText():find("seen this session", 1, true), "...and diag says so")
    M.state.gmcpSeen = nil
    M.rift.irid = nil

    -- A Change uses the same names.
    gmcp.IRE.Rift.Change = { name = "myrrh", amount = 700 }
    raise("gmcp.IRE.Rift.Change")
    eq(M.rift["myrrh gum"], 700, "a Change is translated too")

    -- A target typed with either spelling lands on the listed name.
    local realSave = M.save
    M.save = function() return true end
    M.targets = {}
    ok(M.setTarget("myrrh", "800"), "a target by GMCP name")
    eq(M.targets["myrrh gum"], 800, "...is kept under the listed name")
    ok(M.forget("myrrh"), "...and forgotten by it")
    M.targets = {}
    M.save = realSave
end

-- ---------------------------------------------------------------------------
-- a report asks for a fresh List first
-- ---------------------------------------------------------------------------

do
    -- 15th October 2026: 1000 health bought into the rift sent no Change,
    -- and only `restock refresh` brought the new amount in. So the reports
    -- ask for a List and answer when it lands.
    local timers, nextTimer = {}, 0
    tempTimer = function(seconds, fn)
        nextTimer = nextTimer + 1
        timers[nextTimer] = { seconds = seconds, fn = fn }
        return nextTimer
    end
    killTimer = function(id) timers[id] = nil end

    gmcp.IRE.Rift.List = { { name = "health", amount = 1000 } }
    raise("gmcp.IRE.Rift.List")
    sent, typed = {}, {}
    local ran, saw = 0, nil
    ok(M.fresh(function() ran = ran + 1; saw = M.rift.health end),
        "a fresh report is accepted")
    eq(sent[1], "IRE.Rift.Request", "...and asks for the whole rift")
    -- Achaea held a request's answer 10.07s in a quiet room, until the next
    -- line of room text; something the game answers has to go with it.
    eq(#typed, 1, "...with one line sent to the game")
    eq(typed[1].what, "", "...and that line blank")
    eq(typed[1].echo, false, "...and not echoed")
    eq(typed[1].after, 1, "...and sent after the request, not before")
    eq(ran, 0, "...and waits for it")

    -- The purchase, arriving in the List the request asked for.
    gmcp.IRE.Rift.List = { { name = "health", amount = 2000 } }
    raise("gmcp.IRE.Rift.List")
    eq(ran, 1, "the List that lands runs the report")
    eq(saw, 2000, "...against the new amounts")
    eq(next(timers), nil, "...and the timeout is cancelled")
    raise("gmcp.IRE.Rift.List")
    eq(ran, 1, "a later List does not run it again")

    -- No answer: the timer fires, and the report runs on what is held.
    ran = 0
    clearEcho()
    M.fresh(function() ran = ran + 1 end)
    local id, timer = next(timers)
    eq(timer.seconds, M.FRESH_WAIT, "the wait is FRESH_WAIT")
    timers[id] = nil
    timer.fn()
    eq(ran, 1, "an unanswered request still reports")
    ok(echoedText():find("no answer to IRE.Rift.Request", 1, true),
        "...and says it is reading the last frames")
    raise("gmcp.IRE.Rift.List")
    eq(ran, 1, "...and the late List does not run it twice")

    -- Asking twice keeps one report waiting, the latest.
    local first, second = 0, 0
    M.fresh(function() first = first + 1 end)
    M.fresh(function() second = second + 1 end)
    local waiting = 0
    for _ in pairs(timers) do waiting = waiting + 1 end
    eq(waiting, 1, "one timer for two asks")
    raise("gmcp.IRE.Rift.List")
    eq(first + second, 1, "...and one report")
    eq(second, 1, "...the latest")

    -- Setting a threshold changes a setting and does not wait; reading does.
    local realSave = M.save
    M.save = function() return true end
    sent, typed = {}, {}
    M.curesFresh("500")
    eq(#sent, 0, "restock cures 500 does not ask for the rift")
    eq(#typed, 0, "...and sends no blank line")
    eq(M.config.cureLow, 500, "...and is set at once")
    M.curesFresh("")
    eq(sent[1], "IRE.Rift.Request", "restock cures asks first")
    raise("gmcp.IRE.Rift.List")
    M.curesFresh("all")
    eq(sent[2], "IRE.Rift.Request", "restock cures all asks first")
    raise("gmcp.IRE.Rift.List")
    M.config.cureLow = 0
    M.save = realSave

    -- Stopping drops a report still waiting.
    M.fresh(function() first = first + 100 end)
    M.stop()
    eq(next(timers), nil, "stop cancels the wait")
    raise("gmcp.IRE.Rift.List")
    ok(first < 100, "...and the report never runs")
    M.start()

    tempTimer, killTimer = nil, nil
end

-- ---------------------------------------------------------------------------
-- a name the table has never seen
-- ---------------------------------------------------------------------------

do
    -- M.CATEGORY holds what one character happened to be carrying, so a name
    -- outside it is expected rather than exceptional. It must surface, not
    -- vanish and not be guessed into a heading.
    gmcp.IRE.Rift.List = {
        { name = "ash", amount = 404 },
        { name = "kuzu", amount = 12 },
    }
    raise("gmcp.IRE.Rift.List")
    local groups, unsorted = M.grouped()
    eq(#unsorted, 1, "an unknown name lands in Unsorted")
    eq(unsorted[1].name, "kuzu", "...under its own name")
    eq(#groups.Herbs, 1, "...and is not filed under a heading")

    clearEcho()
    M.diag()
    ok(echoedText():find("kuzu"), "diag names what has no heading")
end

-- ---------------------------------------------------------------------------
-- setting targets
-- ---------------------------------------------------------------------------

do
    M.targets = {}

    ok(M.setTarget("herbs", "500"), "a heading is set case-insensitively")
    eq(M.targets.Herbs, 500, "...under the listing's own capitalisation")

    ok(M.setTarget("HERBS", "600"), "...and in any case at all")
    eq(M.targets.Herbs, 600, "...still one key")

    ok(M.setTarget("bloodroot", "800"), "an item target is set")
    eq(M.targets.bloodroot, 800, "...lowercased")

    -- A name M.CATEGORY has never seen is still allowed: the table is a lower
    -- bound, and refusing would make it impossible to stock something the one
    -- capture did not happen to contain.
    ok(M.setTarget("kuzu", "50"), "an unknown item may still have a target")
    eq(M.targets.kuzu, 50, "...and it is kept")

    -- Over the cap is a warning, not a refusal. The game is the authority on
    -- what it will hold; this only knows what one scroll said.
    clearEcho()
    ok(M.setTarget("ash", "5000"), "a target over the cap is still set")
    eq(M.targets.ash, 5000, "...kept as asked")
    ok(echoedText():find("2500"), "...with the cap named")

    ok(not M.setTarget("herbs", "not a number"), "a non-number is refused")
    ok(not M.setTarget(nil, nil), "no arguments is refused")
    ok(not M.setTarget("herbs", "-5"), "a negative target is refused")

    ok(M.forget("herbs"), "a heading target is forgotten")
    eq(M.targets.Herbs, nil, "...and gone")
    ok(not M.forget("herbs"), "forgetting twice is refused")
    ok(not M.forget(nil), "forgetting nothing is refused")

    M.targets = {}
end

-- ---------------------------------------------------------------------------
-- the reports run, and say something when they cannot
-- ---------------------------------------------------------------------------

do
    gmcp.IRE.Rift.List = {
        { name = "ash", amount = 404 },
        { name = "bloodroot", amount = 188 },
    }
    raise("gmcp.IRE.Rift.List")

    M.targets = {}
    clearEcho()
    ok(not M.report(), "the report declines when no target is set")
    ok(echoedText():find("no targets set"), "...and says why")

    M.targets.Herbs = 500
    clearEcho()
    ok(M.report(), "the report runs")
    ok(echoedText():find("bloodroot"), "...naming what is short")
    ok(echoedText():find("Herbs"), "...under its heading")

    M.targets.Herbs = 100
    clearEcho()
    ok(M.report(), "the report runs when nothing is short")
    ok(echoedText():find("stocked"), "...and says so")

    clearEcho()
    ok(M.reportCategory("herbs"), "one heading prints")
    ok(echoedText():find("cap 2500"), "...with its cap")
    clearEcho()
    ok(not M.reportCategory("nonesuch"), "an unknown heading is refused")
    ok(echoedText():find("Herbs"), "...listing the real ones")
    clearEcho()
    ok(M.reportCategory("reagents"), "the plural heading is the same heading")
    ok(M.reportCategory("minerals"), "a heading with nothing in it prints")
    ok(echoedText():find("nothing in the rift"), "...and says it is empty")

    ok(M.listing(), "the full listing prints")

    -- The buy figure only reaches the target; every row also says how much
    -- more the rift would take, from HELP 7.14's caps.
    local saved = M.rift
    local savedTargets = M.targets
    M.rift = { health = 1800, mana = 640, frost = 1000, venom = 1100,
               epidermal = 300, gleam = 4 }
    M.targets = { Elixirs = 500, Salves = 500, health = 1000, mana = 1000,
                  frost = 1200 }
    clearEcho()
    ok(M.report(), "the report runs with fluid targets")
    -- Colour tags would sit between the columns, so read what is printed.
    local function shown() return (echoedText():gsub("<[%w_]+>", "")) end
    local text = shown()
    ok(text:find("mana%s+640 / 1000%s+buy 360%s+1360 to cap"),
        "a short elixir says how far it is from its own 2000 cap")
    ok(text:find("epidermal%s+300 / 500%s+buy 200%s+700 to cap"),
        "a short salve says how far it is from the fluid cap")
    ok(text:find("frost%s+1000 / 1200%s+buy 200%s+at cap"),
        "a target above the cap reads as at cap, not a negative")
    ok(not text:find("health"), "a stocked item stays out of the report")
    clearEcho()
    ok(M.listing(), "the listing runs")
    text = shown()
    ok(text:find("health%s+1800%s+200 to cap"), "every held row gets its cap")
    ok(text:find("venom%s+1100%s+100 over 7%.14's 1000"),
        "above the cap is said as such")
    ok(text:find("gleam%s+4\n"), "Misc has no cap, so no cap column")
    clearEcho()
    ok(M.reportCategory("elixirs"), "one heading prints")
    text = shown()
    local shortAt = text:match("\n([^\n]*mana[^\n]*)\n"):find(" to cap", 1, true)
    local heldAt = text:match("\n([^\n]*health[^\n]*)\n"):find(" to cap", 1, true)
    eq(heldAt, shortAt, "a stocked row's cap lines up under a short one's")
    M.rift, M.targets = saved, savedTargets

    -- No rift at all is a state the package is in at every login until the
    -- first frame lands, so every report has to survive it.
    local savedLists = M.state.lists
    M.state.lists = 0
    M.rift = {}
    clearEcho()
    ok(not M.report(), "the report declines before any frame")
    ok(echoedText():find("refresh"), "...pointing at the command that fills it")
    ok(not M.listing(), "the listing declines before any frame")
    ok(not M.reportCategory("herbs"), "a heading declines before any frame")

    -- An empty List is a different thing: a rift holding nothing. Through
    -- 0.3.0 it was read as no rift, so an item target or a cure threshold
    -- never produced a shopping list however often the rift was refreshed.
    gmcp.IRE.Rift.List = {}
    raise("gmcp.IRE.Rift.List")
    eq(next(M.rift), nil, "an empty List leaves an empty rift")
    M.targets = { bloodroot = 500 }
    clearEcho()
    ok(M.report(), "the report runs on an empty List")
    ok(shown():find("bloodroot%s+0 / 500%s+buy 500"),
        "...and an item target is bought from nothing")
    local savedLow = M.config.cureLow
    M.config.cureLow = 500
    clearEcho()
    ok(M.cures(), "the cure report runs on an empty List")
    ok(echoedText():find("bloodroot"), "...naming a pair held at none")
    clearEcho()
    ok(M.cures("all"), "every cure pair prints on an empty List")
    M.config.cureLow = savedLow
    clearEcho()
    ok(M.listing(), "the listing runs on an empty List")
    M.state.lists = savedLists
    M.targets = {}
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

do
    -- A recompile must tear its own handlers down rather than leaving a second
    -- set running over the live one. Mudlet clears
    -- mAnonymousEventHandlerFunctions only in Host::resetProfile, so a package
    -- keeping ids in a file-local doubles every event on every reload.
    local before = 0
    for _ in pairs(handlers) do before = before + 1 end
    M.start()
    local after = 0
    for _ in pairs(handlers) do after = after + 1 end
    eq(after, before, "restarting replaces its handlers rather than adding")

    gmcp.IRE.Rift.List = { { name = "ash", amount = 1 } }
    raise("gmcp.IRE.Rift.List")
    eq(M.rift.ash, 1, "one List handler, so one absorb")

    M.stop()
    eq(#M.state.handlers, 0, "stop drops the handlers")
    gmcp.IRE.Rift.List = { { name = "ash", amount = 2 } }
    eq(raise("gmcp.IRE.Rift.List"), 0, "...and nothing fires after it")
    M.start()

    -- start() asks for the rift when it has none, since whether Achaea pushes
    -- a List unasked at login is not established.
    sent, typed = {}, {}
    M.rift = {}
    gmcp.IRE.Rift.List = nil
    M.start()
    eq(sent[1], "IRE.Rift.Request", "an empty rift is asked for at start")
    -- At load the profile may be at the login prompt, or disconnected.
    eq(#typed, 0, "...with no blank line sent")
    sent, typed = {}, {}
    M.refresh()
    eq(sent[1], "IRE.Rift.Request", "restock refresh asks for the rift")
    eq(#typed, 1, "...and sends the blank line")
end

-- ---------------------------------------------------------------------------
-- removing the package stops it
-- ---------------------------------------------------------------------------

do
    -- Mudlet takes the aliases and the script and leaves the event handlers,
    -- so the package has to stop itself. The event is raised for every
    -- package, with the name as its argument.
    local function uninstall(name)
        local n = 0
        for _, h in pairs(handlers) do
            if h.event == "sysUninstall" then
                n = n + 1
                h.fn("sysUninstall", name)
            end
        end
        return n
    end
    eq(uninstall("SomebodyElse"), 1, "one uninstall handler, not one per load")
    eq(#M.state.handlers, 3, "another package being removed changes nothing")
    local build = io.open(HERE .. "/build.py", "r")
    local src = build:read("*a")
    build:close()
    eq(src:match('PACKAGE_NAME = "([^"]+)"'), M.PACKAGE,
        "the name checked is the one the package is built under")
    uninstall(M.PACKAGE)
    eq(#M.state.handlers, 0, "removing this package drops every handler")
    eq(next(handlers), nil, "...and none is left registered")
    M.start()
    eq(#M.state.handlers, 3, "an install after it starts it again")
end

-- ---------------------------------------------------------------------------
-- settings round-trip, and a hand-edited file is cleaned
-- ---------------------------------------------------------------------------

do
    local realSave, realLoad, realExists, realFile = table.save, table.load,
        io.exists, M.file
    local disk
    -- Mudlet's table.save serialises, so the stub copies: storing the live
    -- table would make every later change look as if it had been saved.
    local function copy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for k, x in pairs(v) do out[k] = copy(x) end
        return out
    end
    table.save = function(_, t) disk = copy(t) end
    table.load = function(_, into)
        for k, v in pairs(disk) do into[k] = v end
    end
    io.exists = function() return disk ~= nil end
    M.file = "/harness/achaea-restock.lua"

    M.targets = { ash = 500, Herbs = 300 }
    M.config.cureLow, M.config.cureBuy, M.config.slack = 450, "herbs", 20
    eq(M.save(), true, "settings save")
    M.targets = {}
    M.config.cureLow, M.config.cureBuy, M.config.slack = 0, "either", 0
    eq(M.load(), true, "and load")
    eq(M.config.cureLow, 450, "cureLow comes back")
    eq(M.config.cureBuy, "herbs", "cureBuy comes back")
    eq(M.config.slack, 20, "slack comes back")
    eq(M.targets.ash, 500, "an item target comes back")
    eq(M.targets.Herbs, 300, "a heading target comes back")

    -- The right type and a value no command could set.
    disk = { targets = {}, config = { cureBuy = "rocks", cureLow = -5 } }
    M.load()
    eq(M.config.cureBuy, "either", "an unknown cureBuy falls back to either")
    eq(M.config.cureLow, 0, "a negative cureLow falls back to off")
    disk = { targets = {}, config = { cureLow = math.huge } }
    M.load()
    eq(M.config.cureLow, 0, "an infinite cureLow falls back to off")
    disk = { targets = {}, config = { cureLow = "500" } }
    M.config.cureLow = 0
    M.load()
    eq(M.config.cureLow, 0, "a cureLow of the wrong type is ignored")

    table.save, table.load, io.exists, M.file = realSave, realLoad,
        realExists, realFile
    M.targets = {}
    M.config.cureLow, M.config.cureBuy, M.config.slack = 0, "either", 0
end

-- ---------------------------------------------------------------------------
-- a typo is named when the target is set
-- ---------------------------------------------------------------------------

do
    local realSave = M.save
    M.save = function() return true end
    gmcp.IRE.Rift.List = { { name = "ash", amount = 318 } }
    raise("gmcp.IRE.Rift.List")
    M.targets = {}
    clearEcho()
    ok(M.setTarget("ashh", "500"), "a misspelt item target is still kept")
    ok(echoedText():find("restock forget ashh", 1, true),
        "...with a warning naming how to undo it")
    clearEcho()
    M.setTarget("kelp", "300")
    ok(not echoedText():find("no RIFT listing", 1, true),
        "a listed name at zero is not called a typo")
    clearEcho()
    M.setTarget("herbs", "500")
    ok(not echoedText():find("no RIFT listing", 1, true),
        "nor is a heading")
    M.targets = {}
    M.save = realSave
end

-- ---------------------------------------------------------------------------
-- a save that fails says so
-- ---------------------------------------------------------------------------

do
    -- Mudlet's table.save does not raise on a file it cannot open: it returns
    -- nil and a message, and returns nothing at all when it worked.
    local realSave, realFile = table.save, M.file
    M.file = "/harness/achaea-restock.lua"
    table.save = function() return nil, "Permission denied" end
    clearEcho()
    eq(M.save(), false, "a file that cannot be written is reported")
    ok(echoedText():find("could not save", 1, true), "...out loud")
    ok(echoedText():find("Permission denied", 1, true), "...with the reason")
    ok(echoedText():find("gone when Mudlet restarts", 1, true), "...and what it means")
    table.save = function() end
    eq(M.save(), true, "a save that works still says so")
    table.save, M.file = realSave, realFile
end

-- ---------------------------------------------------------------------------
-- a file that cannot be moved aside is not written over
-- ---------------------------------------------------------------------------

do
    -- os.rename returns nil when it fails; it does not raise. Carrying on to
    -- the write would put empty targets over the only copy of them.
    local realSave, realRename, realFile = table.save, os.rename, M.file
    local realLoaded = M.state.loaded
    local wrote = 0
    M.file = "/harness/achaea-restock.lua"
    M.state.loaded = "unreadable"
    table.save = function() wrote = wrote + 1 end
    os.rename = function() return nil, "Permission denied" end
    clearEcho()
    eq(M.save(), false, "a save that could not move the file aside reports it")
    ok(echoedText():find("could not move", 1, true), "...out loud")
    ok(echoedText():find("Permission denied", 1, true), "...with the reason")
    ok(echoedText():find("by hand", 1, true), "...and how to get out of it")
    eq(wrote, 0, "...and writes nothing")
    eq(M.state.loaded, "unreadable", "...so the next save tries the move again")
    clearEcho()
    M.diag()
    ok(echoedText():find("NOT being saved", 1, true)
        and echoedText():find("Permission denied", 1, true),
        "diag says so, with the reason, after the warning has scrolled away")
    os.rename = function() return true end
    eq(M.save(), true, "a move that works is followed by the save")
    eq(wrote, 1, "...exactly once")
    clearEcho()
    M.diag()
    ok(not echoedText():find("NOT being saved", 1, true),
        "...and diag stops saying it is blocked")
    table.save, os.rename, M.file = realSave, realRename, realFile
    M.state.loaded = realLoaded
end

-- ---------------------------------------------------------------------------
-- the generated package matches the source
-- ---------------------------------------------------------------------------

do
    -- build.py generates both the XML aliases and restock.COMMANDS from one
    -- table, so the in-game help cannot drift from what is installed. Loaded
    -- from source COMMANDS is empty, which is what M.help() says -- so the
    -- check is against the committed XML instead.
    local xml = io.open(HERE .. "/AchaeaRestock.xml", "r")
    ok(xml, "the committed XML is there")
    if xml then
        local text = xml:read("*a")
        xml:close()
        for _, command in ipairs({
            "restock%.fresh%(restock%.report%)", "restock%.help%(%)",
            "restock%.fresh%(restock%.listing%)",
            "restock%.fresh%(function%(%) restock%.reportCategory%(heading%) end%)",
            "restock%.targetList%(%)",
            "restock%.setTarget", "restock%.forget", "restock%.setSlack",
            "restock%.refresh%(%)", "restock%.diag%(%)",
            "restock%.curesFresh%(matches%[2%]%)",
        }) do
            ok(text:find(command), "the XML wires up " .. command)
        end
        -- Every heading the Lua knows is reachable from the alias that
        -- enumerates them. A heading added to one and not the other is a
        -- command that silently does nothing.
        for _, head in ipairs(M.CATEGORY_ORDER) do
            ok(text:find(head:lower(), 1, true),
                "the heading alias reaches " .. head)
        end
        ok(not text:find("<Trigger", 1, true),
            "no trigger is declared: this package reads no game output")
    end
end

-- ---------------------------------------------------------------------------

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
