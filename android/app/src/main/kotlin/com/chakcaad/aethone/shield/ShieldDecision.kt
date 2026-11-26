package com.chakcaad.aethone.shield

import com.chakcaad.aethone.shield.ShieldSnapshot.Level
import com.chakcaad.aethone.shield.ShieldSnapshot.Verdict

/// Family Shield — the per-flow decision of the app layer (pure JVM).
///
/// zeptun has already matched the flow's fake-IP name / real address against
/// the snapshot and hands over its verdict (levels 1, 2, 4, 5, 6, strict).
/// This adds level 3 — app restrictions — which needs the flow's owner uid
/// (the ONE getConnectionOwnerUid lookup HybridRouter.route makes per flow)
/// and applies the owner's priority:
///   1 mandatory security > 2 parent blocklist > 3 app restriction >
///   4 categories > 5 parent allowlist > 6 unknown-domain policy.
/// The allowlist never overrides 1–3; it is already folded into the native
/// verdict for 4 and 6.
object ShieldDecision {
    const val INVALID_UID = -1

    sealed class Decision {
        data class Allow(val level: Int) : Decision()
        data class Block(val level: Int, val category: ShieldCategory?, val reason: String) : Decision()
    }

    /// [restrictedAppIds]: appIds (uid % 100000) of the active profile's
    /// restricted packages. [uid] null / negative = unattributed (Android < 10,
    /// socket gone, lookup error): app restrictions can not match, the
    /// destination verdict still applies.
    fun decide(native: Verdict, uid: Int?, restrictedAppIds: Set<Int>): Decision {
        // Kotlin believes the shield is on but the engine holds no snapshot:
        // fail closed rather than let the flow through unfiltered.
        if (!native.active) return Decision.Block(Level.NONE, null, "no-snapshot")
        if (native.block && (native.level == Level.MANDATORY || native.level == Level.PARENT_BLOCK)) {
            return Decision.Block(native.level, native.categoryOrNull, levelName(native.level))
        }
        if (uid != null && uid >= 0 && (uid % 100_000) in restrictedAppIds) {
            return Decision.Block(Level.APP, null, "app")
        }
        if (native.block) return Decision.Block(native.level, native.categoryOrNull, levelName(native.level))
        return Decision.Allow(native.level)
    }

    fun levelName(level: Int): String = when (level) {
        Level.MANDATORY -> "mandatory"
        Level.PARENT_BLOCK -> "blocklist"
        Level.APP -> "app"
        Level.CATEGORY -> "category"
        Level.PARENT_ALLOW -> "allowlist"
        Level.UNKNOWN -> "unknown"
        Level.STRICT -> "strict"
        else -> "none"
    }
}

/// How HybridRouter.route combines the shield with hybrid routing and
/// Traffic Analytics (pure, so the ordering is unit tested):
///  * the shield is evaluated FIRST — a blocked flow is rejected before the
///    hybrid policy and before any SOCKS dial;
///  * a blocked flow is never handed to the traffic meter, so blocked
///    traffic is not booked as tunnel traffic;
///  * the owner uid is looked up at most once and shared by all three.
object RouteGate {
    const val ROUTE_DEFAULT = 0
    const val ROUTE_REJECT = 3

    data class Outcome(val answer: Int, val observe: Boolean, val shieldBlocked: Boolean)

    fun needsUid(shieldNeedsUid: Boolean, hybridAppRules: Boolean, metering: Boolean): Boolean =
        shieldNeedsUid || hybridAppRules || metering

    /// [hybrid] is the hybrid policy's answer, computed only when the shield
    /// let the flow through (lazily, so a blocked flow costs nothing more).
    fun combine(shield: ShieldDecision.Decision?, metering: Boolean, hybrid: () -> Int): Outcome {
        if (shield is ShieldDecision.Decision.Block) return Outcome(ROUTE_REJECT, observe = false, shieldBlocked = true)
        val a = hybrid()
        return Outcome(a, observe = metering && a != ROUTE_REJECT, shieldBlocked = false)
    }
}
