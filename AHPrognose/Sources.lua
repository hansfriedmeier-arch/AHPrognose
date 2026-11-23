-- AHPrognose: reads the auction house scans YOU make with another addon. AHPrognose never scans by itself:
-- open the auction house, scan with Auctionator / Auctioneer / TSM as usual, close it - AHPrognose then takes the
-- prices over into its own history (which it keeps longer than the scan addon, so the forecasts get better).
--
--   Auctionator: its price database keeps, per item and day, the lowest and highest cheapest-listing price it saw
--                and the most units available (21 days by default). Read in full: the whole history at once.
--   Auctioneer:  its scan image (every auction of the last scan): today's cheapest unit price, median, units.
--   TSM:         TSM_API "dbminbuyout" for the items AHPrognose already knows or you carry: today's price only.
local _, ns = ...
local Sources = {}
ns.Sources = Sources

local floor = math.floor
local SCAN0 = time({ year = 2020, month = 1, day = 1, hour = 0 }) -- Auctionator's day 0 (local time)

function ns.Today() return floor((time() - SCAN0) / 86400) end

-- one day of one item into AHPrognose's history: { day, price, low, qty, src }
-- a day already known from a better source (Auctionator > Auctioneer > TSM) is not overwritten by a worse one
local RANK = { atr = 3, auc = 2, tsm = 1 }
function ns.PutDay(id, day, price, low, qty, src)
    if not (id and day and price and price > 0) then return end
    local item = ns.db.items[id]
    if not item then item = {}; ns.db.items[id] = item end
    for i = #item, 1, -1 do
        local e = item[i]
        if e[1] == day then
            if RANK[src] >= RANK[e[5]] then item[i] = { day, floor(price), floor(low or price), qty or 0, src } end
            return
        elseif e[1] < day then
            table.insert(item, i + 1, { day, floor(price), floor(low or price), qty or 0, src })
            return
        end
    end
    table.insert(item, 1, { day, floor(price), floor(low or price), qty or 0, src })
end

-- keep only the last N days (setting)
function ns.Prune(item)
    local keep = ns.db.settings.keepDays or 60
    local cutoff = ns.Today() - keep
    while item[1] and item[1][1] < cutoff do table.remove(item, 1) end
end

---------------------------------------------------------------------------
-- Auctionator
---------------------------------------------------------------------------
function Sources.HasAuctionator()
    return Auctionator and Auctionator.Database and type(Auctionator.Database.db) == "table" and true or false
end

-- Auctionator's keys: "12345" for plain items; gear ("g:..") and pets ("p:..") are left out (their price depends on
-- item level / pet level, which this addon doesn't model)
-- returns a step function for the chunked import: call it until it returns true
function Sources.AuctionatorImporter()
    local db = Auctionator.Database.db
    local keys = {}
    for k in pairs(db) do
        if type(k) == "string" and k:match("^%d+$") then keys[#keys + 1] = k end
    end
    local i, n = 0, 0
    return function(budget)
        local stop = math.min(#keys, i + budget)
        while i < stop do
            i = i + 1
            local e = db[keys[i]]
            if type(e) == "table" and type(e.h) == "table" then
                local id = tonumber(keys[i])
                for d, high in pairs(e.h) do
                    local day = tonumber(d)
                    local low = (e.l and e.l[d]) or high
                    -- the day's cheapest price (on the user's real data this predicted better than the middle of
                    -- the day's lowest and highest cheapest price: wow-addon-tools/ahp/atr_backtest.lua)
                    ns.PutDay(id, day, low, low, e.a and e.a[d] or 0, "atr")
                end
                n = n + 1
            end
        end
        return i >= #keys, n, #keys
    end
end

---------------------------------------------------------------------------
-- Auctioneer (Auc-Advanced): the last scan's image
---------------------------------------------------------------------------
function Sources.HasAuctioneer()
    return AucAdvanced and AucAdvanced.Scan and AucAdvanced.Scan.GetImageCopy and true or false
end

function Sources.AuctioneerImporter()
    local image = AucAdvanced.Scan.GetImageCopy() or {}
    local C = AucAdvanced.Const or {}
    local ID, COUNT, BUY = C.ITEMID or 23, C.COUNT or 11, C.BUYOUT or 17
    local per = {}
    for _, a in ipairs(image) do
        local id, count, buy = a[ID], a[COUNT] or 1, a[BUY] or 0
        if id and buy > 0 and count > 0 then
            local t = per[id]
            if not t then t = { p = {}, c = {}, qty = 0 }; per[id] = t end
            t.p[#t.p + 1] = buy / count
            t.c[#t.c + 1] = count
            t.qty = t.qty + count
        end
    end
    local ids = {}
    for id in pairs(per) do ids[#ids + 1] = id end
    local today, i = ns.Today(), 0
    return function(budget)
        local stop = math.min(#ids, i + budget)
        while i < stop do
            i = i + 1
            local t = per[ids[i]]
            local low = math.huge
            for _, p in ipairs(t.p) do if p < low then low = p end end
            -- same meaning as Auctionator's: the cheapest unit price of the scan
            ns.PutDay(ids[i], today, low, low, t.qty, "auc")
        end
        return i >= #ids, i, #ids
    end
end

---------------------------------------------------------------------------
-- TradeSkillMaster: only today's minimum buyout, for items AHPrognose already tracks or you carry
---------------------------------------------------------------------------
function Sources.HasTSM()
    return TSM_API and TSM_API.GetCustomPriceValue and true or false
end

function Sources.TSMImporter()
    local ids, seen = {}, {}
    for id in pairs(ns.db.items) do ids[#ids + 1] = id; seen[id] = true end
    for _, id in ipairs(ns.BagItems()) do if not seen[id] then ids[#ids + 1] = id end end
    local today, i = ns.Today(), 0
    return function(budget)
        local stop = math.min(#ids, i + budget)
        while i < stop do
            i = i + 1
            local ok, v = pcall(TSM_API.GetCustomPriceValue, "dbminbuyout", "i:" .. ids[i])
            if ok and type(v) == "number" and v > 0 then ns.PutDay(ids[i], today, v, v, 0, "tsm") end
        end
        return i >= #ids, i, #ids
    end
end

-- names of the sources found, for the UI
function Sources.Found()
    local t = {}
    if Sources.HasAuctionator() then t[#t + 1] = "Auctionator" end
    if Sources.HasAuctioneer() then t[#t + 1] = "Auctioneer" end
    if Sources.HasTSM() then t[#t + 1] = "TSM" end
    return t
end
