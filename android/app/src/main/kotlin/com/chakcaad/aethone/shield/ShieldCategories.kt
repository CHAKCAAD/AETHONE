package com.chakcaad.aethone.shield

/// Family Shield — content categories (pure JVM).
///
/// Each category is one bit of the native snapshot's 64-bit category mask
/// (flow/shield.zig: enabled_cats / mandatory_cats / allow_cats). The bit
/// index is part of the on-disk format: never renumber a category, only
/// append new ones.
///
/// [mandatory] categories are the owner's level 1 ("Mandatory security"):
/// while Family Shield is on they are always blocked, no profile can turn
/// them off and no parent allowlist entry overrides them.
///
/// [allowList] categories are positive lists (e.g. UT1 "child" — sites
/// reviewed as suitable for young children). They never block; in an
/// allowlist-only profile they count as "allowed" like a parent allowlist
/// entry (level 5) and they never override levels 1–4.
enum class ShieldCategory(
    val bit: Int,
    val key: String,
    val mandatory: Boolean = false,
    val allowList: Boolean = false,
) {
    MALWARE(0, "malware", mandatory = true),
    PHISHING(1, "phishing", mandatory = true),
    ADULT(2, "adult"),
    GAMBLING(3, "gambling"),
    DATING(4, "dating"),
    SOCIAL(5, "social"),
    GAMES(6, "games"),
    CHAT(7, "chat"),
    VIOLENCE(8, "violence"),
    DRUGS(9, "drugs"),
    WEAPONS(10, "weapons"),
    /// VPN / proxy / Tor / DoH-resolver names and IPs — the usual bypass tools.
    BYPASS(11, "bypass"),
    PIRACY(12, "piracy"),
    /// Positive list: reviewed as suitable for young children.
    KIDS_SAFE(13, "kids_safe", allowList = true),
    ;

    val mask: Long get() = 1L shl bit

    companion object {
        fun byKey(key: String): ShieldCategory? = entries.firstOrNull { it.key == key }
        fun byBit(bit: Int): ShieldCategory? = entries.firstOrNull { it.bit == bit }

        /// Every category that can block (all except positive lists).
        val blocking: List<ShieldCategory> get() = entries.filter { !it.allowList }

        val mandatoryMask: Long get() = entries.filter { it.mandatory }.fold(0L) { m, c -> m or c.mask }

        fun maskOf(cats: Collection<ShieldCategory>): Long = cats.fold(0L) { m, c -> m or c.mask }

        fun fromMask(mask: Long): Set<ShieldCategory> = entries.filter { mask and it.mask != 0L }.toSet()

        init {
            // the bit numbers are part of the snapshot format
            require(entries.map { it.bit }.toSet().size == entries.size) { "duplicate category bit" }
            require(entries.all { it.bit in 0..63 })
        }
    }
}
