-- Copyright (C) 2026 PrincessSiren
--
-- This program is free software: you can redistribute it and/or modify it
-- under the terms of the GNU General Public License as published by the Free
-- Software Foundation, either version 3 of the License, or (at your option)
-- any later version.
--
-- This program is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
-- more details. You should have received a copy of the GNU General Public
-- License along with this program. If not, see <https://www.gnu.org/licenses/>.

-- AchaeaRestock -- what to buy before you go out.
--
-- Global namespace is `restock`, which is also the command prefix. It is *not*
-- `rift`, and that is the one naming decision here worth stating: RIFT is the
-- game's own verb, with INR, OUTR, IR and INFO RIFT around it (HELP 7.14), and
-- a Mudlet alias on `^rift$` shadows the command it is named after. `restock`
-- was typed in game before it was chosen -- "I'm sorry, I don't know what
-- "restock" does." -- so the front of that command line is free.
--
-- The package sends one thing, `IRE.Rift.Request` over GMCP, and triggers on
-- nothing. There is no output to parse, because the contents arrive as data.
--
-- Three things are worth knowing before reading further.
--
-- GMCP carries the amounts and not the categories. Mudlet asks for IRE.Rift in
-- its own opening handshake (Core.Supports.Set, src/ctelnet.cpp), so no
-- Core.Supports.Add is needed the way IRE.Target needs one -- but a frame is
-- { name, amount } per item and nothing else. Which of the nine headings a
-- name sits under is in the *listing* and only there, which is why M.CATEGORY
-- exists at all and why it is transcribed from a capture rather than recalled.
-- Type RIFT in game to print that listing again.
--
-- M.CATEGORY is therefore a lower bound, and knows only what one character
-- happened to be holding. A name the table has never seen is reported under
-- "Unsorted" rather than guessed at, and `restock diag` lists exactly those,
-- which is how the table grows from data. Do not extend it from memory: the
-- same rule as the Occultist kit's DEFENCE_OFF and the Explorer's skip list.
--
-- M.CAP is HELP 7.14's capacity table, which is the game stating a ceiling --
-- so "how much can I even hold" needs no number anybody invented. Note the
-- hole in it: the scroll's own contents paragraph lists minerals and its
-- capacity table never mentions them, so M.CAP.Minerals is nil on purpose and
-- the harness fails if it stops being nil. Ferrum sitting at exactly 1000 in
-- the capture is a number below a ceiling and nothing more.
--
-- Nothing ships with a target. A target is a preference rather than a game
-- fact -- nobody carries 2500 ash -- so the package cannot invent one for you,
-- and setting one is what opts a category into the report.

restock = restock or {}
local M = restock

M.VERSION = "0.1.0"

-- Both filled in by build.py, which appends them to the shipped copy of
-- this file. Loaded from source they stay empty and "source", which is
-- what the harness runs against and what `restock help` says out loud.
M.COMMANDS = M.COMMANDS or {}
M.BUILD = M.BUILD or "source"

-- Hung off the module table rather than kept in a file-local, so a script
-- recompile finds the live handler ids and tears them down instead of leaving
-- a second copy running over the top. Mudlet clears
-- mAnonymousEventHandlerFunctions only in Host::resetProfile.
M.state = M.state or {
    handlers    = {},
    lists       = 0,      -- IRE.Rift.List frames seen since this script loaded
    changes     = 0,      -- IRE.Rift.Change frames seen
    listedAt    = nil,    -- when the last full List landed
    requested   = false,  -- have we asked for one this session
    loaded      = "fresh",
    loadedCount = 0,
    savedAt     = nil,
}
local S = M.state

-- A recompile finds an M.state built by whichever version was installed
-- before, so a key that version had never heard of is still nil.
S.handlers = S.handlers or {}
S.loaded = S.loaded or "fresh"
S.loadedCount = S.loadedCount or 0

-- ---------------------------------------------------------------------------
-- what the game printed
-- ---------------------------------------------------------------------------

-- The game's own order, from the listing. Reports walk this rather than
-- sorting, so the output reads the way RIFT does.
M.CATEGORY_ORDER = {
    "Herbs", "Minerals", "Elixirs", "Salves", "Inks",
    "Reagent", "Ingredients", "Commodities", "Shipcomm",
}

-- name -> heading, transcribed from one RIFT listing (18th September 2026).
-- A lower bound: it holds what that character was carrying and nothing else.
M.CATEGORY = {
    -- Herbs
    ["ash"] = "Herbs", ["bayberry"] = "Herbs", ["bellwort"] = "Herbs",
    ["bloodroot"] = "Herbs", ["burdock"] = "Herbs", ["cohosh"] = "Herbs",
    ["echinacea"] = "Herbs", ["elm"] = "Herbs", ["ginger"] = "Herbs",
    ["ginseng"] = "Herbs", ["goldenseal"] = "Herbs", ["hawthorn"] = "Herbs",
    ["irid"] = "Herbs", ["kelp"] = "Herbs", ["kola"] = "Herbs",
    ["lobelia"] = "Herbs", ["myrrh gum"] = "Herbs", ["sileris"] = "Herbs",
    ["skullcap"] = "Herbs", ["valerian"] = "Herbs",
    -- Minerals
    ["bisemutum"] = "Minerals", ["calcite"] = "Minerals",
    ["ferrum"] = "Minerals", ["malachite"] = "Minerals",
    ["quartz"] = "Minerals",
    -- Elixirs
    ["frost"] = "Elixirs", ["health"] = "Elixirs", ["immunity"] = "Elixirs",
    ["levitation"] = "Elixirs", ["mana"] = "Elixirs", ["speed"] = "Elixirs",
    ["venom"] = "Elixirs",
    -- Salves
    ["caloric"] = "Salves", ["epidermal"] = "Salves", ["mass"] = "Salves",
    ["mending"] = "Salves", ["restoration"] = "Salves",
    -- Inks
    ["blue ink"] = "Inks", ["gold ink"] = "Inks", ["green ink"] = "Inks",
    ["purple ink"] = "Inks", ["red ink"] = "Inks", ["yellow ink"] = "Inks",
    -- Reagent (singular in the listing, with one row -- whether the heading
    -- agrees with its contents is not settled by one capture)
    ["wyrm tongue"] = "Reagent",
    -- Ingredients
    ["fat"] = "Ingredients", ["salt"] = "Ingredients",
    ["spice"] = "Ingredients", ["sugarcane"] = "Ingredients",
    -- Commodities
    ["cloth"] = "Commodities", ["fibre"] = "Commodities",
    ["iron"] = "Commodities", ["leather"] = "Commodities",
    ["rope"] = "Commodities", ["stone"] = "Commodities",
    ["wood"] = "Commodities",
    -- Shipcomm
    ["shipwood"] = "Shipcomm",
}

-- HELP 7.14's capacity table, by the heading it applies to.
--
-- Minerals is absent and must stay absent. 7.14 caps "each type of herb,
-- commodity, reagent, or crystal" and never says mineral, while its own
-- "What Goes In The Rift?" paragraph lists minerals separately from crystals.
-- Either they are the table's crystals or their cap is unstated, and one
-- capture cannot tell you which. The harness asserts this hole is still here.
M.CAP = {
    Herbs       = 2500,
    Elixirs     = 1000,
    Salves      = 1000,
    Inks        =  750,
    Reagent     = 2500,
    Ingredients = 1000,
    Commodities = 2500,
    Shipcomm    =  500,
}

-- "2000 sips of health and mana", named individually against the 1000 the rest
-- of the fluids get.
M.ITEM_CAP = {
    health = 2000,
    mana   = 2000,
}

-- Where 7.14 hedges. Printed beside a cap rather than silently dropped.
M.CAP_NOTE = {
    Elixirs = "7.14 says \"most\" curatives and fluids",
    Salves  = "7.14 says \"most\" curatives and fluids",
}

-- ---------------------------------------------------------------------------
-- state the game feeds
-- ---------------------------------------------------------------------------

-- name -> amount, rebuilt from every IRE.Rift.List and patched by every
-- IRE.Rift.Change. Never persisted: it is the game's answer, not a setting,
-- and a stale copy loaded at login would be worse than no copy at all.
M.rift = M.rift or {}

-- name or heading -> how many you want to be holding. Nothing here by default.
M.targets = M.targets or {}

local CONFIG_DEFAULTS = {
    -- How close to the target still counts as stocked. Buying 3 bloodroot is
    -- not worth a trip, and a list that says so every time gets ignored.
    slack = 0,
}

M.config = M.config or {}
for key, value in pairs(CONFIG_DEFAULTS) do
    if M.config[key] == nil then
        M.config[key] = value
    end
end

M.file = nil   -- set in start(), so this file still loads under luajit

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function info(text)
    cecho("<ansi_light_cyan>[restock] <reset>" .. text .. "\n")
end

local function warn(text)
    cecho("<ansi_light_cyan>[restock] <ansi_yellow>" .. text .. "<reset>\n")
end

local function plain(text)
    cecho(text .. "\n")
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Mudlet hands an unmatched optional capture over as "" rather than nil.
local function given(value)
    value = trim(value or "")
    if value == "" then
        return nil
    end
    return value
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

--- The console this is printing into, not a number somebody typed. Mudlet
--- re-wraps at the profile's own wrapAt, which the player sets, so a hardcoded
--- width is right only in the profile it was measured in. Both accessors are
--- guarded: they return `nil, message` for a window that is not there, and
--- neither exists under plain luajit.
function M.width()
    local best
    for _, fn in ipairs({ "getWindowWrap", "getColumnCount" }) do
        if type(_G[fn]) == "function" then
            local ok, value = pcall(_G[fn], "main")
            if ok and type(value) == "number" and value > 0 then
                best = (best and value < best) and value or (best or value)
            end
        end
    end
    return best or 72
end

--- Headings agree with the listing's capitalisation, so `restock HERBS` and
--- `restock herbs` both find one.
local function heading(word)
    word = trim(word or ""):lower()
    for _, name in ipairs(M.CATEGORY_ORDER) do
        if name:lower() == word then
            return name
        end
    end
    return nil
end

--- What this name or heading is capped at, or nil where the game has not said.
function M.capOf(what)
    if M.ITEM_CAP[what] then
        return M.ITEM_CAP[what]
    end
    local head = heading(what)
    if head then
        return M.CAP[head]
    end
    local category = M.CATEGORY[what]
    return category and M.CAP[category] or nil
end

--- The target that applies to one item: its own, else its heading's.
function M.targetOf(name)
    if M.targets[name] then
        return M.targets[name], "item"
    end
    local category = M.CATEGORY[name]
    if category and M.targets[category] then
        return M.targets[category], "category"
    end
    return nil, nil
end

-- ---------------------------------------------------------------------------
-- persistence
-- ---------------------------------------------------------------------------
--
-- Written and read as one envelope, with every key that save writes read back
-- by load. The Occultist kit lost two that way: what is saved but not loaded
-- comes back empty, and the next edit writes that emptiness over the file.

function M.save()
    if not M.file then
        return false
    end
    -- A file that would not parse is never written over. The targets in it
    -- were typed in by hand and this is the only copy of them.
    if S.loaded == "unreadable" then
        local kept = M.file .. ".bad"
        if pcall(os.rename, M.file, kept) then
            warn("kept the unreadable file as " .. kept)
        end
        S.loaded = "fresh"
    end
    local ok = pcall(table.save, M.file,
        { targets = M.targets, config = M.config })
    if not ok then
        warn("could not save your targets")
        return false
    end
    S.savedAt = os.time()
    return true
end

function M.load()
    if not M.file then
        return false
    end
    if not io.exists(M.file) then
        S.loaded, S.loadedCount = "fresh", 0
        return false
    end
    local stored = {}
    if not pcall(table.load, M.file, stored) or type(stored) ~= "table" then
        S.loaded, S.loadedCount = "unreadable", 0
        warn("could not read " .. M.file .. " -- your targets are NOT loaded. "
            .. "The file will be kept as " .. M.file
            .. ".bad rather than overwritten.")
        return false
    end
    if type(stored.targets) == "table" then
        M.targets = {}
        for key, value in pairs(stored.targets) do
            if type(key) == "string" and tonumber(value) then
                M.targets[key] = tonumber(value)
            end
        end
    end
    if type(stored.config) == "table" then
        for key, value in pairs(stored.config) do
            if CONFIG_DEFAULTS[key] ~= nil
                and type(value) == type(CONFIG_DEFAULTS[key]) then
                M.config[key] = value
            end
        end
    end
    S.loaded = "loaded"
    S.loadedCount = count(M.targets)
    return true
end

-- ---------------------------------------------------------------------------
-- GMCP
-- ---------------------------------------------------------------------------

--- One item's amount. Orion reads the same two fields and tonumber()s the
--- amount, which is inherited caution rather than a verified string: IRE.Target
--- is on record handing numbers over as strings, so this does not assume.
local function absorb(item)
    if type(item) ~= "table" then
        return false
    end
    local name, amount = item.name, tonumber(item.amount)
    if type(name) ~= "string" or not amount then
        return false
    end
    M.rift[name] = amount
    return true
end

function M.onList()
    local list = gmcp and gmcp.IRE and gmcp.IRE.Rift and gmcp.IRE.Rift.List
    if type(list) ~= "table" then
        return false
    end
    -- A List is the whole rift, so it replaces rather than merges: an item
    -- taken to zero may simply stop being listed.
    M.rift = {}
    for _, item in pairs(list) do
        absorb(item)
    end
    S.lists = (S.lists or 0) + 1
    S.listedAt = os.time()
    return true
end

function M.onChange()
    local item = gmcp and gmcp.IRE and gmcp.IRE.Rift and gmcp.IRE.Rift.Change
    if absorb(item) then
        S.changes = (S.changes or 0) + 1
        return true
    end
    return false
end

--- Ask for the whole rift. Whether Achaea sends a List unasked at login is not
--- established here, so start() asks rather than waiting to find out.
function M.refresh()
    if type(sendGMCP) ~= "function" then
        return false
    end
    sendGMCP("IRE.Rift.Request")
    S.requested = true
    return true
end

-- ---------------------------------------------------------------------------
-- the report
-- ---------------------------------------------------------------------------

--- Everything the rift holds, grouped the way the listing groups it. Names the
--- table has never seen come back under "Unsorted", which is what `restock
--- diag` prints and what M.CATEGORY grows from.
function M.grouped()
    local groups, unsorted = {}, {}
    for _, name in ipairs(M.CATEGORY_ORDER) do
        groups[name] = {}
    end
    for name, amount in pairs(M.rift) do
        local category = M.CATEGORY[name]
        if category and groups[category] then
            table.insert(groups[category], { name = name, amount = amount })
        else
            table.insert(unsorted, { name = name, amount = amount })
        end
    end
    local byName = function(a, b) return a.name < b.name end
    for _, rows in pairs(groups) do table.sort(rows, byName) end
    table.sort(unsorted, byName)
    return groups, unsorted
end

--- What is short, for one heading or for every heading with a target.
--- Returns rows of { name, have, target, buy }, worst shortfall first.
function M.shortfall(only)
    local rows = {}
    for name, amount in pairs(M.rift) do
        local category = M.CATEGORY[name]
        if not only or category == only or name == only then
            local target = M.targetOf(name)
            if target and amount + (M.config.slack or 0) < target then
                table.insert(rows, {
                    name   = name,
                    have   = amount,
                    target = target,
                    buy    = target - amount,
                })
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.buy ~= b.buy then return a.buy > b.buy end
        return a.name < b.name
    end)
    return rows
end

--- Headings that have a target of their own, in the listing's order.
local function watched()
    local list = {}
    for _, name in ipairs(M.CATEGORY_ORDER) do
        if M.targets[name] then
            table.insert(list, name)
        end
    end
    return list
end

local function haveStock()
    if count(M.rift) > 0 then
        return true
    end
    warn("nothing in the rift yet -- `restock refresh` asks the game for it.")
    return false
end

--- One shortfall row, padded into columns. Deliberately atomic: the columns
--- are runs of spaces and anything that re-joined words on single spaces
--- would eat them.
local function shortRow(row)
    return string.format("  <ansi_light_yellow>%-16s<reset> %5d / %-5d  "
        .. "<ansi_light_green>buy %d<reset>",
        row.name, row.have, row.target, row.buy)
end

function M.report()
    if not haveStock() then
        return false
    end
    local heads = watched()
    if #heads == 0 and count(M.targets) == 0 then
        warn("no targets set, so there is nothing to be short of.")
        info("`restock target herbs 500` sets one for a whole heading; "
            .. "`restock target bloodroot 800` sets one for a single item.")
        info("`restock all` prints what is in the rift regardless.")
        return false
    end
    local rows = M.shortfall()
    if #rows == 0 then
        info("<ansi_light_green>Everything with a target is stocked.<reset>")
        return true
    end
    info("Below target:")
    local current
    for _, row in ipairs(rows) do
        local category = M.CATEGORY[row.name] or "Unsorted"
        if category ~= current then
            current = category
            plain("<ansi_white>" .. category .. "<reset>")
        end
        plain(shortRow(row))
    end
    return true
end

function M.reportCategory(argument)
    local head = heading(given(argument) or "")
    if not head then
        warn("no such heading. One of: "
            .. table.concat(M.CATEGORY_ORDER, ", "))
        return false
    end
    if not haveStock() then
        return false
    end
    local groups = M.grouped()
    local rows = groups[head] or {}
    if #rows == 0 then
        info(head .. ": nothing in the rift.")
        return true
    end
    local target = M.targets[head]
    local cap = M.CAP[head]
    local header = head
    if target then
        header = header .. "  target " .. target
    end
    if cap then
        header = header .. "  cap " .. cap
    elseif head == "Minerals" then
        header = header .. "  cap unstated by 7.14"
    end
    info(header)
    for _, row in ipairs(rows) do
        local want = M.targetOf(row.name)
        if want and row.amount + (M.config.slack or 0) < want then
            plain(shortRow({
                name   = row.name,
                have   = row.amount,
                target = want,
                buy    = want - row.amount,
            }))
        else
            plain(string.format("  %-16s %5d", row.name, row.amount))
        end
    end
    return true
end

function M.listing()
    if not haveStock() then
        return false
    end
    local groups, unsorted = M.grouped()
    info("In the rift:")
    for _, head in ipairs(M.CATEGORY_ORDER) do
        local rows = groups[head]
        if rows and #rows > 0 then
            plain("<ansi_white>" .. head .. "<reset>")
            for _, row in ipairs(rows) do
                plain(string.format("  %-16s %5d", row.name, row.amount))
            end
        end
    end
    if #unsorted > 0 then
        plain("<ansi_light_magenta>Unsorted<reset>  "
            .. "(not in M.CATEGORY -- see `restock diag`)")
        for _, row in ipairs(unsorted) do
            plain(string.format("  %-16s %5d", row.name, row.amount))
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- targets
-- ---------------------------------------------------------------------------

function M.setTarget(what, amount)
    what = given(what)
    amount = tonumber(given(amount) or "")
    if not what or not amount then
        warn("usage: restock target <heading|item> <amount>")
        return false
    end
    if amount < 0 then
        warn("a target below zero is not a thing to want.")
        return false
    end
    local key = heading(what) or what:lower()
    -- A heading you typed is always a heading. An item name is taken as given
    -- even when M.CATEGORY has never seen it: the table is a lower bound, and
    -- refusing an unknown name would make it impossible to stock something the
    -- capture did not happen to contain.
    local cap = M.capOf(key)
    if cap and amount > cap then
        warn(string.format("%s caps at %d in the rift (HELP 7.14); "
            .. "keeping your target at %d anyway.", key, cap, amount))
    end
    M.targets[key] = amount
    M.save()
    info(string.format("target for <ansi_light_yellow>%s<reset> is now %d.",
        key, amount))
    return true
end

function M.forget(what)
    what = given(what)
    if not what then
        warn("usage: restock forget <heading|item>")
        return false
    end
    local key = heading(what) or what:lower()
    if M.targets[key] == nil then
        warn("no target set for " .. key .. ".")
        return false
    end
    M.targets[key] = nil
    M.save()
    info("target for " .. key .. " forgotten.")
    return true
end

function M.targetList()
    if count(M.targets) == 0 then
        info("No targets set. `restock target herbs 500` sets one.")
        return true
    end
    info("Targets:")
    for _, head in ipairs(M.CATEGORY_ORDER) do
        if M.targets[head] then
            plain(string.format("  <ansi_white>%-16s<reset> %5d   (heading)",
                head, M.targets[head]))
        end
    end
    local items = {}
    for key, value in pairs(M.targets) do
        if not heading(key) then
            table.insert(items, { name = key, amount = value })
        end
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    for _, row in ipairs(items) do
        plain(string.format("  <ansi_light_yellow>%-16s<reset> %5d",
            row.name, row.amount))
    end
    return true
end

function M.setSlack(argument)
    local value = tonumber(given(argument) or "")
    if not value or value < 0 then
        info("slack is " .. (M.config.slack or 0)
            .. " -- how far below target still counts as stocked.")
        return true
    end
    M.config.slack = value
    M.save()
    info("slack is now " .. value .. ".")
    return true
end

-- ---------------------------------------------------------------------------
-- reporting on itself
-- ---------------------------------------------------------------------------

function M.help()
    info("AchaeaRestock " .. M.VERSION .. " -- what to buy before you go out.")
    for _, row in ipairs(M.COMMANDS) do
        plain(string.format("  <ansi_light_yellow>%-34s<reset> %s",
            row.usage, row.help))
    end
    if #M.COMMANDS == 0 then
        plain("  (loaded from source, so the generated command list is empty)")
    end
    return true
end

function M.diag()
    info("AchaeaRestock " .. M.VERSION .. "  build " .. tostring(M.BUILD))
    plain("  handlers:    " .. #S.handlers
        .. "   lists " .. tostring(S.lists)
        .. "   changes " .. tostring(S.changes))
    plain("  last list:   " .. (S.listedAt
        and os.date("%Y-%m-%d %H:%M:%S", S.listedAt) or "never"))
    plain("  items held:  " .. count(M.rift))
    plain("  targets:     " .. count(M.targets)
        .. "   slack " .. tostring(M.config.slack))
    plain("  saved to:    " .. tostring(M.file))
    plain("  file at load: " .. S.loaded
        .. " (" .. S.loadedCount .. " targets)")
    plain("  Minerals cap: "
        .. (M.CAP.Minerals and tostring(M.CAP.Minerals)
            or "<ansi_light_magenta>unstated by HELP 7.14<reset>"))
    local _, unsorted = M.grouped()
    if #unsorted > 0 then
        plain("  <ansi_light_magenta>not in M.CATEGORY:<reset>")
        for _, row in ipairs(unsorted) do
            plain(string.format("    %-20s %5d", row.name, row.amount))
        end
        plain("  Add these from a RIFT listing that shows their heading, "
            .. "not from memory.")
    else
        plain("  every held item has a heading.")
    end
    return true
end

-- ---------------------------------------------------------------------------
-- start / stop
-- ---------------------------------------------------------------------------

local function teardown()
    for _, id in ipairs(S.handlers) do
        pcall(killAnonymousEventHandler, id)
    end
    S.handlers = {}
end

function M.start()
    teardown()
    -- Resolved here rather than at file scope so the module still loads under
    -- plain luajit, where getMudletHomeDir does not exist.
    if type(getMudletHomeDir) == "function" then
        M.file = getMudletHomeDir() .. "/achaea-restock.lua"
        M.load()
    end
    if type(registerAnonymousEventHandler) == "function" then
        S.handlers = {
            registerAnonymousEventHandler("gmcp.IRE.Rift.List", M.onList),
            registerAnonymousEventHandler("gmcp.IRE.Rift.Change", M.onChange),
        }
    end
    -- A List may well have landed before this script was recompiled, and
    -- Mudlet keeps the table either way -- so read it rather than waiting.
    M.onList()
    if count(M.rift) == 0 then
        M.refresh()
    end
    return true
end

function M.stop()
    teardown()
    return true
end

-- The script body re-runs whenever Mudlet recompiles it, so this also covers
-- editing and reinstalling without a profile restart.
M.start()

info("AchaeaRestock " .. M.VERSION
    .. " loaded -- type `restock help` for commands")
