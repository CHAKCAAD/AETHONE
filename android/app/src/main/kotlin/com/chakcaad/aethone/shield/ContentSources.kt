package com.chakcaad.aethone.shield

import java.security.MessageDigest

/// Family Shield — category database pipeline (pure JVM): source registry
/// with licence + attribution, parsers, dedupe, validation, versioning and
/// rollback. Phase 1 ships the pipeline only: NO list is downloaded into the
/// APK (docs/family-shield-content-sources.md). On the device the lists are
/// fetched by a later phase (through the user's own tunnel), parsed here and
/// compiled into the binary snapshot; the raw files are discarded.
///
/// Licences (checked on the projects' own pages, see the doc):
///   HaGeZi DNS blocklists — GPL-3.0     OISD — GPL-3.0
///   StevenBlack/hosts     — MIT         Phishing.Database — MIT
///   UT1 (Université Toulouse Capitole) — CC BY-SA 4.0 (build on the device,
///   or distribute derived data under CC BY-SA 4.0 with attribution)
///   URLhaus (abuse.ch) — NOT used: its terms are not an open licence; never
///   bundled, never fetched by the app.
object ContentSources {
    enum class Format {
        /// one domain per line, list semantics "the name and all subdomains"
        DOMAINS_ROOT,
        /// hosts file ("0.0.0.0 name"): blocks exactly the listed name
        HOSTS_EXACT,
        /// Adblock-style "||name^" (root semantics)
        ADBLOCK_ROOT,
    }

    data class Source(
        val id: String,
        val project: String,
        val url: String,
        val licence: String,
        val licenceUrl: String,
        val attribution: String,
        val format: Format,
        val category: ShieldCategory,
        /// true only when shipping the derived data inside the APK would be
        /// licence-clean for an AGPL-3.0 app; phase 1 bundles nothing anyway.
        val bundleAllowed: Boolean,
        /// the list must keep at least this many entries, else it is treated
        /// as a broken / truncated download and the previous version stays.
        val minEntries: Int,
    )

    private const val HAGEZI = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/"
    private const val HAGEZI_LIC = "https://github.com/hagezi/dns-blocklists/blob/main/LICENSE"
    private const val SB = "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/"
    private const val SB_LIC = "https://github.com/StevenBlack/hosts/blob/master/license.txt"
    private const val UT1 = "https://raw.githubusercontent.com/olbat/ut1-blacklists/master/blacklists/"
    private const val UT1_LIC = "https://creativecommons.org/licenses/by-sa/4.0/"
    private const val UT1_ATTR = "UT1 blacklists, Université Toulouse Capitole (Fabrice Prigent), CC BY-SA 4.0 — https://dsi.ut-capitole.fr/blacklists/"

    /// The registry. URLs were checked to answer HTTP 200 on 2026-11-26.
    val all: List<Source> = listOf(
        Source("hagezi-tif", "HaGeZi Threat Intelligence Feeds", HAGEZI + "tif-onlydomains.txt", "GPL-3.0", HAGEZI_LIC,
            "HaGeZi DNS Blocklists (GPL-3.0) — https://github.com/hagezi/dns-blocklists", Format.DOMAINS_ROOT, ShieldCategory.MALWARE, true, 10_000),
        Source("hagezi-gambling", "HaGeZi Gambling", HAGEZI + "gambling-onlydomains.txt", "GPL-3.0", HAGEZI_LIC,
            "HaGeZi DNS Blocklists (GPL-3.0)", Format.DOMAINS_ROOT, ShieldCategory.GAMBLING, true, 1_000),
        Source("hagezi-nsfw", "HaGeZi NSFW", HAGEZI + "nsfw-onlydomains.txt", "GPL-3.0", HAGEZI_LIC,
            "HaGeZi DNS Blocklists (GPL-3.0)", Format.DOMAINS_ROOT, ShieldCategory.ADULT, true, 1_000),
        Source("hagezi-social", "HaGeZi Social Networks", HAGEZI + "social-onlydomains.txt", "GPL-3.0", HAGEZI_LIC,
            "HaGeZi DNS Blocklists (GPL-3.0)", Format.DOMAINS_ROOT, ShieldCategory.SOCIAL, true, 100),
        Source("hagezi-bypass", "HaGeZi DoH/VPN/TOR/Proxy Bypass", HAGEZI + "doh-vpn-proxy-bypass-onlydomains.txt", "GPL-3.0", HAGEZI_LIC,
            "HaGeZi DNS Blocklists (GPL-3.0)", Format.DOMAINS_ROOT, ShieldCategory.BYPASS, true, 100),
        Source("hagezi-piracy", "HaGeZi Anti-Piracy", HAGEZI + "anti.piracy-onlydomains.txt", "GPL-3.0", HAGEZI_LIC,
            "HaGeZi DNS Blocklists (GPL-3.0)", Format.DOMAINS_ROOT, ShieldCategory.PIRACY, true, 100),
        Source("oisd-nsfw", "OISD nsfw", "https://nsfw.oisd.nl/domainswild2", "GPL-3.0", "https://github.com/sjhgvr/oisd/blob/main/LICENSE",
            "oisd.nl (GPL-3.0) — https://oisd.nl", Format.DOMAINS_ROOT, ShieldCategory.ADULT, true, 1_000),
        Source("stevenblack-gambling", "StevenBlack hosts — gambling", SB + "gambling-only/hosts", "MIT", SB_LIC,
            "StevenBlack/hosts (MIT) — https://github.com/StevenBlack/hosts", Format.HOSTS_EXACT, ShieldCategory.GAMBLING, true, 100),
        Source("stevenblack-porn", "StevenBlack hosts — porn", SB + "porn-only/hosts", "MIT", SB_LIC,
            "StevenBlack/hosts (MIT)", Format.HOSTS_EXACT, ShieldCategory.ADULT, true, 100),
        Source("stevenblack-social", "StevenBlack hosts — social", SB + "social-only/hosts", "MIT", SB_LIC,
            "StevenBlack/hosts (MIT)", Format.HOSTS_EXACT, ShieldCategory.SOCIAL, true, 10),
        Source("phishing-database", "Phishing.Database (active domains)",
            "https://raw.githubusercontent.com/Phishing-Database/Phishing.Database/master/phishing-domains-ACTIVE.txt",
            "MIT", "https://github.com/Phishing-Database/Phishing.Database/blob/master/LICENSE",
            "Phishing.Database (MIT) — https://github.com/Phishing-Database/Phishing.Database", Format.HOSTS_EXACT, ShieldCategory.PHISHING, true, 1_000),
        // UT1 — ShareAlike: built on the device, never shipped as part of the APK.
        Source("ut1-adult", "UT1 adult", UT1 + "adult/domains", "CC BY-SA 4.0", UT1_LIC, UT1_ATTR, Format.DOMAINS_ROOT, ShieldCategory.ADULT, false, 1_000),
        Source("ut1-gambling", "UT1 gambling", UT1 + "gambling/domains", "CC BY-SA 4.0", UT1_LIC, UT1_ATTR, Format.DOMAINS_ROOT, ShieldCategory.GAMBLING, false, 100),
        Source("ut1-dating", "UT1 dating", UT1 + "dating/domains", "CC BY-SA 4.0", UT1_LIC, UT1_ATTR, Format.DOMAINS_ROOT, ShieldCategory.DATING, false, 100),
        Source("ut1-drugs", "UT1 drogue", UT1 + "drogue/domains", "CC BY-SA 4.0", UT1_LIC, UT1_ATTR, Format.DOMAINS_ROOT, ShieldCategory.DRUGS, false, 10),
        Source("ut1-violence", "UT1 agressif", UT1 + "agressif/domains", "CC BY-SA 4.0", UT1_LIC, UT1_ATTR, Format.DOMAINS_ROOT, ShieldCategory.VIOLENCE, false, 10),
        Source("ut1-weapons", "UT1 dangerous_material", UT1 + "dangerous_material/domains", "CC BY-SA 4.0", UT1_LIC, UT1_ATTR, Format.DOMAINS_ROOT, ShieldCategory.WEAPONS, false, 1),
        Source("ut1-games", "UT1 games", UT1 + "games/domains", "CC BY-SA 4.0", UT1_LIC, UT1_ATTR, Format.DOMAINS_ROOT, ShieldCategory.GAMES, false, 100),
        Source("ut1-chat", "UT1 chat", UT1 + "chat/domains", "CC BY-SA 4.0", UT1_LIC, UT1_ATTR, Format.DOMAINS_ROOT, ShieldCategory.CHAT, false, 10),
        Source("ut1-vpn", "UT1 vpn", UT1 + "vpn/domains", "CC BY-SA 4.0", UT1_LIC, UT1_ATTR, Format.DOMAINS_ROOT, ShieldCategory.BYPASS, false, 10),
        Source("ut1-doh", "UT1 doh", UT1 + "doh/domains", "CC BY-SA 4.0", UT1_LIC, UT1_ATTR, Format.DOMAINS_ROOT, ShieldCategory.BYPASS, false, 10),
        Source("ut1-phishing", "UT1 phishing", UT1 + "phishing/domains", "CC BY-SA 4.0", UT1_LIC, UT1_ATTR, Format.DOMAINS_ROOT, ShieldCategory.PHISHING, false, 100),
        Source("ut1-malware", "UT1 malware", UT1 + "malware/domains", "CC BY-SA 4.0", UT1_LIC, UT1_ATTR, Format.DOMAINS_ROOT, ShieldCategory.MALWARE, false, 10),
        Source("ut1-warez", "UT1 warez", UT1 + "warez/domains", "CC BY-SA 4.0", UT1_LIC, UT1_ATTR, Format.DOMAINS_ROOT, ShieldCategory.PIRACY, false, 10),
        Source("ut1-social", "UT1 social_networks", UT1 + "social_networks/domains", "CC BY-SA 4.0", UT1_LIC, UT1_ATTR, Format.DOMAINS_ROOT, ShieldCategory.SOCIAL, false, 10),
        Source("ut1-child", "UT1 child (positive list)", UT1 + "child/domains", "CC BY-SA 4.0", UT1_LIC, UT1_ATTR, Format.DOMAINS_ROOT, ShieldCategory.KIDS_SAFE, false, 10),
    )

    /// Never used, recorded so nobody adds it by accident.
    const val URLHAUS_EXCLUDED =
        "URLhaus (abuse.ch): terms of use are not an open licence (auth key, non-profit scope, no redistribution " +
            "without consent) — never bundled, never fetched."

    fun byId(id: String): Source? = all.firstOrNull { it.id == id }

    data class Parsed(val names: Set<String>, val skipped: Int)

    /// Parses one list. Comments (#, !), blank lines, localhost/broadcast
    /// entries and anything that does not normalize are skipped.
    fun parse(format: Format, text: String): Parsed {
        val out = HashSet<String>()
        var skipped = 0
        for (raw in text.lineSequence()) {
            var line = raw.substringBefore('#').trim()
            if (line.isEmpty() || line.startsWith("!") || line.startsWith("[")) continue
            line = when (format) {
                Format.HOSTS_EXACT -> {
                    val parts = line.split(Regex("\\s+"))
                    if (parts.size >= 2 && (parts[0] == "0.0.0.0" || parts[0] == "127.0.0.1" || parts[0] == "::" || parts[0] == "::1")) parts[1]
                    else if (parts.size == 1) parts[0] else { skipped++; continue }
                }
                Format.ADBLOCK_ROOT -> {
                    if (!line.startsWith("||")) { skipped++; continue }
                    line.removePrefix("||").substringBefore('^').substringBefore('$')
                }
                Format.DOMAINS_ROOT -> line.removePrefix("*.").split(Regex("\\s+")).first()
            }
            if (line in IGNORED) continue
            val n = DomainNames.normalize(line)
            if (n == null || !n.contains('.')) { skipped++; continue }
            out += n
        }
        return Parsed(out, skipped)
    }

    private val IGNORED = setOf("localhost", "localhost.localdomain", "local", "broadcasthost", "0.0.0.0", "ip6-localhost", "ip6-loopback")

    data class SourceResult(val source: Source, val text: String, val fetchedAt: Long)

    data class SourceManifest(val id: String, val sha256: String, val entries: Int, val skipped: Int, val fetchedAt: Long, val licence: String, val attribution: String)

    data class DbBuild(
        val db: ShieldCompiler.CategoryDatabase,
        val manifest: List<SourceManifest>,
        /// sources that failed validation — their previous version must be kept
        val rejected: List<Pair<String, String>>,
        val version: String,
    )

    /// Builds the category database from fetched lists: parse, validate (size
    /// floor, shrink guard against the previous build), dedupe across lists
    /// (category masks are OR-ed per name) and version it (sha256 over the
    /// per-source digests).
    fun buildDatabase(results: List<SourceResult>, previousCounts: Map<String, Int> = emptyMap()): DbBuild {
        val root = HashMap<String, Long>()
        val exact = HashMap<String, Long>()
        val manifest = ArrayList<SourceManifest>()
        val rejected = ArrayList<Pair<String, String>>()
        for (r in results) {
            val p = parse(r.source.format, r.text)
            val n = p.names.size
            if (n < r.source.minEntries) {
                rejected += r.source.id to "too-few-entries:$n<${r.source.minEntries}"
                continue
            }
            val prev = previousCounts[r.source.id]
            if (prev != null && prev > 0 && n < prev / 2) {
                rejected += r.source.id to "shrunk:$prev->$n"
                continue
            }
            val target = if (r.source.format == Format.HOSTS_EXACT) exact else root
            val bit = r.source.category.mask
            for (name in p.names) target[name] = (target[name] ?: 0L) or bit
            manifest += SourceManifest(
                r.source.id, sha256Hex(r.text.toByteArray(Charsets.UTF_8)), n, p.skipped, r.fetchedAt,
                r.source.licence, r.source.attribution,
            )
        }
        // an exact entry already covered by a root entry of the same
        // categories adds nothing: dedupe it away
        val it = exact.entries.iterator()
        while (it.hasNext()) {
            val (name, mask) = it.next()
            var covered = 0L
            for (s in DomainNames.suffixes(name)) covered = covered or (root[s] ?: 0L)
            if (mask and covered.inv() == 0L) it.remove()
        }
        val version = sha256Hex(manifest.sortedBy { it.id }.joinToString("\n") { "${it.id}:${it.sha256}" }.toByteArray()).take(16)
        return DbBuild(ShieldCompiler.CategoryDatabase(root, emptyMap(), version, exact), manifest, rejected, version)
    }

    fun sha256Hex(b: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }

    /// Versioned DB slots with rollback: a new build becomes active only
    /// after it compiled into a valid snapshot; the previous active one is
    /// kept so a bad update can be rolled back.
    class Versions {
        var active: String? = null
            private set
        var previous: String? = null
            private set

        fun promote(version: String) {
            if (version == active) return
            previous = active
            active = version
        }

        fun rollback(): Boolean {
            val p = previous ?: return false
            active = p
            previous = null
            return true
        }
    }
}
