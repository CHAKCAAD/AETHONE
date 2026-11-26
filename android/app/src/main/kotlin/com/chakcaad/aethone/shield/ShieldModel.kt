package com.chakcaad.aethone.shield

/// Family Shield — data model (pure JVM; persisted by ShieldStore, the
/// SQLite source of truth on the native side — Flutter never owns it).

/// Level 6 of the priority order: what happens to a name / address no rule
/// mentions. BLOCK = allowlist-only (only parent-allowed or kids-safe
/// destinations pass).
enum class UnknownPolicy { ALLOW, BLOCK }

/// Optional bypass hardening, OFF by default (owner decision). Each switch
/// maps to one native header flag (flow/shield.zig flag_strict_*).
data class StrictOptions(
    val enabled: Boolean = false,
    /// TCP/UDP 853 — DNS-over-TLS / DNS-over-QUIC.
    val blockDot: Boolean = true,
    /// UDP 443 — QUIC / HTTP/3 (DoH3); browsers fall back to TCP.
    val blockQuic: Boolean = true,
    /// Port 53 to any address other than the tunnel's own resolver.
    val blockAltDns: Boolean = true,
    /// Any flow to a real (non fake-IP) address with no name. Breaks apps
    /// that connect by hard-coded IP (e.g. some messengers): off by default
    /// even in strict mode.
    val blockDirectIp: Boolean = false,
)

/// The product's age presets — product presets, NOT an official rating.
enum class AgePreset(val key: String, val minAge: Int, val maxAge: Int) {
    TODDLER("toddler", 3, 7),
    CHILD("child", 8, 12),
    TEEN("teen", 13, 15),
    OLDER_TEEN("older_teen", 16, 17),
    CUSTOM("custom", 0, 0),
    ;

    companion object {
        fun byKey(key: String): AgePreset? = entries.firstOrNull { it.key == key }
    }
}

data class AgeProfile(
    val id: String,
    val name: String,
    val preset: AgePreset,
    /// Blocking categories switched on (mandatory ones are always on and are
    /// added at compile time whatever this set holds).
    val categories: Set<ShieldCategory>,
    val unknownPolicy: UnknownPolicy,
    val strict: StrictOptions = StrictOptions(),
    /// Positive-list categories counted as allowed (e.g. KIDS_SAFE).
    val allowCategories: Set<ShieldCategory> = emptySet(),
    val updatedAt: Long = 0L,
)

enum class RuleKind {
    /// exactly this name
    EXACT,
    /// this name and every subdomain
    ROOT,
    /// strict subdomains only (`*.example.com`)
    WILDCARD,
    /// IPv4 / IPv6 address or CIDR
    CIDR,
}

enum class RuleAction { BLOCK, ALLOW }

/// A parent rule. BLOCK rules are the locked blocklist (level 2), ALLOW
/// rules the allowlist (level 5). Rules belong to one profile.
data class ParentRule(
    val id: String,
    val profileId: String,
    val kind: RuleKind,
    /// normalized value (see DomainNames.normalizeRule / parseCidr)
    val value: String,
    val action: RuleAction,
    val note: String? = null,
    val createdAt: Long = 0L,
)

/// App restriction (level 3): every flow of this package is rejected while
/// the profile is active. Enforced by uid at flow open (Android 10+ only).
data class AppRestriction(
    val profileId: String,
    val packageName: String,
    val createdAt: Long = 0L,
)

data class ShieldConfig(
    val enabled: Boolean = false,
    val activeProfileId: String? = null,
    /// Opt-in: store blocked domain names in the event log (default off —
    /// only counts per category/app are kept).
    val logDomains: Boolean = false,
    /// Days of aggregated events kept on the device.
    val retentionDays: Int = 30,
    /// Bumped on every policy change; written into the snapshot header.
    val generation: Int = 0,
    val updatedAt: Long = 0L,
)

data class ProfileChange(
    val at: Long,
    val fromProfileId: String?,
    val toProfileId: String?,
    val reason: String,
)

/// One aggregated event row (never a full URL; a domain only when the parent
/// opted in to domain logging).
data class EventBucket(
    /// minute bucket start (epoch ms)
    val minute: Long,
    val kind: String,
    val level: Int,
    val category: String?,
    val app: String?,
    val domain: String?,
    val count: Long,
)

/// Persistence boundary. ShieldStore (SQLite, Android) is the real one;
/// InMemoryShieldRepository backs the JVM unit tests.
interface ShieldRepository {
    fun config(): ShieldConfig
    fun saveConfig(c: ShieldConfig)
    fun profiles(): List<AgeProfile>
    fun profile(id: String): AgeProfile? = profiles().firstOrNull { it.id == id }
    fun upsertProfile(p: AgeProfile)
    fun deleteProfile(id: String)
    fun rules(profileId: String): List<ParentRule>
    fun addRule(r: ParentRule)
    fun removeRule(id: String)
    fun appRestrictions(profileId: String): List<AppRestriction>
    fun addAppRestriction(a: AppRestriction)
    fun removeAppRestriction(profileId: String, packageName: String)
    fun appendHistory(c: ProfileChange)
    fun history(limit: Int): List<ProfileChange>
    fun pinState(): PinState?
    fun savePinState(s: PinState?)
    fun addEvents(rows: List<EventBucket>)
    fun events(from: Long, to: Long): List<EventBucket>
    fun pruneEvents(before: Long)
}

class InMemoryShieldRepository : ShieldRepository {
    private var cfg = ShieldConfig()
    private val profs = LinkedHashMap<String, AgeProfile>()
    private val ruleList = ArrayList<ParentRule>()
    private val apps = ArrayList<AppRestriction>()
    private val hist = ArrayList<ProfileChange>()
    private var pin: PinState? = null
    private val ev = ArrayList<EventBucket>()

    @Synchronized override fun config() = cfg
    @Synchronized override fun saveConfig(c: ShieldConfig) { cfg = c }
    @Synchronized override fun profiles() = profs.values.toList()
    @Synchronized override fun upsertProfile(p: AgeProfile) { profs[p.id] = p }
    @Synchronized override fun deleteProfile(id: String) {
        profs.remove(id)
        ruleList.removeAll { it.profileId == id }
        apps.removeAll { it.profileId == id }
    }
    @Synchronized override fun rules(profileId: String) = ruleList.filter { it.profileId == profileId }
    @Synchronized override fun addRule(r: ParentRule) { ruleList.removeAll { it.id == r.id }; ruleList += r }
    @Synchronized override fun removeRule(id: String) { ruleList.removeAll { it.id == id } }
    @Synchronized override fun appRestrictions(profileId: String) = apps.filter { it.profileId == profileId }
    @Synchronized override fun addAppRestriction(a: AppRestriction) {
        apps.removeAll { it.profileId == a.profileId && it.packageName == a.packageName }
        apps += a
    }
    @Synchronized override fun removeAppRestriction(profileId: String, packageName: String) {
        apps.removeAll { it.profileId == profileId && it.packageName == packageName }
    }
    @Synchronized override fun appendHistory(c: ProfileChange) { hist += c }
    @Synchronized override fun history(limit: Int) = hist.takeLast(limit).reversed()
    @Synchronized override fun pinState() = pin
    @Synchronized override fun savePinState(s: PinState?) { pin = s }
    @Synchronized override fun addEvents(rows: List<EventBucket>) {
        for (r in rows) {
            val i = ev.indexOfFirst {
                it.minute == r.minute && it.kind == r.kind && it.level == r.level &&
                    it.category == r.category && it.app == r.app && it.domain == r.domain
            }
            if (i >= 0) ev[i] = ev[i].copy(count = ev[i].count + r.count) else ev += r
        }
    }
    @Synchronized override fun events(from: Long, to: Long) = ev.filter { it.minute in from until to }
    @Synchronized override fun pruneEvents(before: Long) { ev.removeAll { it.minute < before } }
}
