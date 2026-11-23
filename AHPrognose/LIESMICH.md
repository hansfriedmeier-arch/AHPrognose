# AHPrognose 1.1.1 (WoW Forever)

Preis-Prognosen fürs Auktionshaus aus **deinen eigenen Scans**. AHPrognose scannt nicht selbst und nutzt keine Website-Daten.

## Benutzung
1. Auctionator (empfohlen), Auctioneer oder TSM aktiv lassen.
2. Auktionshaus öffnen und mit dem Scan-Addon einen vollen Scan machen.
3. Auktionshaus schließen: AHPrognose übernimmt die Preise automatisch (oder `/ahp import`).
4. `/ahp` öffnet das Fenster. Jeden Tag einmal scannen: ab 4 Tagen gibt es Prognosen.

Tabs: Übersicht, Prognosen, Kaufchancen, Verkaufstipps, Merkliste, Genauigkeit, Einstellungen. Jeder Tab und jede Einstellung hat im Fenster eine Erklärung.

## Quellen
- **Auctionator**: der ganze Verlauf (21 Tage), der günstigste Preis pro Tag.
- **Auctioneer**: der letzte Scan, der günstigste Stückpreis.
- **TSM**: `dbminbuyout` für bekannte Items und Taschen-Items, nur der heutige Preis.

Die Rangfolge pro Tag ist Auctionator > Auctioneer > TSM. AHPrognose hebt den Verlauf länger auf als die Scan-Addons (Einstellung "Tage aufheben").

## Wie gut ist es? (geprüft am 2026-11-18)
- **Synthetische Märkte** (`wow-addon-tools/tests/t_ahp.lua`):
  - Bei Ausreißern, Trends und Zurückschwingen ist die Prognose 4-34 % genauer als "Preis bleibt gleich".
  - Bei reinem Zufallswandern ist sie etwa 8 % schlechter; das kann keine Prognose schlagen.
- **Deine echten Auctionator-Daten** (5 Tage, 5483 Prüfungen, `wow-addon-tools/ahp/atr_backtest.lua`):
  - Morgen-Prognose 5 % genauer als "bleibt gleich".
  - 80 %-Bereich traf 80 %.
- **Kaufchancen und Verkaufstipps sind noch NICHT bewiesen.** In den 5 Tagen fiel der Markt insgesamt. Das Addon zeigt darum über diesen Listen einen Hinweis, bis seine eigene Selbstprüfung (Tab Genauigkeit) nach 200 oder mehr Prüfungen zeigt, dass die 3-Tage-Prognose besser ist.

## Neu in 1.1.0: Herstellung und Angebot (geprüft am 2026-11-23 mit 11 Tagen deiner Scans)
- **Herstellkosten:** Für alles, was man herstellen kann (Tränke, Essen, Gegenstände ...), kennt AHPrognose das Rezept aus den
  Spieldaten (Recipes.lua) und rechnet mit den Materialpreisen aus denselben Scans (Händler-Material zum Händlerpreis), was
  das Herstellen heute kostet. Steht im Detailfenster.
  Liegt der Preis weit darüber, unterbieten Hersteller oft: Prognose für morgen -13 % (über 54 % teurer) bzw. -3,5 % (12-54 %).
- **Angebot:** Viel mehr Auktionen als beim Scan am Vortag (+57 % oder mehr, z. B. Farmer werfen viel auf den Markt):
  Prognose für morgen -8 %.
- Geprüft an Tagen, die nicht zum Einstellen benutzt wurden: typischer Fehler (Median) der 1-Tages-Prognose -3 %,
  Durchschnitt -0,7 %; bei 64 % der so verschobenen Items lag der echte Preis wirklich darunter.
- Ebenfalls geprüft und **nicht** eingebaut, weil ohne Wirkung: "Produkte werden teurer -> Material folgt".
- Nur die Prognose für morgen wird verschoben (nur die ist geprüft). Die Genauigkeit-Seite misst es ab jetzt im Spiel mit.
- 1.1.1: die Materialkosten stehen auch im Item-Tooltip ("Herstellen (Material): X  +/- %").
