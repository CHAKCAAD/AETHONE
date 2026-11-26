package com.chakcaad.aethone.shield

/// Family Shield — compiles the active profile (categories, unknown-domain
/// policy, strict options), the parent's rules and the category database
/// into one snapshot spec (pure JVM).
///
/// Domain lists (HaGeZi, OISD, StevenBlack, UT1, Phishing.Database) block a
/// name and everything under it, so list entries are "root" rules: their
/// category bits go to both the name (self) and its subdomains (sub).
object ShieldCompiler {
    /// A category database: name → category mask (root semantics), and
    /// CIDR → category mask. Built on the device from the content sources
    /// (ContentSources.kt); an empty database is valid (rules only).
    class CategoryDatabase(
        /// root semantics: the name and every subdomain
        val domains: Map<String, Long> = emptyMap(),
        val cidrs: Map<Cidr, Long> = emptyMap(),
        val version: String = "none",
        /// exact semantics (hosts-file lists): only the listed name
        val exactDomains: Map<String, Long> = emptyMap(),
    )

    data class Result(val bytes: ByteArray, val domains: Int, val cidrs: Int, val conflicts: List<String>)

    fun headerFlags(profile: AgeProfile): Int {
        var f = 0
        if (profile.unknownPolicy == UnknownPolicy.BLOCK) f = f or ShieldSnapshot.FLAG_UNKNOWN_BLOCK
        val s = profile.strict
        if (s.enabled) {
            if (s.blockDot) f = f or ShieldSnapshot.FLAG_STRICT_DOT
            if (s.blockQuic) f = f or ShieldSnapshot.FLAG_STRICT_QUIC
            if (s.blockAltDns) f = f or ShieldSnapshot.FLAG_STRICT_ALT_DNS
            if (s.blockDirectIp) f = f or ShieldSnapshot.FLAG_STRICT_DIRECT_IP
        }
        return f
    }

    /// [suppressDot]: Android Private DNS is in strict (hostname) mode — the
    /// system resolver talks DoT on 853, so blocking 853 would cut the whole
    /// device's DNS; the switch is dropped (status reports Degraded).
    fun compile(
        profile: AgeProfile,
        rules: List<ParentRule>,
        db: CategoryDatabase,
        generation: Int,
        suppressDot: Boolean = false,
    ): Result {
        val mandatory = ShieldCategory.mandatoryMask
        val enabled = ShieldCategory.maskOf(profile.categories.filter { !it.allowList }) or mandatory
        val allow = ShieldCategory.maskOf(profile.allowCategories.filter { it.allowList })
        var flags = headerFlags(profile)
        if (suppressDot) flags = flags and ShieldSnapshot.FLAG_STRICT_DOT.inv()
        val spec = ShieldSnapshot.Spec(flags, generation, enabled, mandatory, allow, profile.preset.ordinal)
        // only the bits this profile can act on are kept: identical verdicts,
        // a much smaller snapshot
        val relevant = enabled or allow
        for ((name, mask) in db.domains) {
            val m = mask and relevant
            if (m == 0L || !DomainNames.valid(name)) continue
            val e = spec.entry(name)
            e.selfCats = e.selfCats or m
            e.subCats = e.subCats or m
        }
        for ((name, mask) in db.exactDomains) {
            val m = mask and relevant
            if (m == 0L || !DomainNames.valid(name)) continue
            val e = spec.entry(name)
            e.selfCats = e.selfCats or m
        }
        for ((c, mask) in db.cidrs) {
            val m = mask and relevant
            if (m != 0L) spec.addCidr(c, 0, m)
        }
        val conflicts = ArrayList<String>()
        val seen = HashMap<Pair<RuleKind, String>, RuleAction>()
        for (r in rules.filter { it.profileId == profile.id }) {
            val prev = seen.put(r.kind to r.value, r.action)
            if (prev != null && prev != r.action) {
                // block and allow on the same value: the block wins (level 2
                // beats level 5) — reported, never silently dropped
                conflicts += "${r.kind.name.lowercase()}:${r.value}"
            }
            val bit = if (r.action == RuleAction.BLOCK) ShieldSnapshot.RULE_PARENT_BLOCK else ShieldSnapshot.RULE_PARENT_ALLOW
            when (r.kind) {
                RuleKind.EXACT -> spec.entry(r.value).apply { selfFlags = selfFlags or bit }
                RuleKind.ROOT -> spec.entry(r.value).apply {
                    selfFlags = selfFlags or bit
                    subFlags = subFlags or bit
                }
                RuleKind.WILDCARD -> spec.entry(r.value).apply { subFlags = subFlags or bit }
                RuleKind.CIDR -> Cidr.parse(r.value)?.let { spec.addCidr(it, bit, 0L) }
            }
        }
        val bytes = ShieldSnapshot.build(spec)
        // validate what we built exactly as native will (throws on any defect)
        ShieldSnapshot.Reader.parse(bytes)
        return Result(bytes, spec.domains.size, spec.cidrRules(false).size + spec.cidrRules(true).size, conflicts)
    }
}
