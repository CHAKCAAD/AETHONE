package com.chakcaad.aethone.shield

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/// Family Shield — binary snapshot generation and validation (format v1,
/// shared with the native matcher; the golden digest below is also checked
/// by the zeptun patch test "shield: Kotlin golden snapshot").
class ShieldSnapshotTest {
    private fun golden(): ByteArray {
        val spec = ShieldSnapshot.Spec(
            flags = ShieldSnapshot.FLAG_UNKNOWN_BLOCK,
            generation = 42,
            enabledCats = ShieldCategory.ADULT.mask or ShieldCategory.mandatoryMask,
            mandatoryCats = ShieldCategory.mandatoryMask,
            allowCats = ShieldCategory.KIDS_SAFE.mask,
            profile = AgePreset.TODDLER.ordinal,
        )
        spec.entry("adult.example").apply { selfCats = ShieldCategory.ADULT.mask; subCats = ShieldCategory.ADULT.mask }
        spec.entry("school.example").apply { selfFlags = ShieldSnapshot.RULE_PARENT_ALLOW; subFlags = ShieldSnapshot.RULE_PARENT_ALLOW }
        spec.entry("evil.example").apply { selfCats = ShieldCategory.MALWARE.mask; subCats = ShieldCategory.MALWARE.mask }
        spec.addCidr(Cidr.parse("10.0.0.0/8")!!, ShieldSnapshot.RULE_PARENT_BLOCK, 0)
        spec.addCidr(Cidr.parse("2001:db8::/32")!!, ShieldSnapshot.RULE_PARENT_BLOCK, 0)
        return ShieldSnapshot.build(spec)
    }

    @Test fun goldenSnapshotIsDeterministicAndMatchesTheNativeFixture() {
        val a = golden()
        assertArrayEquals(a, golden())
        assertEquals(GOLDEN_SHA256, ContentSources.sha256Hex(a))
        assertEquals(GOLDEN_LEN, a.size)
    }

    @Test fun roundTripVerdicts() {
        val r = ShieldSnapshot.Reader.parse(golden())
        assertEquals(42, r.generation)
        assertEquals(3, r.domainCount)
        assertTrue(r.checkName("www.adult.example").block)
        assertFalse(r.checkName("a.school.example").block)
        assertEquals(ShieldSnapshot.Level.UNKNOWN, r.checkName("random.test").level)
        assertEquals(ShieldSnapshot.Level.MANDATORY, r.checkName("evil.example").level)
        assertTrue(r.checkFlow(null, byteArrayOf(10, 1, 2, 3), false, 6, 80).block)
    }

    private fun expectInvalid(b: ByteArray) {
        try {
            ShieldSnapshot.Reader.parse(b)
            fail("accepted an invalid snapshot")
        } catch (_: ShieldSnapshot.InvalidSnapshot) {
        }
    }

    @Test fun invalidSnapshotsAreRejected() {
        val g = golden()
        expectInvalid(g.copyOf(64))
        expectInvalid(g.copyOf(g.size - 1))
        expectInvalid(g.copyOf().also { it[it.size - 1] = (it[it.size - 1].toInt() xor 1).toByte() }) // checksum
        expectInvalid(g.copyOf().also { it[0] = 'X'.code.toByte(); ShieldSnapshot.seal(it) }) // magic
        expectInvalid(g.copyOf().also { it[8] = 2; ShieldSnapshot.seal(it) }) // version
        expectInvalid(g.copyOf().also { it[12] = 0x40; ShieldSnapshot.seal(it) }) // unknown flags
        expectInvalid(g.copyOf().also { it[130] = (it[130].toInt() xor 0x55).toByte(); ShieldSnapshot.seal(it) }) // entry hash
        expectInvalid(g.copyOf().also { it[80] = 1; ShieldSnapshot.seal(it) }) // reserved
    }

    @Test fun compilerOutputAlwaysValidatesAndDropsIrrelevantBits() {
        val db = ShieldCompiler.CategoryDatabase(
            domains = mapOf("games.example" to ShieldCategory.GAMES.mask, "x.example" to ShieldCategory.ADULT.mask),
        )
        val older = AgePresets.build("p", "p", AgePreset.OLDER_TEEN, 0)
        val res = ShieldCompiler.compile(older, emptyList(), db, 9)
        // games is not enabled for 16–17: the entry is dropped entirely
        assertEquals(1, res.domains)
        val r = ShieldSnapshot.Reader.parse(res.bytes)
        assertEquals(9, r.generation)
        assertFalse(r.checkName("games.example").block)
    }

    @Test fun strictFlagsAndPrivateDnsSuppression() {
        val p = AgePresets.build("p", "p", AgePreset.TEEN, 0).copy(strict = StrictOptions(enabled = true))
        val f = ShieldCompiler.headerFlags(p)
        assertTrue(f and ShieldSnapshot.FLAG_STRICT_DOT != 0)
        assertTrue(f and ShieldSnapshot.FLAG_STRICT_QUIC != 0)
        assertFalse(f and ShieldSnapshot.FLAG_STRICT_DIRECT_IP != 0)
        val r = ShieldSnapshot.Reader.parse(ShieldCompiler.compile(p, emptyList(), ShieldCompiler.CategoryDatabase(), 1, suppressDot = true).bytes)
        assertFalse(r.checkFlow("dns.example", byteArrayOf(198.toByte(), 18, 0, 1), true, 6, 853).block)
        assertTrue(r.checkFlow("x.example", byteArrayOf(198.toByte(), 18, 0, 1), true, 17, 443).block)
        // strict off by default
        assertEquals(0, ShieldCompiler.headerFlags(AgePresets.build("q", "q", AgePreset.TEEN, 0)))
    }

    companion object {
        // Filled from the first run of the builder; the same bytes are
        // embedded (hex) in the zeptun patch test.
        const val GOLDEN_SHA256 = "e339ca8cd8b7ad32e0e137094e05be2ae39f2511613e2b6525c2c5cab79ba68b"
        const val GOLDEN_LEN = 375
    }
}
