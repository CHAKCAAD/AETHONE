package com.chakcaad.aethone.shield

import com.chakcaad.aethone.shield.ShieldCategory.ADULT
import com.chakcaad.aethone.shield.ShieldCategory.BYPASS
import com.chakcaad.aethone.shield.ShieldCategory.CHAT
import com.chakcaad.aethone.shield.ShieldCategory.DATING
import com.chakcaad.aethone.shield.ShieldCategory.DRUGS
import com.chakcaad.aethone.shield.ShieldCategory.GAMBLING
import com.chakcaad.aethone.shield.ShieldCategory.KIDS_SAFE
import com.chakcaad.aethone.shield.ShieldCategory.PIRACY
import com.chakcaad.aethone.shield.ShieldCategory.SOCIAL
import com.chakcaad.aethone.shield.ShieldCategory.VIOLENCE
import com.chakcaad.aethone.shield.ShieldCategory.WEAPONS

/// Family Shield — age presets (product presets, not an official rating) and
/// the profile manager (pure JVM).
///
///  * Toddler 3–7   — allowlist-only: unknown domains are blocked; only
///                    parent-allowed (and kids-safe-listed) destinations pass.
///  * Child 8–12    — broad category blocking, unknown domains allowed.
///  * Teen 13–15    — adult, gambling, dating, violence, drugs, weapons,
///                    bypass tools, piracy.
///  * Older teen 16–17 — adult, gambling, drugs, weapons, bypass tools.
///  * Custom        — starts from the Child set; everything editable.
///
/// Every category stays visible and editable in every preset; mandatory
/// security (malware, phishing) is always on and is not part of a preset.
object AgePresets {
    fun categories(p: AgePreset): Set<ShieldCategory> = when (p) {
        AgePreset.TODDLER -> ShieldCategory.blocking.filter { !it.mandatory }.toSet()
        AgePreset.CHILD, AgePreset.CUSTOM ->
            setOf(ADULT, GAMBLING, DATING, SOCIAL, CHAT, VIOLENCE, DRUGS, WEAPONS, BYPASS, PIRACY)
        AgePreset.TEEN -> setOf(ADULT, GAMBLING, DATING, VIOLENCE, DRUGS, WEAPONS, BYPASS, PIRACY)
        AgePreset.OLDER_TEEN -> setOf(ADULT, GAMBLING, DRUGS, WEAPONS, BYPASS)
    }

    fun unknownPolicy(p: AgePreset): UnknownPolicy =
        if (p == AgePreset.TODDLER) UnknownPolicy.BLOCK else UnknownPolicy.ALLOW

    fun allowCategories(p: AgePreset): Set<ShieldCategory> =
        if (p == AgePreset.TODDLER) setOf(KIDS_SAFE) else emptySet()

    fun build(id: String, name: String, p: AgePreset, now: Long): AgeProfile = AgeProfile(
        id = id,
        name = name,
        preset = p,
        categories = categories(p),
        unknownPolicy = unknownPolicy(p),
        strict = StrictOptions(),
        allowCategories = allowCategories(p),
        updatedAt = now,
    )
}

/// Profile lifecycle over a [ShieldRepository]: every profile keeps its own
/// categories, rules and app restrictions; switching the active profile
/// never touches another profile's data, and every switch is recorded.
class ProfileManager(
    private val repo: ShieldRepository,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    fun create(name: String, preset: AgePreset): AgeProfile {
        val id = "p" + java.util.UUID.randomUUID().toString().replace("-", "").take(12)
        val p = AgePresets.build(id, name.trim().ifEmpty { preset.key }, preset, clock())
        repo.upsertProfile(p)
        bump("profile-created")
        return p
    }

    fun active(): AgeProfile? = repo.config().activeProfileId?.let { repo.profile(it) }

    /// Switches the active profile; the previous profile's data stays as it is.
    fun switchTo(id: String, reason: String = "switch"): AgeProfile {
        val target = repo.profile(id) ?: throw IllegalArgumentException("no profile $id")
        val cfg = repo.config()
        if (cfg.activeProfileId == id) return target
        repo.appendHistory(ProfileChange(clock(), cfg.activeProfileId, id, reason))
        repo.saveConfig(cfg.copy(activeProfileId = id, generation = cfg.generation + 1, updatedAt = clock()))
        return target
    }

    fun setCategory(profileId: String, c: ShieldCategory, on: Boolean): AgeProfile {
        val p = repo.profile(profileId) ?: throw IllegalArgumentException("no profile $profileId")
        require(!c.mandatory) { "mandatory security categories can not be changed" }
        val next = if (c.allowList) {
            p.copy(allowCategories = if (on) p.allowCategories + c else p.allowCategories - c)
        } else {
            p.copy(categories = if (on) p.categories + c else p.categories - c)
        }.copy(updatedAt = clock())
        repo.upsertProfile(next)
        bump("categories")
        return next
    }

    fun setUnknownPolicy(profileId: String, policy: UnknownPolicy): AgeProfile {
        val p = repo.profile(profileId) ?: throw IllegalArgumentException("no profile $profileId")
        val next = p.copy(unknownPolicy = policy, updatedAt = clock())
        repo.upsertProfile(next)
        bump("unknown-policy")
        return next
    }

    fun setStrict(profileId: String, strict: StrictOptions): AgeProfile {
        val p = repo.profile(profileId) ?: throw IllegalArgumentException("no profile $profileId")
        val next = p.copy(strict = strict, updatedAt = clock())
        repo.upsertProfile(next)
        bump("strict")
        return next
    }

    /// Re-applies a preset's defaults to a profile (its rules and app
    /// restrictions are kept).
    fun resetToPreset(profileId: String, preset: AgePreset): AgeProfile {
        val p = repo.profile(profileId) ?: throw IllegalArgumentException("no profile $profileId")
        val base = AgePresets.build(p.id, p.name, preset, clock())
        repo.upsertProfile(base.copy(strict = p.strict))
        bump("preset")
        return repo.profile(profileId)!!
    }

    fun addRule(profileId: String, kind: RuleKind, raw: String, action: RuleAction, note: String? = null): ParentRule {
        require(repo.profile(profileId) != null) { "no profile $profileId" }
        val value = when (kind) {
            RuleKind.CIDR -> Cidr.parse(raw)?.toString() ?: throw IllegalArgumentException("invalid address or CIDR")
            RuleKind.WILDCARD -> DomainNames.normalize(raw.trim().removePrefix("*."))
                ?: throw IllegalArgumentException("invalid domain")
            else -> DomainNames.normalize(raw) ?: throw IllegalArgumentException("invalid domain")
        }
        val r = ParentRule(
            id = "r" + java.util.UUID.randomUUID().toString().replace("-", "").take(12),
            profileId = profileId, kind = kind, value = value, action = action, note = note, createdAt = clock(),
        )
        repo.addRule(r)
        bump("rules")
        return r
    }

    fun removeRule(id: String) {
        repo.removeRule(id)
        bump("rules")
    }

    fun restrictApp(profileId: String, pkg: String, on: Boolean) {
        require(repo.profile(profileId) != null) { "no profile $profileId" }
        require(pkg.isNotBlank() && pkg.length <= 255) { "invalid package" }
        if (on) repo.addAppRestriction(AppRestriction(profileId, pkg, clock()))
        else repo.removeAppRestriction(profileId, pkg)
        bump("apps")
    }

    fun delete(profileId: String) {
        require(repo.config().activeProfileId != profileId) { "switch away from the active profile first" }
        repo.deleteProfile(profileId)
        bump("profile-deleted")
    }

    private fun bump(reason: String) {
        val c = repo.config()
        repo.saveConfig(c.copy(generation = c.generation + 1, updatedAt = clock()))
    }
}
