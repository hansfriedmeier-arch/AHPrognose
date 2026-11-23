-- AHPrognose window (/ahp): tabs, each with a short explanation at the top; item details with a chart; tooltip lines.
local _, ns = ...

local W, H = 800, 600
local ROWS, ROW_H = 17, 20
local GOLD, MUTED, WHITE = { 1, 0.82, 0 }, { 0.65, 0.68, 0.75 }, { 1, 1, 1 }

local function Text(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size or 12, "")
    local c = color or WHITE
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(true)
    return fs
end

local function Pct(x) return ("%+d%%"):format(math.floor(x * 100 + (x >= 0 and 0.5 or -0.5))) end
local function PctColor(x)
    if x >= 0.03 then return "|cff40ff40" .. Pct(x) .. "|r" end
    if x <= -0.03 then return "|cffff6060" .. Pct(x) .. "|r" end
    return "|cffc0c0c0" .. Pct(x) .. "|r"
end
local function Conf(c) return ns.CONF_COLOR[c] .. ns.CONF_TEXT[c] .. "|r" end

local TABS = {
    { "home", "Übersicht",
      "So geht's: 1. Auktionshaus öffnen.  2. Mit Auctionator (oder Auctioneer / TSM) einen vollen Scan machen.  3. Auktionshaus schließen - AHPrognose übernimmt die Preise von selbst. Am besten jeden Tag einmal scannen: ab 4 Tagen gibt es Prognosen, ab 7 Tagen werden sie verlässlicher, ab 14 Tagen kennt AHPrognose auch die Wochentage." },
    { "list", "Prognosen",
      "Alle Items mit Prognose. \"Jetzt\" = günstigster Preis beim letzten Scan. \"Prognose\" = erwarteter günstigster Preis in so vielen Tagen, wie in den Einstellungen gewählt. Linksklick = Details mit Verlauf, Rechtsklick = Merkliste an/aus. Suchfeld: Teil des Namens." },
    { "buy", "Kaufchancen",
      "Items, die gerade deutlich billiger sind, als AHPrognose für die nächsten 3 Tage erwartet. Gut, wenn du das Item brauchst oder es später teurer verkaufen willst. Keine Garantie: es ist eine Schätzung aus deinen bisherigen Scans." },
    { "sell", "Verkaufstipps",
      "Items aus deinen Taschen (nicht gebunden). \"Jetzt verkaufen\": der Preis fällt voraussichtlich. \"Warten\": der Preis steigt voraussichtlich in der nächsten Woche. \"Egal\": keine deutliche Bewegung erwartet." },
    { "watch", "Merkliste",
      "Items, die du beobachtest (Rechtsklick in einer Liste). Nach jedem Übernehmen der Preise meldet AHPrognose im Chat, wenn eins davon gerade eine Kaufchance ist." },
    { "acc", "Genauigkeit",
      "AHPrognose prüft sich selbst: jeden Tag werden die Prognosen notiert und später mit dem echten Preis verglichen. \"Im Bereich\" sollte bei etwa 80 % liegen. Die Prognose ist nur dann nützlich, wenn sie näher liegt als die einfachste Annahme \"der Preis bleibt gleich\"." },
    { "opt", "Einstellungen",
      "Fahre mit der Maus über eine Einstellung oder lies den grauen Text darunter. Änderungen gelten sofort." },
}

local frame, detail
local view, offset, rows, search = "home", 0, {}, ""

---------------------------------------------------------------------------
-- list of all items with a forecast (built in small steps after each import)
---------------------------------------------------------------------------
local scan = { rows = {}, built = false, running = false }
local function BuildScan(done)
    if scan.running then return end
    scan.running = true
    local today = ns.Today()
    local minQty = ns.db.settings.minQty
    local ids = {}
    for id, hist in pairs(ns.db.items) do
        local e = hist[#hist]
        if e and e[1] >= today - 2 and #hist >= ns.Model.MIN_DAYS and (e[4] or 0) >= minQty then ids[#ids + 1] = id end
    end
    local out, i = {}, 0
    local function step()
        local stop = math.min(#ids, i + 150)
        while i < stop do
            i = i + 1
            local sig, f, now, low, qty = ns.Signal(ids[i])
            if f then out[#out + 1] = { id = ids[i], sig = sig, f = f, now = now, low = low, qty = qty } end
        end
        if i < #ids then C_Timer.After(0, step) return end
        scan.rows, scan.built, scan.running = out, true, false
        if done then done() end
    end
    step()
end
function ns.RebuildScan()
    scan.built = false
    if frame and frame:IsShown() then BuildScan(ns.RefreshUI) end
end

---------------------------------------------------------------------------
-- detail window: chart + plain words
---------------------------------------------------------------------------
local ShowDetail
-- redraw the open detail window (item data arrived)
function ns.RefreshDetail() if detail and detail:IsShown() and detail.id then ShowDetail(detail.id) end end

function ShowDetail(id)
    if not detail then
        detail = CreateFrame("Frame", "AHPrognoseDetail", frame, "BackdropTemplate")
        detail:SetSize(360, 480) -- room for 10-12 lines of explanation under the chart
        detail:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
        detail:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        detail:SetBackdropColor(0.06, 0.07, 0.09, 0.95)
        detail:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
        detail:EnableMouse(true)
        local close = CreateFrame("Button", nil, detail, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        detail.icon = detail:CreateTexture(nil, "ARTWORK")
        detail.icon:SetSize(24, 24)
        detail.icon:SetPoint("TOPLEFT", 12, -10)
        detail.title = Text(detail, 13, GOLD)
        detail.title:SetPoint("LEFT", detail.icon, "RIGHT", 6, 0)
        detail.title:SetPoint("RIGHT", -30, 0)
        detail.chart = CreateFrame("Frame", nil, detail, "BackdropTemplate")
        detail.chart:SetPoint("TOPLEFT", 12, -42)
        detail.chart:SetSize(336, 130)
        detail.chart:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        detail.chart:SetBackdropColor(0, 0, 0, 0.35)
        detail.legend = Text(detail, 10, MUTED)
        detail.legend:SetPoint("TOPLEFT", detail.chart, "BOTTOMLEFT", 0, -3)
        detail.legend:SetWidth(336)
        detail.legend:SetText("|cffd0d0d0Punkte|r: deine Scans (letzte 30 Tage)   |cff4fc3f7Blau|r: Prognose, Balken = Bereich (8 von 10 Mal)")
        detail.text = Text(detail, 12)
        detail.text:SetPoint("TOPLEFT", detail.legend, "BOTTOMLEFT", 0, -8)
        detail.text:SetWidth(336)
        detail.watch = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
        detail.watch:SetSize(160, 22)
        detail.watch:SetPoint("BOTTOMLEFT", 12, 10)
        detail.watch:SetScript("OnClick", function()
            local wid = detail.id
            ns.db.watch[wid] = (not ns.db.watch[wid]) or nil
            ShowDetail(wid)
            ns.RefreshUI()
        end)
        detail.pool = {}
    end
    detail.id = id
    detail.icon:SetTexture(ns.ItemIcon(id))
    detail.title:SetText(ns.ItemName(id))
    detail.watch:SetText(ns.db.watch[id] and "Von Merkliste nehmen" or "Auf die Merkliste")
    for _, t in ipairs(detail.pool) do t:Hide() end
    local used = 0
    local function Dot(x, y, size, r, g, b)
        used = used + 1
        local t = detail.pool[used]
        if not t then t = detail.chart:CreateTexture(nil, "OVERLAY"); detail.pool[used] = t end
        t:SetColorTexture(r, g, b, 1)
        t:SetSize(size, size)
        t:ClearAllPoints()
        t:SetPoint("CENTER", detail.chart, "BOTTOMLEFT", x, y)
        t:Show()
    end
    local function Bar(x, y1, y2, r, g, b)
        used = used + 1
        local t = detail.pool[used]
        if not t then t = detail.chart:CreateTexture(nil, "OVERLAY"); detail.pool[used] = t end
        t:SetColorTexture(r, g, b, 0.45)
        t:SetSize(5, math.max(2, y2 - y1))
        t:ClearAllPoints()
        t:SetPoint("BOTTOM", detail.chart, "BOTTOMLEFT", x, y1)
        t:Show()
    end

    local hist = ns.db.items[id] or {}
    local f, why = ns.Forecast(id)
    local today = ns.Today()
    -- chart from the first scan (at most 30 days back) to 7 days ahead, so a short history isn't squeezed to the edge
    local first = today - 30
    for _, e in ipairs(hist) do if e[1] >= first then first = e[1] - 1; break end end
    -- price range of the chart (log scale)
    local lo, hi = math.huge, 0
    for _, e in ipairs(hist) do if e[1] >= first then lo = math.min(lo, e[2]); hi = math.max(hi, e[2]) end end
    if f then for _, h in ipairs(ns.HORIZONS) do lo = math.min(lo, f[h].low); hi = math.max(hi, f[h].high) end end
    if hi > 0 and lo < math.huge then
        if hi <= lo then hi = lo * 1.1 end
        local llo, lhi = math.log(lo), math.log(hi)
        local cw, ch = 336, 130
        local span = today + 7 - first
        local function X(day) return 8 + (day - first) / span * (cw - 16) end
        local function Y(p) return 8 + (math.log(p) - llo) / (lhi - llo) * (ch - 16) end
        -- a faint line at today
        Bar(X(today), 0, ch, 0.4, 0.4, 0.45)
        for _, e in ipairs(hist) do if e[1] >= first then Dot(X(e[1]), Y(e[2]), 5, 0.85, 0.85, 0.85) end end
        if f then
            for _, h in ipairs(ns.HORIZONS) do
                Bar(X(today + h), Y(f[h].low), Y(f[h].high), 0.31, 0.76, 0.97)
                Dot(X(today + h), Y(f[h].price), 6, 0.31, 0.76, 0.97)
            end
        end
    end

    -- the explanation in words
    local lines = {}
    local now, low, qty, age = ns.Now(id)
    if now then
        lines[#lines + 1] = ("Letzter Scan%s: günstigster Preis |cffffffff%s|r, %d Stück im Angebot."):format(
            age and age > 0 and (" (vor %d Tag%s)"):format(age, age == 1 and "" or "en") or " (heute)", ns.Money(low), qty or 0)
    end
    if f then
        for _, h in ipairs(ns.HORIZONS) do
            lines[#lines + 1] = ("In %d Tag%s: etwa |cff4fc3f7%s|r (meist zwischen %s und %s) %s"):format(h, h == 1 and "" or "en",
                ns.Money(f[h].price), ns.Money(f[h].low), ns.Money(f[h].high), now and PctColor(f[h].price / now - 1) or "")
        end
        local trend = f.trend
        local tw = trend > 0.01 and "steigt gerade" or trend < -0.01 and "fällt gerade" or "ist gerade ruhig"
        lines[#lines + 1] = ("Der Preis %s; der übliche Preis der letzten 2 Wochen ist %s."):format(tw, ns.Money(f.anchor))
        local VAR = { ["zurück"] = "schwankt um einen festen Preis und kehrt zurück", springt = "Ausreißer kommen schnell zum üblichen Preis zurück",
            mittel = "gemischt (noch zu wenig Verlauf, um es genauer zu sagen)", folgt = "bleibt dort, wohin er sich bewegt" }
        lines[#lines + 1] = "Verhalten dieses Items: " .. (VAR[f.variant] or f.variant) .. "."
        local mk = f.market
        if mk and mk.kind == "cost" then
            local over = mk.ratio - 1
            local txt = ("Herstellen kostet heute etwa %s an Material; der Preis liegt %s%d%%|r %s."):format(ns.Money(mk.cost),
                over >= 0 and "|cffffd100" or "|cff40ff40", math.floor(math.abs(over) * 100 + 0.5), over >= 0 and "darüber" or "darunter")
            if f.shift then txt = txt .. " Liegt der Preis so weit darüber, unterbieten Hersteller oft: Prognose für morgen gesenkt."
            elseif over < 0 then txt = txt .. " Kaufen ist gerade günstiger als selbst herstellen." end
            lines[#lines + 1] = txt
        elseif mk and mk.kind == "supply" and f.shift then
            lines[#lines + 1] = ("Viel mehr Angebot als beim Scan davor (%d statt %d Stück): danach fällt der Preis oft, Prognose für morgen gesenkt."):format(mk.qtyNow, mk.qtyBefore)
        end
        lines[#lines + 1] = ("Vertrauen: %s (aus %d Tagen Scans)."):format(Conf(f.conf), f.days)
        local sig = ns.Signal(id)
        if sig and sig.buy then lines[#lines + 1] = ("|cff40ff40Kaufchance:|r %d%% unter dem erwarteten Preis."):format(math.floor(sig.buy * 100 + 0.5)) end
        if sig and sig.sell then lines[#lines + 1] = "|cffff9060Wer verkaufen will: lieber jetzt, der Preis fällt voraussichtlich.|r" end
        if sig and sig.wait then lines[#lines + 1] = "|cffffd100Wer verkaufen will: lieber warten, der Preis steigt voraussichtlich.|r" end
    else
        lines[#lines + 1] = "Noch keine Prognose: " .. (why or "zu wenige Scans") .. "."
    end
    detail.text:SetText(table.concat(lines, "\n"))
    detail:Show()
end

---------------------------------------------------------------------------
-- rows
---------------------------------------------------------------------------
local COLS = { { "Item", 250 }, { "Jetzt", 105 }, { "Prognose", 105 }, { "Änderung", 70 }, { "Vertrauen", 70 }, { "", 150 } }

local function MakeRow(parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(W - 28, ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    if i % 2 == 0 then
        local bg = r:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.03)
    end
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", 2, 0)
    r.cells = {}
    local x = 22
    for c, col in ipairs(COLS) do
        local fs = Text(r, 11)
        fs:SetWordWrap(false)
        fs:SetPoint("LEFT", c == 1 and 22 or x, 0)
        fs:SetWidth(c == 1 and col[2] - 22 or col[2] - 6)
        r.cells[c] = fs
        x = x + (c == 1 and col[2] - 22 or col[2])
    end
    r:SetScript("OnClick", function(self, button)
        if not self.id then return end
        if button == "RightButton" then
            ns.db.watch[self.id] = (not ns.db.watch[self.id]) or nil
            ns.Print(ns.ItemName(self.id) .. (ns.db.watch[self.id] and " ist jetzt auf der Merkliste." or " ist nicht mehr auf der Merkliste."))
            ns.RefreshUI()
        else
            ShowDetail(self.id)
        end
    end)
    r:SetScript("OnEnter", function(self)
        if not self.id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.id)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    return r
end

local function FillRow(r, d, extra)
    local s = ns.db.settings
    local h = s.horizon
    r.id = d.id
    r.icon:SetTexture(ns.ItemIcon(d.id))
    r.icon:Show()
    r.cells[1]:SetText((ns.db.watch[d.id] and "|cffffd100*|r " or "") .. ns.ItemName(d.id))
    r.cells[2]:SetText(ns.Money(d.low or d.now))
    r.cells[3]:SetText(d.f and ns.Money(d.f[h].price) or "-")
    r.cells[4]:SetText(d.f and d.now and PctColor(d.f[h].price / d.now - 1) or "")
    r.cells[5]:SetText(d.f and Conf(d.f.conf) or "")
    r.cells[6]:SetText(extra or "")
    r:Show()
end

---------------------------------------------------------------------------
-- what each tab lists
---------------------------------------------------------------------------
local function Filtered()
    local s = ns.db.settings
    local out = {}
    if view == "list" then
        local q = search:lower()
        for _, d in ipairs(scan.rows) do
            if d.f.conf >= s.minConf and (q == "" or ns.ItemName(d.id):lower():find(q, 1, true)) then out[#out + 1] = { d } end
        end
        -- most money on sale first (units x price): the items that matter, not 1-copper arrows
        table.sort(out, function(a, b) return (a[1].qty or 0) * (a[1].now or 0) > (b[1].qty or 0) * (b[1].now or 0) end)
    elseif view == "buy" then
        for _, d in ipairs(scan.rows) do
            if d.f.conf >= s.minConf and d.sig and d.sig.buy then
                out[#out + 1] = { d, ("|cff40ff40%d%% unter Erwartung|r"):format(math.floor(d.sig.buy * 100 + 0.5)) }
            end
        end
        -- biggest saving in gold first (a 50 % "chance" on a 1-silver item is worth nothing)
        table.sort(out, function(a, b) return a[1].f[3].price - a[1].low > b[1].f[3].price - b[1].low end)
    elseif view == "sell" then
        for _, id in ipairs(ns.BagItems()) do
            local sig, f, now, low, qty = ns.Signal(id)
            local d = { id = id, sig = sig, f = f, now = now, low = low, qty = qty }
            local txt
            if not f then txt = "|cff808080keine Prognose|r"
            elseif sig.sell then txt = "|cffff9060Jetzt verkaufen|r"
            elseif sig.wait then txt = "|cffffd100Warten|r"
            else txt = "|cffc0c0c0Egal|r" end
            if now then out[#out + 1] = { d, txt, f and (sig.sell and 3 or sig.wait and 2 or 1) or 0 } end
        end
        table.sort(out, function(a, b) return a[3] > b[3] end)
    elseif view == "watch" then
        for id in pairs(ns.db.watch) do
            local sig, f, now, low, qty = ns.Signal(id)
            local d = { id = id, sig = sig, f = f, now = now, low = low, qty = qty }
            local txt = sig and sig.buy and ("|cff40ff40Kaufchance %d%%|r"):format(math.floor(sig.buy * 100 + 0.5))
                or (not f and ("|cff808080" .. (ns.WhyNot(id) or "keine Scans") .. "|r")) or ""
            out[#out + 1] = { d, txt }
        end
        table.sort(out, function(a, b) return ns.ItemName(a[1].id) < ns.ItemName(b[1].id) end)
    end
    return out
end

---------------------------------------------------------------------------
-- pages without a list
---------------------------------------------------------------------------
local function HomeText()
    local found = ns.Sources.Found()
    local items, fc, days = 0, 0, {}
    for _, hist in pairs(ns.db.items) do
        items = items + 1
        for _, e in ipairs(hist) do days[e[1]] = true end
    end
    local nd = 0
    for _ in pairs(days) do nd = nd + 1 end
    fc = #scan.rows
    local t = {}
    t[#t + 1] = "|cffffd100Scan-Addons gefunden:|r " .. (#found > 0 and table.concat(found, ", ") or "|cffff6060keins - installiere Auctionator (empfohlen), Auctioneer oder TSM|r")
    t[#t + 1] = ("|cffffd100Gespeichert:|r %d Items, Preise von %d verschiedenen Tagen."):format(items, nd)
    t[#t + 1] = ("|cffffd100Mit Prognose:|r %s Items (mit mind. %d Stück im Angebot)."):format(scan.built and fc or "...", ns.db.settings.minQty)
    t[#t + 1] = "|cffffd100Zuletzt übernommen:|r " .. (ns.db.lastImport and date("%d.%m. %H:%M", ns.db.lastImport) or "noch nie")
    t[#t + 1] = "|cffffd100Wochentage:|r " .. (ns.db.weekday and "werden berücksichtigt" or "noch nicht (braucht 14 Tage Scans)")
    if nd > 0 and nd < 4 then t[#t + 1] = ("\n|cffff9060Noch %d Tag(e) scannen, dann gibt es die ersten Prognosen.|r"):format(4 - nd) end
    t[#t + 1] = "\n|cffffd100Woher kommen die Preise?|r Nur aus deinen eigenen Scans. Auctionator merkt sich pro Tag den günstigsten Preis jedes Items (21 Tage lang); AHPrognose übernimmt das und hebt es länger auf (Einstellung \"Tage aufheben\"). Auctioneer und TSM liefern nur den heutigen Preis - darum täglich scannen."
    t[#t + 1] = "\n|cffffd100Wie wird geschätzt?|r Aus dem Verlauf jedes Items: der übliche Preis der letzten Tage, wohin er sich bewegt (Trend, vorsichtig gebremst) und ob Ausreißer zum Preis der letzten 2 Wochen zurückkehren. Für jedes Item wird die Rechenweise gewählt, die seinen eigenen bisherigen Verlauf am besten vorhergesagt hätte. Der Bereich zeigt, wie stark das Item bisher schwankte."
    t[#t + 1] = "\n|cffffd100Befehle:|r /ahp (Fenster), /ahp import (Preise jetzt übernehmen), /ahp reset (alles löschen)"
    return table.concat(t, "\n")
end

local function AccText()
    local t = {}
    local any
    for _, h in ipairs(ns.HORIZONS) do
        local a = ns.db.acc[h]
        if a and (a.n or 0) > 0 and a.err and a.naive and a.hit then
            any = true
            local hit = a.hit / a.n * 100
            local me, naive = (math.exp(a.err / a.n) - 1) * 100, (math.exp(a.naive / a.n) - 1) * 100
            local verdict = me < naive * 0.95 and "|cff40ff40besser als \"bleibt gleich\"|r"
                or me > naive * 1.05 and "|cffff6060schlechter als \"bleibt gleich\" - diesem Zeitraum nicht trauen|r"
                or "|cffffd100etwa gleich gut wie \"bleibt gleich\"|r"
            t[#t + 1] = ("|cffffd100In %d Tag%s|r  (%d Prognosen geprüft)"):format(h, h == 1 and "" or "en", a.n)
            t[#t + 1] = ("   Echter Preis im Bereich: |cffffffff%d%%|r (Ziel etwa 80%%)"):format(math.floor(hit + 0.5))
            t[#t + 1] = ("   Typische Abweichung: Prognose |cffffffff%d%%|r, \"bleibt gleich\" |cffffffff%d%%|r  -> %s"):format(math.floor(me + 0.5), math.floor(naive + 0.5), verdict)
            t[#t + 1] = ""
        end
    end
    if not any then
        t[#t + 1] = "Noch nichts geprüft. Die ersten Ergebnisse gibt es, sobald es Prognosen gibt und danach an einem weiteren Tag gescannt wurde (für \"in 3 Tagen\" 3 Tage später)."
    end
    t[#t + 1] = "\nEs werden täglich die 400 meistgehandelten Items und deine Merkliste geprüft."
    return table.concat(t, "\n")
end

---------------------------------------------------------------------------
-- settings page
---------------------------------------------------------------------------
local OPTS = {
    { "autoImport", "check", "Preise automatisch übernehmen", "Beim Schließen des Auktionshauses und beim Einloggen. Aus: nur per Knopf \"Jetzt übernehmen\" oder /ahp import." },
    { "tooltip", "check", "Prognose im Tooltip", "Zeigt beim Item-Tooltip den erwarteten Preis und ob gerade eine Kaufchance ist." },
    { "alerts", "check", "Chat-Meldung für die Merkliste", "Meldet im Chat, wenn ein Item deiner Merkliste gerade eine Kaufchance ist." },
    { "horizon", "list", "Prognose für", "Welcher Zeitraum in den Listen und im Tooltip gezeigt wird. Kürzer = genauer.", { 1, 3, 7 }, function(v) return v .. (v == 1 and " Tag" or " Tage") end },
    { "minConf", "list", "Mindest-Vertrauen", "Listen zeigen nur Prognosen mit mindestens diesem Vertrauen. Niedrig zeigt mehr Items, aber unsichere.", { 1, 2, 3 }, function(v) return ns.CONF_TEXT[v] end },
    { "minQty", "num", "Mindest-Stückzahl im AH", "Nur Items, von denen beim Scan mindestens so viele im Angebot waren. Bei einem einzigen Angebot sagt der Preis wenig.", 1, 50, 1 },
    { "buyPct", "num", "Kaufchance ab ... % unter Erwartung", "Wie viel billiger als erwartet ein Item sein muss, damit es unter Kaufchancen steht.", 5, 50, 5, "%" },
    { "sellPct", "num", "Verkaufstipp ab ... % Bewegung", "Wie stark der Preis voraussichtlich fallen oder steigen muss, damit \"Jetzt verkaufen\" oder \"Warten\" erscheint.", 5, 50, 5, "%" },
    { "keepDays", "num", "Tage aufheben", "So viele Tage Preis-Verlauf behält AHPrognose. Mehr Tage = bessere Prognosen, aber größere Datei.", 21, 120, 7, " Tage" },
}

local function BuildOptions(page)
    local y = -4
    page.controls = {}
    for _, o in ipairs(OPTS) do
        local key, kind, label, help = o[1], o[2], o[3], o[4]
        local c = {}
        if kind == "check" then
            local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb:SetPoint("TOPLEFT", 0, y)
            cb:SetScript("OnClick", function(self)
                ns.db.settings[key] = self:GetChecked() and true or false
                ns.RefreshUI()
            end)
            c.refresh = function() cb:SetChecked(ns.db.settings[key]) end
            local fs = Text(page, 12)
            fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
            fs:SetText(label)
        else
            local fs = Text(page, 12)
            fs:SetPoint("TOPLEFT", 4, y - 4)
            fs:SetText(label)
            local minus = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
            minus:SetSize(24, 20)
            minus:SetPoint("TOPLEFT", 300, y - 1)
            minus:SetText("-")
            local val = Text(page, 12, GOLD, "CENTER")
            val:SetPoint("LEFT", minus, "RIGHT", 4, 0)
            val:SetWidth(80)
            local plus = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
            plus:SetSize(24, 20)
            plus:SetPoint("LEFT", val, "RIGHT", 4, 0)
            plus:SetText("+")
            local function change(dir)
                local s = ns.db.settings
                if kind == "list" then
                    local list, idx = o[5], 1
                    for i, v in ipairs(list) do if v == s[key] then idx = i end end
                    s[key] = list[math.max(1, math.min(#list, idx + dir))]
                else
                    s[key] = math.max(o[5], math.min(o[6], s[key] + dir * o[7]))
                end
                if key == "minQty" or key == "buyPct" or key == "sellPct" then ns.RebuildScan() end
                if key == "keepDays" then for _, hist in pairs(ns.db.items) do ns.Prune(hist) end; ns.Invalidate(); ns.RebuildScan() end
                ns.RefreshUI()
            end
            minus:SetScript("OnClick", function() change(-1) end)
            plus:SetScript("OnClick", function() change(1) end)
            c.refresh = function()
                local v = ns.db.settings[key]
                val:SetText(kind == "list" and o[6](v) or (v .. (o[8] or "")))
            end
        end
        local hs = Text(page, 10, MUTED)
        hs:SetPoint("TOPLEFT", 26, y - 22)
        hs:SetWidth(W - 70)
        hs:SetText(help)
        page.controls[#page.controls + 1] = c
        y = y - 46
    end
    local imp = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    imp:SetSize(160, 22)
    imp:SetPoint("TOPLEFT", 0, y - 4)
    imp:SetText("Jetzt übernehmen")
    imp:SetScript("OnClick", function() ns.Import() end)
    local rst = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    rst:SetSize(160, 22)
    rst:SetPoint("LEFT", imp, "RIGHT", 8, 0)
    rst:SetText("Alles löschen")
    rst:SetScript("OnClick", function() StaticPopup_Show("AHPROGNOSE_RESET") end)
    local hs = Text(page, 10, MUTED)
    hs:SetPoint("TOPLEFT", imp, "BOTTOMLEFT", 26, -4)
    hs:SetWidth(W - 70)
    hs:SetText("\"Jetzt übernehmen\" liest sofort die Preise deines Scan-Addons. \"Alles löschen\" entfernt alle gespeicherten Preise, Prüfungen und die Merkliste (die Einstellungen bleiben).")
end

---------------------------------------------------------------------------
-- the window
---------------------------------------------------------------------------
local function Build()
    frame = CreateFrame("Frame", "AHPrognoseFrame", UIParent, "BackdropTemplate")
    local f = frame
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.06, 0.07, 0.09, 0.95)
    f:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, "AHPrognoseFrame")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    local title = Text(f, 14, GOLD)
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText("AHPrognose  |cff9aa0aa- Preis-Prognosen aus deinen eigenen Scans|r")

    f.tabs = {}
    local x = 12
    for _, t in ipairs(TABS) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        local w = math.max(80, #t[2] * 7 + 20)
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", x, -36)
        x = x + w + 3
        b:SetText(t[2])
        b:SetScript("OnClick", function() view = t[1]; offset = 0; ns.RefreshUI() end)
        f.tabs[t[1]] = b
    end

    f.help = Text(f, 11, MUTED)
    f.help:SetPoint("TOPLEFT", 16, -66)
    f.help:SetWidth(W - 32)

    -- search box (Prognosen)
    f.search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.search:SetSize(200, 20)
    f.search:SetAutoFocus(false)
    f.search:SetPoint("TOPRIGHT", -18, -104)
    f.search:SetScript("OnTextChanged", function(self) search = self:GetText() or ""; offset = 0; ns.RefreshUI() end)
    f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.searchLabel = Text(f, 11, MUTED)
    f.searchLabel:SetPoint("RIGHT", f.search, "LEFT", -8, 0)
    f.searchLabel:SetText("Suche:")

    -- column headers
    f.header = CreateFrame("Frame", nil, f)
    f.header:SetPoint("TOPLEFT", 14, -128)
    f.header:SetSize(W - 28, 16)
    local hx = 0
    for _, col in ipairs(COLS) do
        local fs = Text(f.header, 11, GOLD)
        fs:SetPoint("LEFT", hx + (hx == 0 and 22 or 0), 0)
        fs:SetText(col[1])
        hx = hx + col[2]
    end

    f.list = CreateFrame("Frame", nil, f)
    f.list:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -2)
    f.list:SetSize(W - 28, ROWS * ROW_H)
    f.list:EnableMouseWheel(true)
    f.list:SetScript("OnMouseWheel", function(_, delta) offset = offset - delta * 3; ns.RefreshUI() end)
    for i = 1, ROWS do rows[i] = MakeRow(f.list, i) end
    f.empty = Text(f.list, 12, MUTED)
    f.empty:SetPoint("TOPLEFT", 4, -8)
    f.empty:SetWidth(W - 40)
    f.page = Text(f, 11, MUTED)
    f.page:SetPoint("BOTTOMRIGHT", -18, 14)
    f.status = Text(f, 11, MUTED)
    f.status:SetPoint("BOTTOMLEFT", 16, 14)

    -- text page (Übersicht, Genauigkeit)
    f.textPage = Text(f, 12)
    f.textPage:SetPoint("TOPLEFT", 16, -118)
    f.textPage:SetWidth(W - 32)

    -- settings page
    f.opt = CreateFrame("Frame", nil, f)
    f.opt:SetPoint("TOPLEFT", 16, -100)
    f.opt:SetSize(W - 32, H - 130)
    BuildOptions(f.opt)

    -- Übersicht: import button
    f.import = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.import:SetSize(160, 22)
    f.import:SetPoint("BOTTOMLEFT", 14, 34)
    f.import:SetText("Jetzt übernehmen")
    f.import:SetScript("OnClick", function() ns.Import() end)

    f:SetScript("OnShow", function() if not scan.built then BuildScan(ns.RefreshUI) end end)
end

function ns.RefreshUI()
    if not (frame and frame:IsShown()) then return end
    local f = frame
    for _, t in ipairs(TABS) do
        f.tabs[t[1]]:SetEnabled(view ~= t[1])
        if view == t[1] then f.help:SetText(t[3]) end
    end
    local isList = view == "list" or view == "buy" or view == "sell" or view == "watch"
    f.header:SetShown(isList)
    f.list:SetShown(isList)
    f.page:SetShown(isList)
    f.search:SetShown(view == "list")
    f.searchLabel:SetShown(view == "list")
    f.textPage:SetShown(view == "home" or view == "acc")
    f.opt:SetShown(view == "opt")
    f.import:SetShown(view == "home")
    f.status:SetText(ns.ImportRunning() and "Übernehme Preise ..." or scan.running and "Berechne Prognosen ..." or "")

    if view == "home" then f.textPage:SetText(HomeText())
    elseif view == "acc" then f.textPage:SetText(AccText())
    elseif view == "opt" then for _, c in ipairs(f.opt.controls) do c.refresh() end end
    if not isList then return end

    local data = Filtered()
    -- buy / sell signals are only shown as proven once the self-check says the forecasts beat "price stays the same"
    if view == "buy" or view == "sell" then
        local a = ns.db.acc[3]
        local proven = a and a.err and a.naive and (a.n or 0) >= 200 and a.err < a.naive * 0.97
        f.help:SetText(f.help:GetText() .. (proven and "\n|cff40ff40Die Selbstprüfung (Tab Genauigkeit) zeigt: die 3-Tage-Prognosen sind besser als \"bleibt gleich\".|r"
            or "\n|cffff9060Noch nicht bewiesen: die Selbstprüfung (Tab Genauigkeit) hat noch nicht genug geprüft oder die Prognose ist nicht besser als \"bleibt gleich\". Nur als Hinweis nutzen.|r"))
    end
    offset = math.max(0, math.min(offset, #data - ROWS))
    for i = 1, ROWS do
        local d = data[offset + i]
        if d then FillRow(rows[i], d[1], d[2]) else rows[i].id = nil; rows[i]:Hide() end
    end
    if #data == 0 then
        local msg = not scan.built and "Berechne Prognosen ..."
            or view == "watch" and "Die Merkliste ist leer. Rechtsklick auf ein Item unter \"Prognosen\" setzt es auf die Merkliste."
            or view == "sell" and "Keine handelbaren Items mit Scan-Daten in deinen Taschen."
            or view == "buy" and "Gerade keine Kaufchancen. Das ist normal - sie entstehen, wenn jemand ein Item deutlich unter Wert einstellt."
            or (#scan.rows == 0 and "Noch keine Prognosen. Scanne an mindestens 4 Tagen das Auktionshaus (siehe Übersicht)." or "Nichts gefunden.")
        f.empty:SetText(msg)
        f.empty:Show()
    else
        f.empty:Hide()
    end
    f.page:SetText(#data > ROWS and ("%d-%d von %d  (Mausrad zum Blättern)"):format(offset + 1, math.min(#data, offset + ROWS), #data) or (#data > 0 and (#data .. " Items") or ""))
    f.page:SetShown(true)
end

function ns.ToggleUI()
    if not frame then Build() end
    if frame:IsShown() then frame:Hide() else frame:Show(); ns.RefreshUI() end
end

-- after each import: forecasts changed
function ns.OnImported()
    scan.built = false
    if frame and frame:IsShown() then BuildScan(ns.RefreshUI) end
end

---------------------------------------------------------------------------
-- tooltip
---------------------------------------------------------------------------
local function OnItemTooltip(tt, data)
    if not (ns.db and ns.db.settings.tooltip) then return end
    if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
    local id = data and data.id
    if type(id) ~= "number" or not ns.db.items[id] then return end
    local f, why = ns.Forecast(id)
    local h = ns.db.settings.horizon
    if not f then
        tt:AddLine("AHPrognose: " .. (why or "noch keine Prognose"), 0.6, 0.63, 0.7)
        return
    end
    local now = ns.Now(id)
    tt:AddDoubleLine(("AHPrognose in %d Tag%s:"):format(h, h == 1 and "" or "en"),
        ("%s  %s"):format(ns.Money(f[h].price), now and PctColor(f[h].price / now - 1) or ""), 0.31, 0.76, 0.97, 1, 1, 1)
    tt:AddDoubleLine("   Bereich / Vertrauen:", ("%s - %s  %s"):format(ns.Money(f[h].low), ns.Money(f[h].high), Conf(f.conf)), 0.6, 0.63, 0.7, 1, 1, 1)
    -- crafted items: today's material cost and how far the price is from it (details in the detail window)
    local mk = f.market
    if mk and mk.kind == "cost" then
        tt:AddDoubleLine("   Herstellen (Material):", ("%s  %s"):format(ns.Money(mk.cost), PctColor(mk.ratio - 1)), 0.6, 0.63, 0.7, 1, 1, 1)
    elseif mk and mk.kind == "supply" and f.shift then
        tt:AddLine(("   Viel mehr Angebot (%d statt %d): Preis fällt oft"):format(mk.qtyNow, mk.qtyBefore), 0.6, 0.63, 0.7)
    end
    local sig = ns.Signal(id)
    if sig and sig.buy then tt:AddLine(("   Kaufchance: %d%% unter Erwartung"):format(math.floor(sig.buy * 100 + 0.5)), 0.25, 1, 0.25) end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        local ok, err = pcall(OnItemTooltip, tt, data)
        if not ok and ns.db then ns.db.lastError = tostring(err) end
    end)
end

-- for the offline tests (wow-addon-tools/tests/t_ahp.lua)
function ns._SetView(v) view = v; offset = 0; ns.RefreshUI() end
ns._ShowDetail = function(id) ShowDetail(id) end
function ns._Rows(v) view = v; local n = #Filtered(); ns.RefreshUI(); return n end
