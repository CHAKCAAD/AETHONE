# Family Shield — content sources (phase 1)

Status: pipeline code + registry implemented and unit-tested (`ContentSources.kt`). **No list is
downloaded or bundled into the APK in phase 1.** Fetching/updating on the device is phase 2.

## 1. Sources and licences

All URLs answered HTTP 200 on 2026-11-26. Licences were read on the projects' own pages during phase 0
(HaGeZi `LICENSE`, OISD FAQ + `sjhgvr/oisd`, StevenBlack `license.txt`, Phishing.Database `LICENSE`,
UT1 official page).

| Source | Licence | Used for (category) | Format → semantics | Bundle in APK? |
|---|---|---|---|---|
| HaGeZi TIF `wildcard/tif-onlydomains.txt` | GPL-3.0 | malware (mandatory) | domains → name + subdomains | allowed (GPL-3.0 ⊂ AGPL-3.0 app) |
| HaGeZi `gambling`, `nsfw`, `social`, `doh-vpn-proxy-bypass`, `anti.piracy` (`-onlydomains.txt`) | GPL-3.0 | gambling, adult, social, bypass, piracy | domains → root | allowed |
| OISD nsfw `https://nsfw.oisd.nl/domainswild2` | GPL-3.0 | adult | domains (wildcard, "blocks subdomains") → root | allowed |
| StevenBlack `alternates/{gambling,porn,social}-only/hosts` | MIT | gambling, adult, social | hosts → exact name | allowed |
| Phishing.Database `phishing-domains-ACTIVE.txt` | MIT | phishing (mandatory) | one host per line → exact | allowed |
| UT1 (Université Toulouse Capitole) via `olbat/ut1-blacklists` mirror: adult, gambling, dating, drogue, agressif, dangerous_material, games, chat, vpn, doh, phishing, malware, warez, social_networks, **child** (positive list) | **CC BY-SA 4.0** | all age categories; `child` → `kids_safe` | domains → root | **no** — built on the device; any distributed derivative must be CC BY-SA 4.0 with attribution |
| URLhaus (abuse.ch) | terms of use, not an open licence | — | — | **never** (not fetched, not bundled) |

Attribution strings are stored per source (`Source.attribution`) and recorded in every DB manifest.

## 2. Pipeline

```
fetch (phase 2, through the user's tunnel) → parse(format) → validate → dedupe → CategoryDatabase
   → ShieldCompiler (active profile) → snapshot → native validate → atomic swap
```

* **parse:** comments (`#`, `!`), blank lines, localhost/broadcast entries skipped; every name through
  `DomainNames.normalize` (IDN → punycode, lower case, label rules); single-label names dropped.
* **validate:** per-source minimum entry count (a truncated download is refused) and a shrink guard
  (a list that lost more than half of its previous size is refused). Refused sources keep their
  previous version.
* **dedupe:** category masks OR-ed per name across lists; exact (hosts) entries already covered by a
  root entry with the same categories are dropped.
* **versioning:** per-source SHA-256 + count + fetch time + licence in a manifest; DB version = first
  16 hex of SHA-256 over the sorted per-source digests.
* **rollback:** `ContentSources.Versions` keeps the active and the previous version; a new DB becomes
  active only after it compiled into a valid snapshot.
* **size:** the compiler keeps only bits the active profile can act on (enabled + positive categories),
  so a snapshot never carries categories the child's profile ignores.

## 3. Phase-2 work (not done)

Downloading with integrity checks, scheduling (WorkManager), storage of the per-source caches,
HaGeZi DoH **IP** lists (path not verified in phase 1), UI for licences/attribution, false-positive
reporting.
