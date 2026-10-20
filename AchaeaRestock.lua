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
-- The package sends `IRE.Rift.Request` over GMCP, with a blank line behind it
-- so the game answers (see M.refresh), and triggers on nothing. There is no
-- output to parse, because the contents arrive as data.
--
-- Three things are worth knowing before reading further.
--
-- GMCP carries the amounts and not the categories. Mudlet asks for IRE.Rift in
-- its own opening handshake (Core.Supports.Set, src/ctelnet.cpp), so no
-- Core.Supports.Add is needed the way IRE.Target needs one -- but a frame is
-- { name, amount } per item and nothing else. Which of the ten headings a
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
-- so "how much can I even hold" needs no number anybody invented. One row of
-- it is a reading rather than a quotation: the table caps "crystal" at 2500
-- and never says mineral, and M.CAP.Minerals takes that 2500 on the owner's
-- reading that the scroll's crystals are what RIFT heads Minerals. See M.CAP.
--
-- GMCP and the listing do not always agree on a name, either. GMCP says
-- `blueink` and `myrrh` where RIFT prints "blue ink" and "myrrh gum", so
-- M.GMCP_NAMES turns the one into the other as each frame lands, and
-- everything past absorb() -- headings, cure pairs, targets you type -- uses
-- the name RIFT prints.
--
-- Nothing ships with a target. A target is a preference rather than a game
-- fact -- nobody carries 2500 ash -- so the package cannot invent one for you,
-- and setting one is what opts a category into the report.
--
-- Since 0.2.0 there is a second kind of target, on a cure rather than an item.
-- HELP 13.7.1 gives every mineral a herb that does the same thing, word for
-- word, and server-side curing will use the other one when you run out of
-- your own (CURING FALLBACK, HELP 13.7.8). So 300 ash and 300 stannum are 600
-- sanity cures, and `restock cures 500` watches the pair rather than either.
-- M.CURES is the pairing.

restock = restock or {}
local M = restock

M.VERSION = "0.3.1"

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
    "Reagent", "Ingredients", "Commodities", "Shipcomm", "Misc",
}

-- name -> heading, transcribed from RIFT listings of 18th September, 15th
-- October and 19th October 2026. A lower bound: it holds what that character
-- was carrying and nothing else.
M.CATEGORY = {
    -- Herbs
    ["ash"] = "Herbs", ["bayberry"] = "Herbs", ["bellwort"] = "Herbs",
    ["bloodroot"] = "Herbs", ["burdock"] = "Herbs", ["cohosh"] = "Herbs",
    ["echinacea"] = "Herbs", ["elm"] = "Herbs", ["ginger"] = "Herbs",
    ["ginseng"] = "Herbs", ["goldenseal"] = "Herbs", ["hawthorn"] = "Herbs",
    ["irid"] = "Herbs", ["kelp"] = "Herbs", ["kola"] = "Herbs",
    ["lobelia"] = "Herbs", ["myrrh gum"] = "Herbs", ["pear"] = "Herbs",
    ["sileris"] = "Herbs", ["skullcap"] = "Herbs", ["valerian"] = "Herbs",
    -- Minerals
    ["aurum"] = "Minerals", ["bisemutum"] = "Minerals",
    ["calcite"] = "Minerals", ["cinnabar"] = "Minerals",
    ["ferrum"] = "Minerals", ["malachite"] = "Minerals",
    ["potash"] = "Minerals", ["quartz"] = "Minerals",
    ["realgar"] = "Minerals", ["stannum"] = "Minerals",
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
    -- Reagent. The listing prints "Reagent" over one row and "Reagents" over
    -- two, so the heading agrees with its count; the key stays singular so a
    -- target saved under it by 0.1.x still applies, and both spellings are
    -- accepted wherever a heading is typed.
    ["wyrm tongue"] = "Reagent", ["fish scales"] = "Reagent",
    ["lumic moss"] = "Reagent",
    -- Ingredients
    ["fat"] = "Ingredients", ["meat"] = "Ingredients",
    ["poultry"] = "Ingredients", ["salt"] = "Ingredients",
    ["spice"] = "Ingredients", ["sugarcane"] = "Ingredients",
    -- Commodities
    ["bone"] = "Commodities", ["cloth"] = "Commodities",
    ["coal"] = "Commodities", ["fibre"] = "Commodities",
    ["gems"] = "Commodities", ["gold"] = "Commodities",
    ["iron"] = "Commodities", ["ironore"] = "Commodities",
    ["leather"] = "Commodities", ["rawgems"] = "Commodities",
    ["rope"] = "Commodities", ["silver bar"] = "Commodities",
    ["silverore"] = "Commodities", ["steel"] = "Commodities",
    ["stone"] = "Commodities", ["wood"] = "Commodities",
    -- First listed 19th October 2026, at 1378; `restock diag` that day showed
    -- GMCP sending it under the same name at the same amount.
    ["rawstone"] = "Commodities",
    -- Shipcomm
    ["shipwood"] = "Shipcomm",
    -- Misc (first seen 15th October 2026; HELP 7.14 states no cap for it)
    ["gleam"] = "Misc",
}

-- Herb and mineral pairs that cure the same thing, from HELP 13.7.1. Every
-- mineral's line there is word for word one herb's line, and that identity
-- is the whole of the pairing: no row here was matched by what the two
-- sound like. Twenty-one minerals, so twenty-one rows, each mineral once.
-- Skullcap is in two, because it is two cures: eaten it is azurite's
-- deathsight, smoked it is malachite's rebounding.
--
-- These are the names the *rift* uses, which are not always the scroll's.
-- The rift says ash, elm and irid where 13.7.1 says Prickly Ash, Slippery Elm
-- and Irid Moss -- the scroll's own cross-references ("Ash See Prickly Ash")
-- make those three certain. "pear" is Prickly Pear by elimination: it is
-- under Herbs, and no other herb in 13.7.1 has the word in it.
--
-- Every mineral here is the short name HELP 18.5.1 gives it, and the set is
-- exactly that scroll's twenty-one. Each of the ten held so far reached GMCP
-- under that short name, stannum included, which was bought to test it.
-- Burdock is in the rift and not in 13.7.1 at all, so it pairs with nothing.
M.CURES = {
    { "ash",       "stannum" },     -- sanity afflictions
    { "bayberry",  "arsenic" },     -- gives blindness
    { "bellwort",  "cuprum" },      -- altruism
    { "bloodroot", "magnesium" },   -- paralysis and slickness
    { "cohosh",    "gypsum" },      -- gives insomnia
    { "echinacea", "dolomite" },    -- gives third eye
    { "elm",       "cinnabar" },    -- (smoked) curses and afflictions
    { "ginger",    "antimony" },    -- fluid level
    { "ginseng",   "ferrum" },      -- blood and skin
    { "goldenseal", "plumbum" },    -- disharmony
    { "hawthorn",  "calamine" },    -- gives deafness
    { "irid",      "potash" },      -- health and mana
    { "kelp",      "aurum" },       -- weakened muscles
    { "kola",      "quartz" },      -- waking at will
    { "lobelia",   "argentum" },    -- phobias and pathos
    { "myrrh gum", "bisemutum" },   -- lesson speed
    { "pear",      "calcite" },     -- breathing underwater
    { "sileris",   "quicksilver" }, -- (applied) Serpent fangs
    { "skullcap",  "azurite" },     -- (eaten) deathsight
    { "skullcap",  "malachite" },   -- (smoked) rebounding
    { "valerian",  "realgar" },     -- (smoked) disfigurement and slickness
}

-- HELP 7.14's capacity table, by the heading it applies to.
--
-- Minerals is the one row the scroll does not name. 7.14 caps "each type of
-- herb, commodity, reagent, or crystal" at 2500 and never says mineral, though
-- its own "What Goes In The Rift?" paragraph lists minerals and crystals
-- separately. Through 0.1.x the row was left empty for that reason. It is
-- 2500 since 0.2.0 on the owner's reading that 7.14's crystals are the
-- minerals, the same edible stones RIFT lists under that heading -- a reading
-- of the scroll, not a capture of the game refusing the 2501st, and M.CAP_NOTE
-- says so wherever the cap is printed. Potash at 2349 in a listing of 15th
-- October 2026 is the highest mineral on file, and agrees with it.
M.CAP = {
    Herbs       = 2500,
    Minerals    = 2500,
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
    Elixirs  = "7.14 says \"most\" curatives and fluids",
    Salves   = "7.14 says \"most\" curatives and fluids",
    Minerals = "7.14 says \"crystal\", read as minerals",
}

-- GMCP name -> the name RIFT prints, where the two differ. Each row was read
-- off one session on 15th October 2026: `restock diag` listed the GMCP names
-- it could not place, a RIFT listing taken minutes before printed the same
-- amounts under these names, and no other row in the listing had that amount.
-- Inks lose their space, myrrh gum loses "gum", and the two metals swap
-- around: GMCP's `goldbar` is RIFT's "gold" and its `silver` is "silverore".
-- Grown the same way M.CATEGORY is: from a diag line and a listing side by
-- side, never by guessing what a name probably becomes.
--
-- What GMCP sends looks like the item's short name, while RIFT prints
-- something longer. HELP 18.5 and 18.5.1 list the short names of every
-- harvestable herb and Transmutation mineral, and every herb and mineral
-- GMCP has sent matches its short name -- myrrh included, which 18.5 gives
-- as "Myrrh, a ball of myrrh gum". Inks and metals have no such scroll on
-- file, so for them the rows below are observation only.
--
-- One row is a prediction from that, and is the only one: 18.5 gives irid
-- moss the short name "Moss", while RIFT prints "irid". Nobody has held irid
-- since the package went live, so GMCP has not been seen sending either name.
-- If it sends "moss", this row is what keeps irid from reading as none held
-- in its pair with potash. If it sends "irid", the row never fires. Either
-- way, M.GMCP_PREDICTED tells `restock diag` to say which it has seen.
M.GMCP_NAMES = {
    blueink   = "blue ink",
    goldink   = "gold ink",
    greenink  = "green ink",
    purpleink = "purple ink",
    redink    = "red ink",
    yellowink = "yellow ink",
    myrrh     = "myrrh gum",
    goldbar   = "gold",
    silver    = "silverore",
    moss      = "irid",       -- predicted from HELP 18.5; see above
}

-- Rows of M.GMCP_NAMES that come from a scroll rather than a sighting. A
-- name here that arrives in a frame is recorded in S.gmcpSeen.
M.GMCP_PREDICTED = {
    moss = true,
}

-- Listed by RIFT and never sent over GMCP under any name. On 15th October
-- 2026 a `restock all` beside a listing held every row but these two, at a
-- time when GMCP had sent 71 items against the listing's 73. So the package
-- cannot see them, and to it they would read as none held: a target on one
-- would call for the whole amount every time. The report leaves them out and
-- `restock target` says why. Why these two is not known -- one is a
-- commodity and one the only ship commodity -- so the list grows from the
-- same comparison and nothing else.
M.GMCP_ABSENT = {
    ["silver bar"] = true,
    ["shipwood"]   = true,
}

--- The name RIFT prints for something, from either spelling of it.
function M.listingName(name)
    name = name:lower()
    return M.GMCP_NAMES[name] or name
end

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
    -- Herb and mineral together below this is short. 0 is off, and is where
    -- it starts: like every other target, it is a preference.
    cureLow = 0,
    -- What the cure report tells you to buy: "herbs", "minerals" or "either".
    -- Server-side curing eats one kind and falls back to the other, and which
    -- is a CURING TRANSMUTATION setting this package cannot read -- the
    -- STATUS line says "Curing Method: Concoctions" for herbs.
    cureBuy = "either",
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
    -- The listing prints "Reagents" once there are two of them.
    if word == "reagents" then
        word = "reagent"
    end
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

-- What every failed save ends with. The commands that call M.save go on to
-- say what they changed, and that is true: the change is in effect. What it
-- is not is kept, and this is the line that says so.
local NOT_KEPT = "The change is in effect now and will be gone when Mudlet restarts."

function M.save()
    if not M.file then
        return false
    end
    -- A file that would not parse is never written over. The targets in it
    -- were typed in by hand and this is the only copy of them.
    if S.loaded == "unreadable" then
        local kept = M.file .. ".bad"
        -- os.rename reports failure by returning nil, not by raising. If the
        -- file could not be moved aside, writing now would destroy the only
        -- copy, so nothing is written and the next save tries again.
        -- os.rename's second result is the reason, when there is one. An
        -- existing .bad from an earlier time is the likely one on Windows,
        -- where a rename does not replace its target.
        local ok, moved, why = pcall(os.rename, M.file, kept)
        if not (ok and moved) then
            S.moveFailed = tostring(why or moved or "no reason given")
            warn("could not move the unreadable file aside (" .. S.moveFailed
                .. "), so nothing was written over it. " .. NOT_KEPT
                .. " To fix it, move or delete " .. kept .. " or " .. M.file
                .. " by hand; the next change saves.")
            return false
        end
        S.moveFailed = nil
        warn("kept the unreadable file as " .. kept)
        S.loaded = "fresh"
    end
    -- table.save reports a file it could not open by returning nil and a
    -- message, not by raising, and returns nothing when it worked. So the
    -- message is the sign of a failure and pcall's own result is not.
    local ok, _, failed = pcall(table.save, M.file,
        { targets = M.targets, config = M.config })
    if not ok or failed ~= nil then
        warn("could not save your targets to " .. M.file .. " ("
            .. tostring(failed or "no reason given") .. "). " .. NOT_KEPT)
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
            .. "The file is not overwritten: it is moved to " .. M.file
            .. ".bad before the next save, and nothing is written if that fails.")
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
    -- The right type is not yet a value the commands could have set. A file
    -- edited by hand gets the default rather than a setting nothing can
    -- print sensibly.
    local buy = M.config.cureBuy
    if buy ~= "herbs" and buy ~= "minerals" and buy ~= "either" then
        M.config.cureBuy = CONFIG_DEFAULTS.cureBuy
    end
    local low = M.config.cureLow
    if low ~= low or low < 0 or low == math.huge then
        M.config.cureLow = CONFIG_DEFAULTS.cureLow
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
    if M.GMCP_PREDICTED[name:lower()] then
        S.gmcpSeen = S.gmcpSeen or {}
        S.gmcpSeen[name:lower()] = true
    end
    M.rift[M.listingName(name)] = amount
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
    -- A report that asked for this List answers now.
    if S.pending then
        local report = S.pending
        S.pending = nil
        if S.pendingTimer and type(killTimer) == "function" then
            pcall(killTimer, S.pendingTimer)
        end
        S.pendingTimer = nil
        report()
    end
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

--- Ask for the whole rift over GMCP, and nothing else. start() uses this:
--- whether Achaea sends a List unasked at login is not established here, so
--- it asks rather than waiting to find out, and at load it may be sitting at
--- the login prompt, where a blank line is not obviously harmless.
function M.request()
    if type(sendGMCP) ~= "function" then
        return false
    end
    sendGMCP("IRE.Rift.Request")
    S.requested = true
    return true
end

--- Ask for the whole rift and get the answer sent now: the request, then a
--- blank line. Everything the player asks for goes through here.
---
--- On 15th October 2026 a request sent on its own in a quiet room was
--- answered after 10.07s, arriving with the next line of room text. Two
--- requests sent back to back were answered 1.20s after the second, with a
--- prompt. Achaea seems to hold the answer until something else gives it a
--- reason to send, so in a quiet room every report fell back to stale frames.
--- That is a reading of two timings, not a measured mechanism. A blank line is
--- a command the game answers with a prompt, and with it the List came back
--- at once on the first live run.
---
--- send("") sends a bare newline at Mudlet-4.22.0 and -5.0.1 (Host::send,
--- "allow sending blank commands"). Disconnected, cTelnet::socketOutRaw
--- drops it on !mpSocket->isValid() at both tags. sysDataSendRequest is still
--- raised with "", so other packages see a blank command go by. Under the
--- default echo settings nothing is printed but the prompt. With command echo
--- set to Always, and the IRE driver bugfix off or forced LF after the prompt
--- on, an empty command line is printed as well.
function M.refresh()
    if not M.request() then
        return false
    end
    if type(send) == "function" then
        send("", false)
    end
    return true
end

-- How long a report waits for the List it asked for before answering from
-- what it already holds.
M.FRESH_WAIT = 3

--- Run a report against a List asked for now, rather than the frames held.
---
--- Buying into the rift sends no IRE.Rift.Change. On 15th October 2026, 1000
--- health bought straight into it left the frames at 1000 while RIFT printed
--- 2000, and only a `restock refresh` brought the 2000 in. So between a
--- shop and the next List every report was stale, and stale in the one
--- direction that matters: it still called for what had just been bought.
--- Asking costs one GMCP round trip. If no List comes back in FRESH_WAIT
--- seconds the report runs anyway, and says what it is reading from.
---
--- Without a timer to wait on -- plain luajit -- it runs at once.
function M.fresh(report)
    if type(tempTimer) ~= "function" or not M.refresh() then
        return report()
    end
    if S.pendingTimer and type(killTimer) == "function" then
        pcall(killTimer, S.pendingTimer)
    end
    S.pending = report
    S.pendingTimer = tempTimer(M.FRESH_WAIT, function()
        S.pendingTimer = nil
        if S.pending then
            local late = S.pending
            S.pending = nil
            warn(string.format("no answer to IRE.Rift.Request in %ds, so this "
                .. "is from the last frames held -- anything bought since is "
                .. "missing.", M.FRESH_WAIT))
            late()
        end
    end)
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
    local function consider(name, amount)
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
    for name, amount in pairs(M.rift) do
        consider(name, amount)
    end
    -- An item at zero is not in the rift's frames at all, so the loop above
    -- never meets it -- and none held is the shortfall that matters most.
    -- Through 0.1.x a target on one was silently never reported. A heading
    -- target cannot be helped this way, since nothing says which names a
    -- heading would hold, but an item target names its item.
    for name in pairs(M.targets) do
        if M.rift[name] == nil and not heading(name)
            and not M.GMCP_ABSENT[name] then
            consider(name, 0)
        end
    end
    table.sort(rows, function(a, b)
        if a.buy ~= b.buy then return a.buy > b.buy end
        return a.name < b.name
    end)
    return rows
end

--- Every pair in M.CURES with what you hold of each half. With a threshold,
--- only the pairs short of it, worst first; with none, all of them in the
--- table's order. Rows are { herb, mineral, herbHave, mineralHave, have, buy }.
function M.cureShortfall(threshold)
    local rows = {}
    for _, pair in ipairs(M.CURES) do
        local herb, mineral = pair[1], pair[2]
        local herbHave = M.rift[herb] or 0
        local mineralHave = M.rift[mineral] or 0
        local have = herbHave + mineralHave
        local row = {
            herb        = herb,
            mineral     = mineral,
            herbHave    = herbHave,
            mineralHave = mineralHave,
            have        = have,
            buy         = threshold and math.max(threshold - have, 0) or 0,
        }
        if not threshold then
            table.insert(rows, row)
        elseif have + (M.config.slack or 0) < threshold then
            table.insert(rows, row)
        end
    end
    if threshold then
        table.sort(rows, function(a, b)
            if a.buy ~= b.buy then return a.buy > b.buy end
            if a.herb ~= b.herb then return a.herb < b.herb end
            return a.mineral < b.mineral
        end)
    end
    return rows
end

--- Which half of a pair the report says to buy, or nil for "either".
local function buyName(row)
    if M.config.cureBuy == "herbs" then
        return row.herb
    elseif M.config.cureBuy == "minerals" then
        return row.mineral
    end
    return nil
end

--- One pair, padded into columns. Atomic for the same reason shortRow is.
local function cureRow(row, short)
    local line = string.format("  %-10s %4d + %-11s %4d = %4d",
        row.herb, row.herbHave, row.mineral, row.mineralHave, row.have)
    if short then
        local name = buyName(row)
        return "<ansi_light_yellow>" .. line .. "<reset>  <ansi_light_green>buy "
            .. row.buy .. (name and (" " .. name) or "") .. "<reset>"
    end
    return line
end

local function printCures(rows, threshold)
    info(string.format("Cures below %d, herb + mineral (HELP 13.7.1):", threshold))
    for _, row in ipairs(rows) do
        plain(cureRow(row, true))
    end
    if M.config.cureBuy ~= "herbs" and M.config.cureBuy ~= "minerals" then
        plain("  either half will do; `restock cures herbs|minerals` names one.")
    end
end

--- The alias's way into M.cures: the two forms that report wait for a fresh
--- List, and the forms that change a setting do not.
function M.curesFresh(argument)
    local arg = given(argument)
    if arg == nil or arg:lower() == "all" then
        return M.fresh(function() return M.cures(argument) end)
    end
    return M.cures(argument)
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

--- Whether there is a rift to report on: a List has arrived, or a Change has.
--- An empty List counts. It is the rift of a character holding nothing, and
--- through 0.3.0 this asked for items rather than a List, so that character
--- got a refresh warning however many times they refreshed, and never the
--- shopping list an item target or `restock cures` would have given them.
local function haveStock()
    if count(M.rift) > 0 or (S.lists or 0) > 0 then
        return true
    end
    warn("the game has not sent your rift yet -- `restock refresh` asks for it.")
    return false
end

--- How far one item is from its HELP 7.14 cap, as the words a row ends with,
--- or "" where the scroll states no cap for it (Misc, and anything Unsorted).
--- The buy figure only reaches the target; this is how much more the rift
--- would still take. Above the cap is printed as such rather than as a
--- negative, since it means M.CAP is wrong for that item -- 7.14 says "most"
--- fluids, not all of them.
local function capRoom(name, amount)
    local cap = M.capOf(name)
    if not cap then
        return ""
    end
    if amount > cap then
        return string.format("  <ansi_light_magenta>%d over 7.14's %d<reset>",
            amount - cap, cap)
    end
    if amount == cap then
        return "  at cap"
    end
    return string.format("  %4d to cap", cap - amount)
end

-- What shortRow puts between the amount and the cap column, as blanks, so a
-- stocked row in the same heading lines its cap up under a short one's.
local SHORT_GAP = #string.format(" / %-5d  buy %-5d", 0, 0)

--- One shortfall row, padded into columns. Deliberately atomic: the columns
--- are runs of spaces and anything that re-joined words on single spaces
--- would eat them.
local function shortRow(row)
    return string.format("  <ansi_light_yellow>%-16s<reset> %5d / %-5d  "
        .. "<ansi_light_green>buy %-5d<reset>",
        row.name, row.have, row.target, row.buy) .. capRoom(row.name, row.have)
end

--- One row of what is held, with how far it is from its cap. `gap` pads it to
--- line up with shortRow where the two share a heading.
local function heldRow(name, amount, gap)
    return string.format("  %-16s %5d", name, amount)
        .. string.rep(" ", gap or 0) .. capRoom(name, amount)
end

--- `restock cures [n|all|herbs|minerals|either]`. One alias and one function,
--- because Mudlet fires every alias that matches: four aliases on the same
--- prefix would need regexes that exclude each other, and this does not.
function M.cures(argument)
    local arg = given(argument)
    arg = arg and arg:lower()
    local number = arg and tonumber(arg)
    if number then
        if number < 0 then
            warn("a threshold below zero is not a thing to want.")
            return false
        end
        M.config.cureLow = number
        M.save()
        if number == 0 then
            info("cure pairs are no longer watched.")
        else
            info(string.format("a cure with under %d herb + mineral is now short.",
                number))
        end
        return true
    end
    if arg == "herbs" or arg == "herb" or arg == "minerals" or arg == "mineral"
        or arg == "either" then
        M.config.cureBuy = (arg == "herb" and "herbs")
            or (arg == "mineral" and "minerals") or arg
        M.save()
        info("the cure report now says to buy " .. M.config.cureBuy .. ".")
        return true
    end
    if arg and arg ~= "all" then
        warn("usage: restock cures [<n>|all|herbs|minerals|either]")
        return false
    end
    if not haveStock() then
        return false
    end
    local low = M.config.cureLow or 0
    if arg == "all" then
        local rows = M.cureShortfall()
        info("Every cure pair, herb + mineral (HELP 13.7.1):")
        for _, row in ipairs(rows) do
            local short = low > 0 and row.have + (M.config.slack or 0) < low
            if short then
                row.buy = low - row.have
            end
            plain(cureRow(row, short))
        end
        return true
    end
    if low <= 0 then
        warn("no cure threshold set, so there is nothing to be short of.")
        info("`restock cures 500` watches every herb and mineral pair; "
            .. "`restock cures all` prints them regardless.")
        return false
    end
    local rows = M.cureShortfall(low)
    if #rows == 0 then
        info(string.format("<ansi_light_green>Every cure has at least %d, "
            .. "herb and mineral together.<reset>", low))
        return true
    end
    printCures(rows, low)
    return true
end

function M.report()
    if not haveStock() then
        return false
    end
    local low = M.config.cureLow or 0
    if count(M.targets) == 0 and low <= 0 then
        warn("no targets set, so there is nothing to be short of.")
        info("`restock target herbs 500` sets one for a whole heading; "
            .. "`restock target bloodroot 800` sets one for a single item.")
        info("`restock cures 500` watches each herb and the mineral that "
            .. "cures the same thing, together.")
        info("`restock all` prints what is in the rift regardless.")
        return false
    end
    local rows = M.shortfall()
    local cures = low > 0 and M.cureShortfall(low) or {}
    if #rows == 0 and #cures == 0 then
        info("<ansi_light_green>Everything with a target is stocked.<reset>")
        return true
    end
    if #rows > 0 then
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
    end
    if #cures > 0 then
        printCures(cures, low)
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
        if M.CAP_NOTE[head] then
            header = header .. " (" .. M.CAP_NOTE[head] .. ")"
        end
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
            plain(heldRow(row.name, row.amount, SHORT_GAP))
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
                plain(heldRow(row.name, row.amount))
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
    local key = heading(what) or M.listingName(what)
    -- A heading you typed is always a heading. An item name is taken as given
    -- even when M.CATEGORY has never seen it: the table is a lower bound, and
    -- refusing an unknown name would make it impossible to stock something the
    -- capture did not happen to contain.
    local cap = M.capOf(key)
    if cap and amount > cap then
        warn(string.format("%s caps at %d in the rift (HELP 7.14); "
            .. "keeping your target at %d anyway.", key, cap, amount))
    end
    -- Since 0.2.0 an item target on something absent from the frames reads as
    -- none held, so a misspelt one would call for the whole amount for ever.
    -- A name no listing has filed and the rift is not holding is said out
    -- loud: it may be real (M.CATEGORY is a lower bound), or a typo.
    if not heading(what) and not M.CATEGORY[key] and M.rift[key] == nil
        and not M.GMCP_ABSENT[key] then
        warn(key .. " is in no RIFT listing on file and not in the rift now, "
            .. "so it reports as none held. If that is a typo, `restock forget "
            .. key .. "`.")
    end
    if M.GMCP_ABSENT[key] then
        warn(key .. " is in RIFT listings but never sent over GMCP, so the "
            .. "report cannot see it. Keeping the target; check it with RIFT.")
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
    local key = heading(what) or M.listingName(what)
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
    plain("  cures:       " .. ((M.config.cureLow or 0) > 0
        and ("short below " .. M.config.cureLow) or "off")
        .. "   buy " .. tostring(M.config.cureBuy))
    plain("  saved to:    " .. tostring(M.file))
    plain("  file at load: " .. S.loaded
        .. " (" .. S.loadedCount .. " targets)")
    -- The warning that said so has scrolled away by the time anyone asks.
    if S.moveFailed then
        plain("  <ansi_light_red>NOT being saved<reset>: the unreadable file "
            .. "could not be moved aside (" .. S.moveFailed .. ")")
    end
    local _, unsorted = M.grouped()
    if #unsorted > 0 then
        plain("  <ansi_light_magenta>not in M.CATEGORY:<reset>")
        for _, row in ipairs(unsorted) do
            plain(string.format("    %-20s %5d", row.name, row.amount))
        end
        plain("  Set these beside a RIFT listing, not from memory. GMCP may "
            .. "spell a name differently (blueink is \"blue ink\"): the "
            .. "amount says which row it is. Then M.GMCP_NAMES or M.CATEGORY.")
    else
        plain("  every held item has a heading.")
    end
    for name in pairs(M.GMCP_PREDICTED) do
        local seen = S.gmcpSeen and S.gmcpSeen[name]
        plain(string.format("  GMCP name %s -> %s: %s", name, M.GMCP_NAMES[name],
            seen and "<ansi_light_green>seen this session<reset>"
                or "predicted from HELP 18.5, not seen yet"))
    end
    local absent, arrived = {}, {}
    for name in pairs(M.GMCP_ABSENT) do
        table.insert(M.rift[name] and arrived or absent, name)
    end
    table.sort(absent)
    table.sort(arrived)
    if #absent > 0 then
        plain("  listed by RIFT, never sent over GMCP: " .. table.concat(absent, ", "))
    end
    if #arrived > 0 then
        plain("  <ansi_light_magenta>now sent over GMCP after all:<reset> "
            .. table.concat(arrived, ", ") .. " -- M.GMCP_ABSENT is out of date")
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
            registerAnonymousEventHandler("sysUninstall", M.onUninstall),
        }
    end
    -- A List may well have landed before this script was recompiled, and
    -- Mudlet keeps the table either way -- so read it rather than waiting.
    M.onList()
    if count(M.rift) == 0 then
        M.request()
    end
    return true
end

function M.stop()
    teardown()
    if S.pendingTimer and type(killTimer) == "function" then
        pcall(killTimer, S.pendingTimer)
    end
    S.pending, S.pendingTimer = nil, nil
    return true
end

-- The name Mudlet knows the package by, which is what its uninstall event
-- carries. build.py has the same string; the harness holds the two together.
M.PACKAGE = "AchaeaRestock"

--- Removing the package takes its aliases and its script away and leaves
--- everything created at runtime behind, still running with no command left
--- to stop it. `sysUninstall` rather than `sysUninstallPackage`: it is the
--- one event raised however the package was installed, and one installed
--- through the Module Manager never raises the other. Mudlet raises it
--- before it removes anything, and for every package, so the name is
--- checked. An upgrade or a module sync is an uninstall and an install:
--- the new copy's script starts it again.
function M.onUninstall(_, name)
    if name ~= M.PACKAGE then
        return false
    end
    M.stop()
    return true
end

-- The script body re-runs whenever Mudlet recompiles it, so this also covers
-- editing and reinstalling without a profile restart.
M.start()

info("AchaeaRestock " .. M.VERSION
    .. " loaded -- type `restock help` for commands")
