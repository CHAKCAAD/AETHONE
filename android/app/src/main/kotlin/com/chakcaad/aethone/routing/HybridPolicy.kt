package com.chakcaad.aethone.routing

import java.net.IDN
import java.net.Inet6Address
import java.net.InetAddress

/// Hybrid per-tunnel routing — the policy engine (pure JVM, no Android
/// types, so the JVM unit tests in src/test exercise exactly this code).
///
/// A hybrid protocol (Aether chain/reverse with Psiphon or Tor) runs two
/// independent SOCKS5 listeners at once (see docs/hybrid-routing.md §2):
/// e.g. AETHER → PSIPHON serves WARP on 127.0.0.1:1819 and WARP→Psiphon on
/// 127.0.0.1:1821. zeptun asks [decide] for every new TCP/UDP flow (the
/// route callback of scripts/zeptun-hybrid-routing.patch) and dials the
/// SOCKS5 server the answer names. A decision never means "direct".
///
/// Priority (first match wins, deterministic):
///   1. App rule        — the flow's owner uid (Android-attributed) is the
///                         rule's package. App rules beat every destination rule.
///   2. Exact domain    — the fake-IP domain equals the rule's domain.
///   3. Wildcard domain — `*.example.com` matches strict subdomains only
///                         (a.example.com, a.b.example.com — NOT example.com);
///                         the longest (most specific) suffix wins.
///   4. IP / CIDR       — the real destination address (only for flows that
///                         did not resolve through the tunnel's DNS); the
///                         longest prefix wins, ties go to the earlier rule.
///   5. Default         — the protocol's own default (unchanged) route.
class HybridPolicy private constructor(
    val profile: String,
    /// Tunnel ids in route order; index 0 is the default route.
    val tunnels: List<String>,
    private val apps: Map<String, Rule>,
    private val exact: Map<String, Rule>,
    private val wildcards: List<Pair<String, Rule>>,
    private val nets: List<Pair<Cidr, Rule>>,
    /// Rules that could not be applied (bad value or a tunnel this profile
    /// does not have), with the reason — surfaced to the UI as errors.
    val rejected: List<Pair<Rule, String>>,
) {
    enum class Kind { APP, DOMAIN, WILDCARD, CIDR }

    data class Rule(
        val id: String,
        val kind: Kind,
        val value: String,
        val tunnel: String,
        val enabled: Boolean = true,
    )

    /// What the engine answers for one flow.
    sealed class Decision {
        /// Route through [tunnel] (index into [tunnels]; 0 = default).
        data class Route(val tunnel: Int, val ruleId: String?) : Decision()
        /// A matching rule names a tunnel that is not available: refuse the
        /// flow instead of silently sending it elsewhere (fail-closed).
        data class Refuse(val ruleId: String) : Decision()
    }

    val hasAppRules: Boolean get() = apps.isNotEmpty()
    val appPackages: Set<String> get() = apps.keys
    val activeCount: Int get() = apps.size + exact.size + wildcards.size + nets.size

    /// [ownerPackages] — the packages sharing the flow's owner uid (empty
    /// when the owner is unknown); [domain] — the fake-IP name (null for a
    /// real destination); [dst] — the destination address bytes (4 or 16).
    fun decide(ownerPackages: Collection<String>, domain: String?, dst: ByteArray?): Decision {
        for (pkg in ownerPackages) {
            apps[pkg]?.let { return resolve(it) }
        }
        if (domain != null) {
            val name = normalizeName(domain)
            if (name != null) {
                exact[name]?.let { return resolve(it) }
                for ((suffix, rule) in wildcards) {
                    if (name.length > suffix.length + 1 && name.endsWith(".$suffix")) return resolve(rule)
                }
            }
        } else if (dst != null) {
            for ((net, rule) in nets) {
                if (net.contains(dst)) return resolve(rule)
            }
        }
        return Decision.Route(0, null)
    }

    private fun resolve(rule: Rule): Decision {
        val i = tunnels.indexOf(rule.tunnel)
        return if (i < 0) Decision.Refuse(rule.id) else Decision.Route(i, rule.id)
    }

    data class Cidr(val bytes: ByteArray, val prefix: Int) {
        fun contains(addr: ByteArray): Boolean {
            if (addr.size != bytes.size) return false
            var bits = prefix
            var i = 0
            while (bits > 0) {
                val mask = if (bits >= 8) 0xFF else (0xFF shl (8 - bits)) and 0xFF
                if ((addr[i].toInt() and mask) != (bytes[i].toInt() and mask)) return false
                bits -= 8
                i++
            }
            return true
        }

        override fun equals(other: Any?): Boolean =
            other is Cidr && other.prefix == prefix && other.bytes.contentEquals(bytes)

        override fun hashCode(): Int = bytes.contentHashCode() * 31 + prefix
    }

    companion object {
        private val PACKAGE = Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+$")
        private val LABEL = Regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$")
        private val IPV4 = Regex("^(25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)(\\.(25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){3}$")
        private val IPV6_CHARS = Regex("^[0-9A-Fa-f:.]+$")

        /// Lower-case ASCII (IDNA/punycode) form of a host name, or null when
        /// it is not a valid name (labels 1..63, total ≤ 253, no wildcard).
        fun normalizeName(input: String): String? {
            var s = input.trim().trimEnd('.')
            if (s.isEmpty() || s.length > 253 * 4) return null
            s = try {
                IDN.toASCII(s, IDN.ALLOW_UNASSIGNED).lowercase()
            } catch (_: IllegalArgumentException) {
                return null
            }
            if (s.length > 253) return null
            val labels = s.split('.')
            if (labels.size < 2) return null
            if (labels.any { !LABEL.matches(it) }) return null
            return s
        }

        /// Parses `1.1.1.1`, `192.168.1.0/24`, `2606:4700::1111`, `2001:db8::/32`
        /// WITHOUT any DNS lookup (only numeric literals reach InetAddress).
        /// Host bits must be zero in a CIDR (`192.168.1.5/24` is refused).
        fun parseCidr(input: String): Cidr? {
            val text = input.trim()
            val slash = text.indexOf('/')
            val host = if (slash < 0) text else text.substring(0, slash)
            val bytes = parseAddress(host) ?: return null
            val max = bytes.size * 8
            val prefix = if (slash < 0) max else text.substring(slash + 1).toIntOrNull() ?: return null
            if (prefix < 0 || prefix > max) return null
            val net = Cidr(bytes, prefix)
            // zero host bits
            for (bit in prefix until max) {
                if ((bytes[bit / 8].toInt() shr (7 - bit % 8)) and 1 == 1) return null
            }
            return net
        }

        fun parseAddress(host: String): ByteArray? {
            if (IPV4.matches(host)) {
                return host.split('.').map { it.toInt().toByte() }.toByteArray()
            }
            if (host.contains(':') && IPV6_CHARS.matches(host)) {
                return try {
                    val a = InetAddress.getByName(host)
                    if (a is Inet6Address) a.address else a.address
                } catch (_: Exception) {
                    null
                }
            }
            return null
        }

        /// Canonical value of a rule (what is stored and matched), or null
        /// when the value is not valid for the kind.
        fun canonical(kind: Kind, value: String): String? = when (kind) {
            Kind.APP -> value.trim().takeIf { PACKAGE.matches(it) }
            Kind.DOMAIN -> normalizeName(value)
            Kind.WILDCARD -> {
                val v = value.trim()
                if (!v.startsWith("*.")) null else normalizeName(v.substring(2))?.let { "*.$it" }
            }
            Kind.CIDR -> parseCidr(value)?.let { c ->
                val host = InetAddress.getByAddress(c.bytes).hostAddress
                "$host/${c.prefix}"
            }
        }

        fun build(profile: String, tunnels: List<String>, rules: List<Rule>): HybridPolicy {
            val apps = LinkedHashMap<String, Rule>()
            val exact = LinkedHashMap<String, Rule>()
            val wild = ArrayList<Pair<String, Rule>>()
            val nets = ArrayList<Triple<Cidr, Rule, Int>>()
            val rejected = ArrayList<Pair<Rule, String>>()
            rules.forEachIndexed { order, r ->
                if (!r.enabled) return@forEachIndexed
                if (r.tunnel !in tunnels) {
                    // Kept as a REFUSING rule: its traffic is blocked, never
                    // re-routed, until the user fixes or removes it.
                    rejected += r to "tunnel-unavailable"
                }
                val v = canonical(r.kind, r.value)
                if (v == null) {
                    rejected += r to "invalid-value"
                    return@forEachIndexed
                }
                val dup = when (r.kind) {
                    Kind.APP -> apps.putIfAbsent(v, r)
                    Kind.DOMAIN -> exact.putIfAbsent(v, r)
                    Kind.WILDCARD -> {
                        val s = v.removePrefix("*.")
                        if (wild.any { it.first == s }) r else { wild += s to r; null }
                    }
                    Kind.CIDR -> {
                        val c = parseCidr(v)!!
                        if (nets.any { it.first == c }) r else { nets += Triple(c, r, order); null }
                    }
                }
                if (dup != null) rejected += r to "duplicate"
            }
            wild.sortByDescending { it.first.length }
            nets.sortWith(compareByDescending<Triple<Cidr, Rule, Int>> { it.first.prefix }.thenBy { it.third })
            return HybridPolicy(
                profile, tunnels, apps, exact, wild,
                nets.map { it.first to it.second }, rejected,
            )
        }
    }
}
