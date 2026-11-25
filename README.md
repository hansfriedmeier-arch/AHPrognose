# AHPrognose (WoW Forever)

Preis-Prognosen fürs Auktionshaus aus **deinen eigenen Scans**: was ein Item morgen, in 3 und in 7 Tagen
voraussichtlich kostet, dazu Kaufchancen und Verkaufstipps. AHPrognose scannt nicht selbst und nutzt keine
Website-Daten – es rechnet nur mit dem, was dein Scan-Addon gesehen hat.

## Funktionen
- **Prognosen** für 1, 3 und 7 Tage mit Bereich („meist zwischen … und …“) und Vertrauen (niedrig / mittel / hoch).
- **Lernt pro Item**: wählt die Rechenweise, die den bisherigen Verlauf dieses Items am besten vorhergesagt hätte
  (schwankt um einen festen Preis, folgt dem Trend, Ausreißer kommen zurück …).
- **Herstellkosten** (ab 1.1): für alles Herstellbare (Tränke, Elixiere, Essen, Gegenstände) rechnet es mit den
  Materialpreisen aus denselben Scans aus, was das Herstellen heute kostet – im Tooltip und im Detailfenster.
  Liegt der Preis weit darüber, wird die Prognose für morgen gesenkt (Hersteller unterbieten dann oft).
- **Angebot**: stehen plötzlich viel mehr Stück im Angebot als am Vortag (z. B. Farmer), wird die Prognose für morgen gesenkt.
- **Kaufchancen**: Items, die gerade deutlich unter ihrem erwarteten Preis liegen.
- **Verkaufstipps** für deine Taschen: lieber jetzt verkaufen oder warten.
- **Merkliste** mit Hinweis, wenn sich bei gemerkten Items etwas tut.
- **Genauigkeit**: misst im Spiel selbst, wie oft die Prognose stimmte und ob sie besser war als „Preis bleibt gleich“.
- **Tooltip**: Prognose, Bereich, Herstellkosten direkt am Item.

## Benutzung
1. **Auctionator** (empfohlen), Auctioneer oder TSM installiert lassen.
2. Auktionshaus öffnen und mit dem Scan-Addon einen **vollen Scan** machen.
3. Auktionshaus schließen – AHPrognose übernimmt die Preise automatisch (oder `/ahp import`).
4. **Jeden Tag einmal scannen** (am besten immer zur gleichen Zeit). Ab 4 Tagen gibt es Prognosen.

Befehle: `/ahp` (Fenster) · `/ahp import` (Preise jetzt übernehmen) · `/ahp reset` (alles löschen).
Linksklick auf ein Item = Detailfenster mit Verlauf und Erklärung, Rechtsklick = Merkliste.

## Installation
Unter [Releases](../../releases) die neueste Zip laden und nach `World of Warcraft/_forever_/Interface/AddOns/` entpacken.
Bei einem Update mit **neuen Dateien** WoW komplett neu starten (ein `/reload` lädt neue Dateien nicht).

**Mit WowUp (automatische Updates):** In WowUp WoW Forever auswählen → **Get Addons** → **Install from URL** →
`https://github.com/hansfriedmeier-arch/AHPrognose` eintragen → installieren. WowUp holt danach jede neue Version von hier
(es nimmt die Zip, die auf `-forever.zip` endet).

## Hinweise
- Die Rezepte (`Recipes.lua`) stammen aus den Spieldaten des WoW-Forever-Clients.
- Kaufchancen sind noch „nicht bewiesen“, bis die eingebaute Genauigkeitsprüfung genug Daten hat.

Autor: Nexxo-Ashenbow, Claude · Lizenz: MIT (siehe LICENSE)
