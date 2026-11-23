-- AHPrognose core: saved data, taking over your scans, forecasts, signals, accuracy, slash command.
local ADDON, ns = ...
local Model = ns.Model

ns.HORIZONS = { 1, 3, 7 }
ns.DEFAULTS = {
    autoImport = true,   -- take the prices over when the auction house closes and at login
    tooltip = true,      -- forecast lines in item tooltips
    alerts = true,       -- chat message when a watched item is cheap
    minConf = 2,         -- lists show forecasts from this confidence on (1 low, 2 medium, 3 high)
    minQty = 3,          -- lists: at least this many units on sale (a single listing says little)
    buyPct = 15,         -- buy chance: cheapest price this many % under the 3-day forecast
    sellPct = 10,        -- sell tip: forecast this many % above / below today
    keepDays = 60,       -- how many days of history AHPrognose keeps
    horizon = 3,         -- main forecast shown in lists and tooltips (1, 3 or 7 days)
}

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7AHPrognose|r " .. msg) end
ns.Print = Print

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
function ns.Money(c)
    if not c then return "-" end
    c = math.floor(c + 0.5)
    local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    if g > 0 then return ("%d|cffffd700g|r %02d|cffc7c7cfs|r"):format(g, s) end
    if s > 0 then return ("%d|cffc7c7cfs|r %02d|cffeda55fc|r"):format(s, k) end
    return ("%d|cffeda55fc|r"):format(k)
end

-- items the client hasn't loaded yet return nothing at first: ask the client to load them and redraw once they arrive
local pending, redrawQueued = {}, false
local function Want(id)
    if pending[id] then return end
    pending[id] = true
    C_Item.RequestLoadItemDataByID(id)
end
function ns.OnItemLoaded(id)
    if not pending[id] then return end
    pending[id] = nil
    if redrawQueued then return end
    redrawQueued = true
    C_Timer.After(0.3, function() -- many items arrive together: one redraw for all of them
        redrawQueued = false
        if ns.RefreshUI then ns.RefreshUI() end
        if ns.RefreshDetail then ns.RefreshDetail() end
    end)
end

function ns.ItemName(id)
    local name = C_Item.GetItemNameByID(id)
    if name then ns.db.names[id] = name; return name end
    Want(id)
    return ns.db.names[id] or ("Item " .. id)
end

-- item icon: the item's own icon (GetItemIconByID, else GetItemInfoInstant); until it is known a question mark
local QUESTION = 134400 -- INV_Misc_QuestionMark
local icons = {}
function ns.ItemIcon(id)
    local icon = icons[id]
    if icon then return icon end
    icon = C_Item.GetItemIconByID(id)
    if not icon then icon = select(5, C_Item.GetItemInfoInstant(id)) end
    if icon then icons[id] = icon; return icon end
    Want(id)
    return QUESTION
end

function ns.BagItems()
    local out, seen = {}, {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and not seen[id] then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if not (info and info.isBound) then seen[id] = true; out[#out + 1] = id end
            end
        end
    end
    return out
end

ns.CONF_TEXT = { "niedrig", "mittel", "hoch" }
ns.CONF_COLOR = { "|cffff7f50", "|cffffd100", "|cff40ff40" }

---------------------------------------------------------------------------
-- forecasts (computed when needed, cached until the next import)
---------------------------------------------------------------------------
local cache = {}
function ns.Invalidate() wipe(cache) end -- (recipe strings are parsed once, see ns.Recipes)

function ns.Forecast(id)
    local c = cache[id]
    if c ~= nil then return c or nil end
    local hist = ns.db.items[id]
    local f, why = nil, "keine Scans"
    if hist then f, why = Model.Forecast(hist, ns.Today(), ns.HORIZONS, ns.db.weekday) end
    -- market signals (material cost of crafted items, sudden flood of auctions): next-day forecast only
    if f then Model.ApplyShift(f, Model.MarketShift(hist, ns.Recipes(id), ns.VENDOR, ns.PriceOn)) end
    cache[id] = f or false
    if not f then cache["why" .. id] = why end
    return f, why
end
function ns.WhyNot(id) return cache["why" .. id] end

-- an item's recipes as { {made, mat, n, ...}, ... }: Recipes.lua keeps them as short strings, read on first use
local parsed = {}
function ns.Recipes(id)
    local r = parsed[id]
    if r ~= nil then return r or nil end
    local raw = ns.RECIPES and ns.RECIPES[id]
    if type(raw) == "table" then return raw end
    if type(raw) ~= "string" then return nil end
    r = {}
    for one in raw:gmatch("[^;]+") do
        local t = {}
        for v in one:gmatch("%d+") do t[#t + 1] = tonumber(v) end
        r[#r + 1] = t
    end
    parsed[id] = r
    return r
end

-- the cheapest price of an item on a given scan day (searched from the newest day back), or nil
function ns.PriceOn(id, day)
    local hist = ns.db.items[id]
    if not hist then return nil end
    for i = #hist, 1, -1 do
        local d = hist[i][1]
        if d == day then return hist[i][2] end
        if d < day then return nil end
    end
end

-- today's price: the newest day with data
function ns.Now(id)
    local hist = ns.db.items[id]
    local e = hist and hist[#hist]
    if not e then return nil end
    return e[2], e[3], e[4], ns.Today() - e[1]
end

--[[ the signal of an item, in plain words:
  "buy"   the cheapest price today is at least buyPct % under the forecast (it should come back up)
  "wait"  for selling: the forecast in 7 days is at least sellPct % higher than today
  "sell"  for selling: the forecast in 3 days is at least sellPct % lower than today ]]
function ns.Signal(id)
    local f = ns.Forecast(id)
    local now, low, qty = ns.Now(id)
    if not (f and now) then return nil end
    local s = ns.db.settings
    local f3, f7 = f[3].price, f[7].price
    local out = {}
    if low and low <= f3 * (1 - s.buyPct / 100) then out.buy = (f3 - low) / f3 end
    if f7 >= now * (1 + s.sellPct / 100) then out.wait = (f7 - now) / now end
    if f3 <= now * (1 - s.sellPct / 100) then out.sell = (now - f3) / now end
    return out, f, now, low, qty
end

---------------------------------------------------------------------------
-- accuracy: today's forecasts are written down; when the day they were for has passed, they are checked against
-- the real price and against the simplest guess ("the price stays as it is")
---------------------------------------------------------------------------
local LOG_PER_DAY = 400
local function LogForecasts()
    local today = ns.Today()
    if ns.db.loggedDay == today then return end
    ns.db.loggedDay = today
    -- the most traded items (most units on sale) + the watch list
    local ids = {}
    for id, hist in pairs(ns.db.items) do
        local e = hist[#hist]
        if e and e[1] >= today - 1 then ids[#ids + 1] = { id, e[4] or 0 } end
    end
    table.sort(ids, function(a, b) return a[2] > b[2] end)
    local pick = {}
    for i = 1, math.min(LOG_PER_DAY, #ids) do pick[ids[i][1]] = true end
    for id in pairs(ns.db.watch) do pick[id] = true end
    for id in pairs(pick) do
        local f = ns.Forecast(id)
        local now = ns.Now(id)
        if f and now then
            for _, h in ipairs(ns.HORIZONS) do
                local key = today + h
                ns.db.preds[key] = ns.db.preds[key] or {}
                -- never 0: a 0 copper forecast would make log(actual / 0) infinite in the self-check
                ns.db.preds[key][id .. ":" .. h] = { math.max(1, math.floor(f[h].price)), math.max(0, math.floor(f[h].low)), math.max(1, math.floor(f[h].high)), math.max(1, math.floor(now)) }
            end
        end
    end
end

local function CheckForecasts()
    local today = ns.Today()
    for day, list in pairs(ns.db.preds) do
        if day < today then -- that day is over: its prices are final
            for key, p in pairs(list) do
                local id, h = key:match("^(%d+):(%d+)$")
                id, h = tonumber(id), tonumber(h)
                local actual
                for _, e in ipairs(ns.db.items[id] or {}) do if e[1] == day then actual = e[2] end end
                -- p[1] / p[4] are 0 in forecasts saved by 1.0.0 for items below 1 copper: skip those, the log would be infinite
                if actual and actual > 0 and h and (p[1] or 0) > 0 and (p[4] or 0) > 0 then
                    local a = ns.db.acc[h] or { n = 0, hit = 0, err = 0, naive = 0 }
                    a.n = a.n + 1
                    if actual >= p[2] and actual <= p[3] then a.hit = a.hit + 1 end
                    a.err = a.err + math.abs(math.log(actual / p[1]))
                    a.naive = a.naive + math.abs(math.log(actual / p[4]))
                    ns.db.acc[h] = a
                end
            end
            if day < today - 3 then ns.db.preds[day] = nil end -- data for it may still arrive for a few days
        end
    end
end

---------------------------------------------------------------------------
-- taking the scans over (in small steps, the game never stalls)
---------------------------------------------------------------------------
local running
function ns.ImportRunning() return running ~= nil end

function ns.Import(quiet)
    if running then return end
    local steps = {}
    if ns.Sources.HasAuctionator() then steps[#steps + 1] = { "Auctionator", ns.Sources.AuctionatorImporter } end
    if ns.Sources.HasAuctioneer() then steps[#steps + 1] = { "Auctioneer", ns.Sources.AuctioneerImporter } end
    if ns.Sources.HasTSM() then steps[#steps + 1] = { "TSM", ns.Sources.TSMImporter } end
    if #steps == 0 then
        if not quiet then Print("Kein Scan-Addon gefunden. Installiere Auctionator, Auctioneer oder TSM und scanne damit das Auktionshaus.") end
        return
    end
    running = { step = 1, steps = steps, done = {} }
    local function tick()
        local st = steps[running.step]
        running.fn = running.fn or st[2]()
        local finished, n = running.fn(300)
        if finished then
            running.done[#running.done + 1] = ("%s %d"):format(st[1], n or 0)
            running.fn = nil
            running.step = running.step + 1
        end
        if running.step > #steps then
            local done = running.done
            running = nil
            for _, hist in pairs(ns.db.items) do ns.Prune(hist) end
            -- weekday effect from the 2000 most traded items (enough for a market-wide effect, cheap to compute)
            local top = {}
            for id, hist in pairs(ns.db.items) do
                if #hist >= 7 then top[#top + 1] = { hist, hist[#hist][4] or 0 } end
            end
            table.sort(top, function(a, b) return a[2] > b[2] end)
            local hists = {}
            for i = 1, math.min(2000, #top) do hists[i] = top[i][1] end
            ns.db.weekday = Model.WeekdayEffects(hists)
            ns.Invalidate()
            CheckForecasts()
            LogForecasts()
            ns.db.lastImport = time()
            if not quiet then Print("Preise übernommen: " .. table.concat(done, ", ") .. " Items.") end
            ns.CheckWatch()
            if ns.OnImported then ns.OnImported() end
            if ns.RefreshUI then ns.RefreshUI() end
            return
        end
        C_Timer.After(0, tick)
    end
    tick()
end

-- watch list: chat line for watched items that are a buy chance now
function ns.CheckWatch()
    if not ns.db.settings.alerts then return end
    for id in pairs(ns.db.watch) do
        local sig, f, _, low = ns.Signal(id)
        if sig and sig.buy then
            Print(("Merkliste: %s ist günstig - %s statt erwartet %s (%d%% darunter)."):format(ns.ItemName(id), ns.Money(low), ns.Money(f[3].price), math.floor(sig.buy * 100 + 0.5)))
        end
    end
end

---------------------------------------------------------------------------
-- events, slash
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")
f:RegisterEvent("ITEM_DATA_LOAD_RESULT")
f:SetScript("OnEvent", function(_, event, arg)
    if event == "ITEM_DATA_LOAD_RESULT" then ns.OnItemLoaded(arg); return end
    if event == "ADDON_LOADED" and arg == ADDON then
        AHPrognoseDB = AHPrognoseDB or {}
        local db = AHPrognoseDB
        db.items = db.items or {}
        db.names = db.names or {}
        db.watch = db.watch or {}
        db.preds = db.preds or {}
        db.acc = db.acc or {}
        -- WoW cannot save an infinite number and drops the field: an entry missing one of its sums (1.0.0 bug, a 0
        -- copper forecast) is unusable, start that horizon's self-check again
        for h, a in pairs(db.acc) do
            local ok = type(a) == "table"
            for _, k in ipairs({ "n", "hit", "err", "naive" }) do
                local v = ok and a[k]
                if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then ok = false end
            end
            if not ok then db.acc[h] = nil end
        end
        db.settings = db.settings or {}
        for k, v in pairs(ns.DEFAULTS) do if db.settings[k] == nil then db.settings[k] = v end end
        ns.db = db
    elseif event == "PLAYER_LOGIN" then
        -- Auctionator decodes its database at login: take it over a few seconds later
        C_Timer.After(8, function() if ns.db.settings.autoImport then ns.Import(true) end end)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        -- you scanned (or at least looked): Auctionator / Auctioneer finish writing first
        C_Timer.After(3, function() if ns.db.settings.autoImport then ns.Import() end end)
    end
end)

SLASH_AHPROGNOSE1, SLASH_AHPROGNOSE2 = "/ahp", "/ahprognose"
SlashCmdList.AHPROGNOSE = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "import" or msg == "übernehmen" then ns.Import()
    elseif msg == "reset" then
        StaticPopup_Show("AHPROGNOSE_RESET")
    else ns.ToggleUI() end
end

StaticPopupDialogs.AHPROGNOSE_RESET = {
    text = "AHPrognose: alle gespeicherten Preise, Prognose-Prüfungen und die Merkliste löschen?",
    button1 = YES, button2 = NO,
    OnAccept = function()
        local s = ns.db.settings
        wipe(AHPrognoseDB)
        AHPrognoseDB.items, AHPrognoseDB.names, AHPrognoseDB.watch, AHPrognoseDB.preds, AHPrognoseDB.acc = {}, {}, {}, {}, {}
        AHPrognoseDB.settings = s
        ns.db = AHPrognoseDB
        ns.Invalidate()
        if ns.OnImported then ns.OnImported() end
        if ns.RefreshUI then ns.RefreshUI() end
        Print("Alle Daten gelöscht. Beim nächsten Schließen des Auktionshauses wird neu übernommen.")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
