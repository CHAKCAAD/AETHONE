# Traffic Analytics — Design Research (Figma Community)

Written 2026-11-26, before any UI code (prompt §2.G). Scope: the Android
Traffic Analytics screens of AETHONE.

## 0. What could and could not be inspected — read this first

* **No Figma account / API token was available to the build environment.**
  The Figma *editor* (frames, layers, auto-layout, variants, prototype
  links) requires a signed-in session; Community pages only expose the
  title, author, description, licence and preview images to an anonymous
  client. Therefore **no source frame of any file below was opened in the
  editor**, and no claim is made about their layer structure, variants,
  grids or prototype interactions beyond what the authors' own descriptions
  say.
* **What WAS inspected in full:** the owner's own export of
  *Charts UI KIT (Community)* — 30 chart frames, 600×600 PNG each
  (`Charts UI KIT (Community) (Community).zip`), studied as contact sheets
  at pixel level (bar styles, track bars, highlight pills, tooltip chips,
  legends, donut / ring / gauge / pie, smooth line + area, dual-line,
  dashed comparison line, combo bar+line, Gantt, bubble).
* For every other file: the Community page (description, licence,
  metadata) was read; preview images were not downloadable as originals.

## 1. Files reviewed

| # | File | Link | Licence | Inspected |
|---|---|---|---|---|
| 1 | Charts UI KIT (Community) | https://www.figma.com/design/9QGWhOCZVE1l1EkSTqtcSp/Charts-UI-KIT--Community---Community-?node-id=0-1 | Community file (CC BY 4.0 is Figma Community's default; the remix link itself was not opened) | **owner's 30-frame PNG export, fully** |
| 2 | 59 Charts UI Responsive Components (Iago Sousa) | https://www.figma.com/community/file/1136725187967938411 | CC BY 4.0 | page + description |
| 3 | Data Visualization Graphs / Charts Kit (DMS Studio) | https://www.figma.com/community/file/1199721318228257277 | CC BY 4.0 | page + description; 15 public comments say the free file is images/a teaser for a paid kit → **rejected as a source** |
| 4 | SnowUI Dashboard UI Kit (ByeWind) | https://www.figma.com/community/file/1210542873091115123 | CC BY 4.0 | page + description |
| 5 | Mobile Charts & Tables — 17 chart types, light & dark (Bohouš Poláček) | https://www.figma.com/community/file/1689937979750008051/mobile-charts-tables-for-figma-free-17-chart-types-data-tables-light-dark | CC BY 4.0 | page + description |
| 6 | Sales Analytics — Mobile UI Kit Light & Dark (Sunie) | https://www.figma.com/community/file/1274706651798894123/sales-analytics-mobile-ui-kit-light-dark-theme-free | CC BY 4.0 | page + description |
| 7 | Dark Mode Mobile UI for Market Data Analysis | https://www.figma.com/community/file/1531125089859017414/dark-mode-mobile-ui-interface-for-market-data-analysis-with-statistical-comparison | not read | search result only |
| 8 | VPN Analytics Dashboard Redesign | https://www.figma.com/community/file/1606379382872449494/vpn-analytics-dashboard-redesign | not read | search result only (desktop, glow/glass — rejected) |
| 9 | Network Traffic Dashboard Design | https://www.figma.com/community/file/1601527006052679604/network-traffic-dashboard-design | CC BY 4.0 | search result only |

## 2. Patterns selected and why

| Component in AETHONE | Taken from | Why |
|---|---|---|
| **Area chart** (download + upload) | Kit #1 frames 18/22 (smooth line, vertical gradient fill fading to 0, one selected guide + dark tooltip chip) | The calmest time-series in the set; gradient-to-zero keeps a dark card quiet. AETHONE adds: monotone curve (no overshoot below 0 — #1's spline overshoots), 3 hairlines only, byte-aware «nice» axis. |
| **Tooltip** | Kit #1 (dark rounded chip with value) | Small, high-contrast; AETHONE inverts it per theme and lists time + ↓/↑ with colour dots. |
| **Live speed line** | Kit #1 frame 28 (thin line, last point marked) + #5's «sparkline» definition | A 60-second window needs no axis: right-aligned newest sample + dot. |
| **Donut** (route share) | Kit #1 frames 9/10 and 22 (thick ring, rounded caps, value in the hole) | Two to four slices max (routes of one profile) — exactly what a donut does well. Gaps between slices, selected slice thickens. |
| **Horizontal bars** (apps) | Kit #1 frame 7 (rounded horizontal bars) + track-bar idea of frames 1/3 (grey full-length track behind) | Stacked download/upload inside one rounded track reads per row without an axis. |
| **Sparklines** in the app list | #5 (sparkline as a first-class mobile chart) | Trend at a glance in a list row, no labels. |
| **Comparison** | Kit #1 frames 1/3 «value over track» | Two bars on one scale (current vs previous) + a % chip — no dual-axis combo (frame 27 rejected as too busy for mobile). |
| **Stat cards** | SnowUI (#4) KPI cards: caption over large figure, quiet secondary row | Matches AETHONE's own settings cards (r22, dark card, IRANYekanX). |
| **Range selector** | #6 (mobile period pills) | Horizontal scrollable pills — AETHONE's own pill style (green selected, track unselected). |
| **Empty / loading** | #5 («Empty states» are explicit components) | Every chart has a written empty state; nothing draws a fake flat zero line. |

Rejected: pie with exploded wedge (#1 frame 11), bubble chart, Gantt,
dual-axis combo, glow/glass (#8), and every 3-colour series palette.

## 3. Harmonised into AETHONE's language

* **Colour:** only AETHONE's own: download = green `#1AD995`/`#2FF8B1`
  (connected), upload = red `#FF5B5E`/`#EA2323` (the app's UP stat red);
  extra routes use deeper tints of those two. Hairlines = text-secondary @ 12 %.
* **Type:** IRANYekanX everywhere; numbers LTR inside RTL rows.
* **Shape:** card radius 22 (SubSectionCard), pills r14–16, 2 px strokes
  with round caps, 11 px donut ring, bars with fully rounded ends.
* **Frame:** every screen is a `SubPageFrame` (theme tile, back tile, page
  header, cascade entrance) — the same chrome as every settings page; no
  other page changes.
* **Direction:** content follows the app language (RTL for fa); time axes
  stay left→right.
* **Dark & light:** all colours read from the live palette.

## 4. Final structure

1. **Traffic Analytics** (settings › categories): range pills → totals card
   (total, ↓, ↑, average, peak) → area chart → Live (speeds, 60 s line,
   active routes, active apps) → Routes (donut + rows → Route details) →
   Apps (top 5 bars → All apps / App details) → Compare (vs previous period,
   biggest app changes) → Measurement coverage (unattributed, unmeasured) →
   History & export.
2. **All apps:** search, ranked list with icon, sparkline, stacked bar.
3. **App details:** icon + package, totals & speeds, hourly / daily chart,
   per-route table (WARP vs WARP → Psiphon), top domains.
4. **Route details:** totals, chart, apps on the route.
5. **History & export:** record on/off, domain names on/off, retention,
   CSV / JSON export, clear.

## 5. Licence / attribution

No asset, image or vector from any file is shipped: every chart is a
Flutter `CustomPainter` written for AETHONE, informed by the patterns above.
Attribution (CC BY 4.0, voluntary since nothing is redistributed): Charts
UI KIT (Community); Iago Sousa — 59 Charts; ByeWind — SnowUI; Bohouš
Poláček — Mobile Charts & Tables; Sunie — Sales Analytics Mobile UI Kit.
