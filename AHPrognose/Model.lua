-- AHPrognose: the forecast. Pure Lua (no game API), so it can be tested outside the game.
--
-- Input per item: its daily history from YOUR OWN auction house scans (made with Auctionator, Auctioneer or TSM),
-- { {day, price, low, qty}, ... } oldest first. "price" is the day's cheapest listing (what you pay / what you
-- compete with when selling).
-- Prices are worked on in log space (a 10 % rise counts the same for copper and for gold).
--
--   level   L  = exponentially weighted average of the daily medians (the recent normal price)
--   trend   b  = Theil-Sen slope of the last days (median of all pair slopes: one odd day can't tilt it), damped
--   anchor  M  = median of the last 14 days (where prices tend to return to)
--   weekday w  = market-wide weekday effect, only once two weeks of scans exist
--   forecast for h days:  F(h) = M + (L - M) * r^h + b * (phi + phi^2 + ... + phi^h) + w(day of target)
--   range: the item's own one-day-ahead errors over its history (walk-forward), robust spread (MAD), x sqrt(h),
--          80 % range = F +- 1.28 * sigma * sqrt(h)
--   confidence: from days of data, how wide the range is, and how many auctions there are
--
-- Nothing here is tuned to a website: the parameters are the same for every item and the addon measures, in its
-- "Genauigkeit" tab, how often the real price ended inside the range and whether it beat "price stays the same".
local _, ns = ...
ns = ns or {}
local Model = {}
ns.Model = Model

Model.MAX_SLOPE = 0.15    -- trend cap: +-15 % per day
Model.MIN_DAYS = 4        -- fewer days of scans: no forecast yet
Model.CHOOSE_AFTER = 4    -- one-day checks an item needs before its own best variant is chosen
Model.DEFAULT_SIGMA = 0.35  -- daily spread before an item has its own; 80 % range hit 80 % on real Forever scans
Model.Z80 = 1.2816

local log, exp, sqrt, abs, floor, min, max = math.log, math.exp, math.sqrt, math.abs, math.floor, math.min, math.max

local function median(t)
    local n = #t
    if n == 0 then return nil end
    local s = {}
    for i = 1, n do s[i] = t[i] end
    table.sort(s)
    if n % 2 == 1 then return s[(n + 1) / 2] end
    return (s[n / 2] + s[n / 2 + 1]) / 2
end
Model.Median = median

-- weighted median: values with weights (e.g. unit prices and how many units each auction holds)
function Model.WeightedMedian(values, weights)
    local n = #values
    if n == 0 then return nil end
    local idx = {}
    for i = 1, n do idx[i] = i end
    table.sort(idx, function(a, b) return values[a] < values[b] end)
    local total = 0
    for i = 1, n do total = total + (weights[i] or 1) end
    local half, acc = total / 2, 0
    for _, i in ipairs(idx) do
        acc = acc + (weights[i] or 1)
        if acc >= half then return values[i] end
    end
    return values[idx[n]]
end

-- Theil-Sen slope over (day, value) points
local function slope(days, xs)
    local s = {}
    for i = 1, #xs - 1 do
        for j = i + 1, #xs do
            local dd = days[j] - days[i]
            if dd > 0 then s[#s + 1] = (xs[j] - xs[i]) / dd end
        end
    end
    return median(s) or 0
end

-- three ways to read a price history; per item, the one that predicted ITS OWN past best is used
--   "zurück" : prices swing around a normal price and come back (slow level, strong pull to the 2-week median)
--   "springt": like "zurück", but every scan counts fully and the pull back is strong (no trend)
--   "mittel" : in between (the default while there is too little history to choose)
--   "folgt"  : prices wander and stay where they went (newest price, gently damped trend, no pull back)
Model.VARIANTS = {
    { name = "zurück", alpha = 0.35, revert = 0.80, phi = 0.80 },
    { name = "springt", alpha = 1.00, revert = 0.60, phi = 0.00 },
    { name = "mittel", alpha = 0.70, revert = 0.93, phi = 0.80 },
    { name = "folgt",  alpha = 1.00, revert = 1.00, phi = 0.70 },
}
Model.DEFAULT_VARIANT = 3

-- the forecast core on log prices, using only points up to index `upto`
local function core(days, xs, upto, P)
    local L = xs[1]
    for i = 2, upto do L = P.alpha * xs[i] + (1 - P.alpha) * L end
    local first = upto
    while first > 1 and days[upto] - days[first - 1] < 14 do first = first - 1 end
    local window = {}
    for i = first, upto do window[#window + 1] = xs[i] end
    local M = median(window)
    local sfirst = max(1, upto - 9)
    local sd, sx = {}, {}
    for i = sfirst, upto do sd[#sd + 1] = days[i]; sx[#sx + 1] = xs[i] end
    local b = #sx >= 3 and slope(sd, sx) or 0
    b = max(-Model.MAX_SLOPE, min(Model.MAX_SLOPE, b))
    return L, M, b
end

local function project(L, M, b, h, w, P)
    local damp, p = 0, 1
    for _ = 1, h do p = p * P.phi; damp = damp + p end
    return M + (L - M) * P.revert ^ h + b * damp + (w or 0)
end

-- day numbers are Auctionator's: days since 2020-01-01 local time (a Wednesday). Weekday: 1 = Monday ... 7 = Sunday
function Model.Weekday(day) return (day + 2) % 7 + 1 end

--[[ Forecast one item.
  hist: { {day, median, min, qty}, ... } oldest first (one entry per day with scans)
  today: the current day number; horizons: list of days ahead, e.g. {1, 3, 7}
  weekday: optional table [1..7] = log effect (from Model.WeekdayEffects), or nil
  returns nil, reason   or   { days = n, sigma, conf = 1..3, [h] = { price, low, high } , level, anchor, trend }
]]
function Model.Forecast(hist, today, horizons, weekday)
    local n = #hist
    if n < Model.MIN_DAYS then return nil, ("noch %d Tage scannen"):format(Model.MIN_DAYS - n) end
    local days, xs = {}, {}
    for i = 1, n do
        local med = hist[i][2]
        if not med or med <= 0 then return nil, "Daten fehlen" end
        days[i], xs[i] = hist[i][1], log(med)
    end
    -- each variant's one-day-ahead errors over the item's own past (walk-forward: only data before that day)
    local best, bestErr, bestErrs
    for v, P in ipairs(Model.VARIANTS) do
        local errs, sum = {}, 0
        for k = Model.MIN_DAYS - 1, n - 1 do
            local L, M, b = core(days, xs, k, P)
            local h = days[k + 1] - days[k]
            if h >= 1 and h <= 3 then
                local w = weekday and (weekday[Model.Weekday(days[k + 1])] or 0) or 0
                local e = (xs[k + 1] - project(L, M, b, h, w, P)) / sqrt(h)
                errs[#errs + 1] = e
                sum = sum + abs(e)
            end
        end
        local mean = #errs > 0 and sum / #errs or 0
        -- too few checks to choose: the middle variant
        if #errs < Model.CHOOSE_AFTER then mean = (v == Model.DEFAULT_VARIANT) and -1 or math.huge end
        if not bestErr or mean < bestErr then best, bestErr, bestErrs = v, mean, errs end
    end
    local P = Model.VARIANTS[best]
    local errs = bestErrs
    local sigma = Model.DEFAULT_SIGMA
    if #errs >= 3 then
        local med = median(errs)
        local dev = {}
        for i = 1, #errs do dev[i] = abs(errs[i] - med) end
        sigma = max(0.03, 1.4826 * median(dev))
        if #errs < 6 then sigma = (sigma * #errs + Model.DEFAULT_SIGMA * (6 - #errs)) / 6 end -- few errors: lean on a default
    end
    local L, M, b = core(days, xs, n, P)
    local res = { days = n, sigma = sigma, level = exp(L), anchor = exp(M), trend = b, variant = P.name }
    local gap = max(0, today - days[n]) -- days since the last day with data
    for _, h in ipairs(horizons) do
        local hh = h + gap
        local w = weekday and (weekday[Model.Weekday(today + h)] or 0) or 0
        local f = project(L, M, b, hh, w, P)
        local half = Model.Z80 * sigma * sqrt(hh)
        res[h] = { price = exp(f), low = exp(f - half), high = exp(f + half) }
    end
    -- confidence: 3 high, 2 medium, 1 low
    local width = Model.Z80 * sigma * sqrt(3) -- half range at 3 days, in log
    local conf = 1
    if n >= 7 and width < 0.25 then conf = 3 elseif n >= 5 and width < 0.45 then conf = 2 end
    local qty = hist[n][4] or 0
    if qty < 3 and conf > 1 then conf = conf - 1 end
    res.conf = conf
    return res
end

--[[ Market signals on top of the price history (checked on the user's real scans, 11 days, 2026-11-23:
  walk-forward on later days, 1-day forecast: mean error -0.4..-0.9 %, median error -3.3..-3.8 %, and on 60-62 %
  of the shifted items the price really ended below the old forecast; wow-addon-tools/ahp/craft_backtest.lua)
  * "Herstellkosten": for something crafted (potions, food, gear parts ...) today's material cost is known from
    the same scans (plus vendor prices). If it sells far above what it costs to make, crafters undercut it:
      price > 54 % over cost (log 0.43) -> next day -13 %;  12-54 % over (log 0.11) -> -3.5 %
  * "Angebot": many more auctions than the scan day before (farmers / crafters dumping):
      quantity +57 % or more (log 0.45) -> next day -8 %
  Only the next-day forecast is moved (only that was checked); the material signal (products getting dearer ->
  materials follow) was checked too and showed no effect, so it is not used.
  hist: the item's history; recipes: list of {made, mat, n, mat, n ...}; vendor: [mat] = copper;
  priceOn(mat, day) -> that day's cheapest price of a material or nil
  returns shift (log), info = { kind = "cost"|"supply", cost = copper, ratio = price/cost, qtyNow, qtyBefore } or nil ]]
Model.COST_HIGH, Model.COST_HIGH_SHIFT = 0.43, -0.13
Model.COST_MID, Model.COST_MID_SHIFT = 0.11, -0.035
Model.SUPPLY_UP, Model.SUPPLY_SHIFT = 0.45, -0.08

-- cheapest way to make one of an item today (copper), or nil when a material has no price
function Model.CraftCost(recipes, vendor, priceOn, day)
    local best
    for _, r in ipairs(recipes) do
        local sum = 0
        for i = 2, #r - 1, 2 do
            local m, n = r[i], r[i + 1]
            local p, v = priceOn(m, day), vendor and vendor[m]
            if v and (not p or v < p) then p = v end
            if not p or p <= 0 then sum = nil; break end
            sum = sum + p * n
        end
        if sum then
            sum = sum / r[1]
            if not best or sum < best then best = sum end
        end
    end
    return best
end

function Model.MarketShift(hist, recipes, vendor, priceOn)
    local n = #hist
    local last = hist[n]
    if not last or not last[2] or last[2] <= 0 then return 0 end
    if recipes then
        local cost = Model.CraftCost(recipes, vendor, priceOn, last[1])
        if cost and cost > 0 then
            local m = log(last[2] / cost)
            local info = { kind = "cost", cost = cost, ratio = last[2] / cost }
            if m > Model.COST_HIGH then return Model.COST_HIGH_SHIFT, info end
            if m > Model.COST_MID then return Model.COST_MID_SHIFT, info end
            return 0, info
        end
    end
    local prev = hist[n - 1]
    if prev and last[1] - prev[1] == 1 and (prev[4] or 0) > 0 and (last[4] or 0) > 0 then
        if log(last[4] / prev[4]) > Model.SUPPLY_UP then
            return Model.SUPPLY_SHIFT, { kind = "supply", qtyNow = last[4], qtyBefore = prev[4] }
        end
    end
    return 0
end

-- moves the next-day forecast (price and its range) by a market signal's shift
function Model.ApplyShift(f, shift, info)
    if not f then return f end
    f.market = info
    if shift and shift ~= 0 and f[1] then
        local k = exp(shift)
        f[1] = { price = f[1].price * k, low = f[1].low * k, high = f[1].high * k }
        f.shift = shift
    end
    return f
end

--[[ Market-wide weekday effect (log), from every item's deviation from its own 7-day median.
  items: map id -> hist. Needs >= 14 distinct days in total; returns nil before. Effects under 2 % are dropped. ]]
function Model.WeekdayEffects(items)
    local allDays, byWd = {}, {}
    for _, hist in pairs(items) do
        local n = #hist
        if n >= 7 then
            for i = 1, n do
                allDays[hist[i][1]] = true
                local window = {}
                -- days are sorted and unique: the +-3-day window lies within 3 positions
                for j = max(1, i - 3), min(n, i + 3) do
                    if abs(hist[j][1] - hist[i][1]) <= 3 and hist[j][2] > 0 then window[#window + 1] = log(hist[j][2]) end
                end
                if #window >= 5 and hist[i][2] > 0 then
                    local wd = Model.Weekday(hist[i][1])
                    byWd[wd] = byWd[wd] or {}
                    local t = byWd[wd]
                    t[#t + 1] = log(hist[i][2]) - median(window)
                end
            end
        end
    end
    local count = 0
    for _ in pairs(allDays) do count = count + 1 end
    if count < 14 then return nil end
    local eff = {}
    for wd = 1, 7 do
        local e = byWd[wd] and #byWd[wd] >= 20 and median(byWd[wd]) or 0
        eff[wd] = abs(e) >= 0.02 and e or 0
    end
    return eff
end

return Model
