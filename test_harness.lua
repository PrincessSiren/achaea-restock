-- Drives AchaeaRestock.lua under plain luajit, with enough of Mudlet stubbed
-- to run it. Mudlet embeds Lua 5.1 and luajit is that exact dialect.
--
-- What this proves is the logic and the tables. What it cannot prove is that
-- Achaea sends what the GMCP fixtures below say it sends: those are modelled
-- on Orion's own IRE.Rift handlers (external-addons/orion/Orion.xml in the
-- workshop), which is the best evidence available without a live profile, and
-- not a capture. The amount arriving as a *string* is tested for that reason
-- -- IRE.Target is on record handing numbers over as strings, so neither shape
-- is assumed.
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
    eq(#M.CATEGORY_ORDER, 9, "nine headings in the listing's order")
    eq(M.CATEGORY_ORDER[1], "Herbs", "Herbs is first, as RIFT prints it")
    eq(M.CATEGORY_ORDER[9], "Shipcomm", "Shipcomm is last")

    -- Every heading in the order list is one something is actually filed
    -- under, and every category used is a heading in the order list. A typo in
    -- either direction shows up here rather than as a silently empty section.
    local used = {}
    local total = 0
    for _, category in pairs(M.CATEGORY) do
        used[category] = (used[category] or 0) + 1
        total = total + 1
    end
    eq(total, 56, "56 names transcribed from RIFT 2026-09-18.txt")
    for _, head in ipairs(M.CATEGORY_ORDER) do
        ok(used[head], "heading has at least one name: " .. head)
        used[head] = nil
    end
    eq(next(used), nil, "no name filed under a heading not in the order list")

    -- The per-heading counts the capture printed.
    local want = {
        Herbs = 20, Minerals = 5, Elixirs = 7, Salves = 5, Inks = 6,
        Reagent = 1, Ingredients = 4, Commodities = 7, Shipcomm = 1,
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
end

-- ---------------------------------------------------------------------------
-- the hole in HELP 7.14, which must stay a hole
-- ---------------------------------------------------------------------------

do
    -- 7.14 caps "each type of herb, commodity, reagent, or crystal" and never
    -- says mineral, while its own contents paragraph lists minerals separately
    -- from crystals. Either they are the table's crystals or their cap is
    -- unstated, and one capture cannot tell you which.
    --
    -- This assertion is the point of the test, not a side effect of it:
    -- 2500 is the obvious number to fill in and it may well be right, which is
    -- exactly why it must not be filled in from here. Close it with a capture
    -- -- fill the rift past 2500 and read what the game says -- and change
    -- this test in the same commit.
    eq(M.CAP.Minerals, nil, "Minerals has no cap: HELP 7.14 does not state one")

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
    eq(M.capOf("ferrum"), nil, "a mineral has no cap to take")
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
-- a name the table has never seen
-- ---------------------------------------------------------------------------

do
    -- M.CATEGORY holds what one character happened to be carrying, so a name
    -- outside it is expected rather than exceptional. It must surface, not
    -- vanish and not be guessed into a heading.
    gmcp.IRE.Rift.List = {
        { name = "ash", amount = 404 },
        { name = "moss", amount = 12 },
    }
    raise("gmcp.IRE.Rift.List")
    local groups, unsorted = M.grouped()
    eq(#unsorted, 1, "an unknown name lands in Unsorted")
    eq(unsorted[1].name, "moss", "...under its own name")
    eq(#groups.Herbs, 1, "...and is not filed under a heading")

    clearEcho()
    M.diag()
    ok(echoedText():find("moss"), "diag names what has no heading")
    ok(echoedText():find("unstated by HELP 7.14"),
        "diag says the minerals cap is a hole")
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
    ok(M.setTarget("moss", "50"), "an unknown item may still have a target")
    eq(M.targets.moss, 50, "...and it is kept")

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
    ok(M.reportCategory("minerals"), "a heading with nothing in it prints")
    ok(echoedText():find("nothing in the rift"), "...and says it is empty")

    ok(M.listing(), "the full listing prints")

    -- An empty rift is a state the package is in at every login until the
    -- first frame lands, so every report has to survive it.
    M.rift = {}
    clearEcho()
    ok(not M.report(), "the report declines on an empty rift")
    ok(echoedText():find("refresh"), "...pointing at the command that fills it")
    ok(not M.listing(), "the listing declines on an empty rift")
    ok(not M.reportCategory("herbs"), "a heading declines on an empty rift")
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
    sent = {}
    M.rift = {}
    gmcp.IRE.Rift.List = nil
    M.start()
    eq(sent[1], "IRE.Rift.Request", "an empty rift is asked for at start")
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
            "restock%.report%(%)", "restock%.help%(%)", "restock%.listing%(%)",
            "restock%.reportCategory", "restock%.targetList%(%)",
            "restock%.setTarget", "restock%.forget", "restock%.setSlack",
            "restock%.refresh%(%)", "restock%.diag%(%)",
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
