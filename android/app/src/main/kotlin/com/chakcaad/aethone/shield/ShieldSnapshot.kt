package com.chakcaad.aethone.shield

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest

/// Family Shield — the binary read-only policy snapshot (format v1), built
/// here and consumed by the native matcher (zeptun patch, flow/shield.zig —
/// the authoritative description of the layout is at the top of that file).
///
/// Lifecycle: compile (ShieldCompiler) → build → [ShieldSnapshot.parse] here
/// (full validation, the same checks as native) → native validates again
/// (zeptun_shield_validate) → atomic swap. An invalid snapshot is refused at
/// every step and the previous one stays active. Nothing per packet touches
/// SQLite: the engine only reads this immutable blob.
object ShieldSnapshot {
    const val MAGIC = "AETHSHLD"
    const val VERSION = 1
    const val HEADER_LEN = 128
    const val ENTRY_LEN = 40
    const val V4_LEN = 24
    const val V6_LEN = 32

    const val FLAG_UNKNOWN_BLOCK = 1 shl 0
    const val FLAG_STRICT_DOT = 1 shl 1
    const val FLAG_STRICT_QUIC = 1 shl 2
    const val FLAG_STRICT_DIRECT_IP = 1 shl 3
    const val FLAG_STRICT_ALT_DNS = 1 shl 4
    private const val KNOWN_FLAGS = 0x1f

    const val RULE_PARENT_BLOCK = 1 shl 0
    const val RULE_PARENT_ALLOW = 1 shl 1
    private const val KNOWN_RULE_FLAGS = 0x3

    fun fnv1a64(s: ByteArray): Long {
        var h = -0x340d631b7bdddcdbL // 0xcbf29ce484222325
        for (b in s) {
            h = h xor (b.toLong() and 0xff)
            h *= 0x100000001b3L
        }
        return h
    }

    class Entry {
        var selfFlags = 0
        var subFlags = 0
        var selfCats = 0L
        var subCats = 0L
    }

    data class CidrRule(val cidr: Cidr, val flags: Int, val cats: Long)

    /// Everything a snapshot holds, before serialization.
    class Spec(
        val flags: Int,
        val generation: Int,
        val enabledCats: Long,
        val mandatoryCats: Long,
        val allowCats: Long,
        val profile: Int,
    ) {
        val domains = java.util.TreeMap<String, Entry>()
        private val cidrs = HashMap<Cidr, IntArrayLong>()

        class IntArrayLong(var flags: Int, var cats: Long)

        fun entry(name: String): Entry {
            require(DomainNames.valid(name)) { "not a normalized name: $name" }
            return domains.getOrPut(name) { Entry() }
        }

        fun addCidr(c: Cidr, flags: Int, cats: Long) {
            val cur = cidrs.getOrPut(c) { IntArrayLong(0, 0L) }
            cur.flags = cur.flags or flags
            cur.cats = cur.cats or cats
        }

        fun cidrRules(v6: Boolean): List<CidrRule> = cidrs.entries
            .filter { it.key.v6 == v6 }
            .map { CidrRule(it.key, it.value.flags, it.value.cats) }
            .sortedWith { a, b ->
                if (a.cidr.prefix != b.cidr.prefix) a.cidr.prefix - b.cidr.prefix
                else compareUnsigned(a.cidr.address, b.cidr.address)
            }
    }

    fun compareUnsigned(a: ByteArray, b: ByteArray): Int {
        for (i in a.indices) {
            val d = (a[i].toInt() and 0xff) - (b[i].toInt() and 0xff)
            if (d != 0) return d
        }
        return 0
    }

    fun build(spec: Spec): ByteArray {
        val names = spec.domains.keys.toList() // sorted: deterministic bytes
        var buckets = 1
        while (buckets < names.size * 2 + 1) buckets *= 2
        val strings = java.io.ByteArrayOutputStream()
        val offs = IntArray(names.size)
        val nameBytes = names.map { it.toByteArray(Charsets.US_ASCII) }
        for ((i, nb) in nameBytes.withIndex()) {
            offs[i] = strings.size()
            strings.write(nb)
        }
        val v4 = spec.cidrRules(false)
        val v6 = spec.cidrRules(true)
        val sb = strings.toByteArray()
        val total = HEADER_LEN.toLong() + names.size.toLong() * ENTRY_LEN + buckets.toLong() * 4 +
            v4.size.toLong() * V4_LEN + v6.size.toLong() * V6_LEN + sb.size
        require(total <= Int.MAX_VALUE) { "snapshot too large" }
        val buf = ByteBuffer.allocate(total.toInt()).order(ByteOrder.LITTLE_ENDIAN)
        buf.put(MAGIC.toByteArray(Charsets.US_ASCII))
        buf.putShort(VERSION.toShort())
        buf.putShort(HEADER_LEN.toShort())
        buf.putInt(spec.flags)
        buf.putInt(total.toInt())
        buf.putInt(spec.generation)
        buf.putLong(spec.enabledCats)
        buf.putLong(spec.mandatoryCats)
        buf.putLong(spec.allowCats)
        buf.putInt(names.size)
        buf.putInt(buckets)
        buf.putInt(v4.size)
        buf.putInt(v6.size)
        buf.putInt(sb.size)
        buf.putInt(spec.profile)
        // 72..128: reserved + checksum (zero for now)
        buf.position(HEADER_LEN)
        val bucketArr = IntArray(buckets)
        for ((i, name) in names.withIndex()) {
            val e = spec.domains[name]!!
            val h = fnv1a64(nameBytes[i])
            buf.putLong(h)
            buf.putInt(offs[i])
            buf.putShort(nameBytes[i].size.toShort())
            buf.putShort(0)
            buf.putInt(e.selfFlags)
            buf.putInt(e.subFlags)
            buf.putLong(e.selfCats)
            buf.putLong(e.subCats)
            var slot = (h and (buckets - 1).toLong()).toInt()
            while (bucketArr[slot] != 0) slot = (slot + 1) and (buckets - 1)
            bucketArr[slot] = i + 1
        }
        for (v in bucketArr) buf.putInt(v)
        for (r in v4) {
            buf.put(r.cidr.address)
            buf.put(r.cidr.prefix.toByte())
            buf.put(ByteArray(3))
            buf.putInt(r.flags)
            buf.putInt(0)
            buf.putLong(r.cats)
        }
        for (r in v6) {
            buf.put(r.cidr.address)
            buf.put(r.cidr.prefix.toByte())
            buf.put(ByteArray(3))
            buf.putInt(r.flags)
            buf.putLong(r.cats)
        }
        buf.put(sb)
        val out = buf.array()
        seal(out)
        return out
    }

    fun seal(b: ByteArray) {
        java.util.Arrays.fill(b, 96, 128, 0)
        val d = MessageDigest.getInstance("SHA-256").digest(b)
        System.arraycopy(d, 0, b, 96, 32)
    }

    class InvalidSnapshot(msg: String) : Exception(msg)

    /// Level codes shared with native (flow/shield.zig Level).
    object Level {
        const val NONE = 0
        const val MANDATORY = 1
        const val PARENT_BLOCK = 2
        const val APP = 3
        const val CATEGORY = 4
        const val PARENT_ALLOW = 5
        const val UNKNOWN = 6
        const val STRICT = 7
    }

    /// The native verdict (Verdict.encode in flow/shield.zig).
    data class Verdict(val active: Boolean, val block: Boolean, val level: Int, val category: Int) {
        fun encode(): Int = (if (active) Int.MIN_VALUE else 0) or (if (block) 1 else 0) or
            (level shl 8) or (category shl 16)

        val categoryOrNull: ShieldCategory? get() = if (category == 0) null else ShieldCategory.byBit(category - 1)

        companion object {
            val INACTIVE = Verdict(false, false, 0, 0)
            fun decode(v: Int): Verdict = Verdict(
                active = v and Int.MIN_VALUE != 0,
                block = v and 0xff == 1,
                level = (v ushr 8) and 0xff,
                category = (v ushr 16) and 0xff,
            )
        }
    }

    /// A parsed, fully validated snapshot with the same matching semantics as
    /// native — used to validate what we built before handing it over, and by
    /// the JVM tests.
    class Reader private constructor(private val b: ByteArray) {
        private val bb = ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN)
        val flags = bb.getInt(12)
        val generation = bb.getInt(20)
        val enabled = bb.getLong(24)
        val mandatory = bb.getLong(32)
        val allowCats = bb.getLong(40)
        val domainCount = bb.getInt(48)
        private val buckets = bb.getInt(52)
        private val v4n = bb.getInt(56)
        private val v6n = bb.getInt(60)
        private val stringsLen = bb.getInt(64)
        private val entriesOff = HEADER_LEN
        private val bucketsOff = entriesOff + domainCount * ENTRY_LEN
        private val v4Off = bucketsOff + buckets * 4
        private val v6Off = v4Off + v4n * V4_LEN
        private val stringsOff = v6Off + v6n * V6_LEN

        private fun nameAt(i: Int): String {
            val e = entriesOff + i * ENTRY_LEN
            val off = bb.getInt(e + 8)
            val len = bb.getShort(e + 12).toInt() and 0xffff
            return String(b, stringsOff + off, len, Charsets.US_ASCII)
        }

        fun find(name: String): Int? {
            if (domainCount == 0) return null
            val nb = name.toByteArray(Charsets.US_ASCII)
            val h = fnv1a64(nb)
            var slot = (h and (buckets - 1).toLong()).toInt()
            repeat(buckets) {
                val v = bb.getInt(bucketsOff + slot * 4)
                if (v == 0) return null
                val i = v - 1
                if (i >= domainCount) return null
                if (bb.getLong(entriesOff + i * ENTRY_LEN) == h && nameAt(i) == name) return i
                slot = (slot + 1) and (buckets - 1)
            }
            return null
        }

        private class Acc { var flags = 0; var cats = 0L }

        private fun matchName(name: String, acc: Acc) {
            find(name)?.let { i ->
                val e = entriesOff + i * ENTRY_LEN
                acc.flags = acc.flags or bb.getInt(e + 16)
                acc.cats = acc.cats or bb.getLong(e + 24)
            }
            for (s in DomainNames.suffixes(name).drop(1)) {
                find(s)?.let { i ->
                    val e = entriesOff + i * ENTRY_LEN
                    acc.flags = acc.flags or bb.getInt(e + 20)
                    acc.cats = acc.cats or bb.getLong(e + 32)
                }
            }
        }

        private fun matchAddr(a: ByteArray, acc: Acc) {
            val v6 = a.size == 16
            val n = if (v6) v6n else v4n
            val rl = if (v6) V6_LEN else V4_LEN
            val base = if (v6) v6Off else v4Off
            for (i in 0 until n) {
                val r = base + i * rl
                val net = b.copyOfRange(r, r + a.size)
                val prefix = b[r + a.size].toInt() and 0xff
                if (Cidr(net, prefix).contains(a)) {
                    acc.flags = acc.flags or bb.getInt(r + a.size + 4)
                    acc.cats = acc.cats or bb.getLong(r + if (v6) 24 else 16)
                }
            }
        }

        private fun firstBit(v: Long) = java.lang.Long.numberOfTrailingZeros(v) + 1

        private fun judge(acc: Acc): Verdict {
            val m = acc.cats and mandatory
            if (m != 0L) return Verdict(true, true, Level.MANDATORY, firstBit(m))
            if (acc.flags and RULE_PARENT_BLOCK != 0) return Verdict(true, true, Level.PARENT_BLOCK, 0)
            val allowed = acc.flags and RULE_PARENT_ALLOW != 0
            val c = acc.cats and enabled and mandatory.inv()
            if (c != 0L && !allowed) return Verdict(true, true, Level.CATEGORY, firstBit(c))
            if (allowed) return Verdict(true, false, Level.PARENT_ALLOW, 0)
            val ac = acc.cats and allowCats
            if (ac != 0L) return Verdict(true, false, Level.PARENT_ALLOW, firstBit(ac))
            if (flags and FLAG_UNKNOWN_BLOCK != 0) return Verdict(true, true, Level.UNKNOWN, 0)
            return Verdict(true, false, Level.NONE, 0)
        }

        fun checkName(name: String): Verdict {
            val acc = Acc()
            matchName(name, acc)
            return judge(acc)
        }

        fun checkFlow(name: String?, dst: ByteArray, fake: Boolean, proto: Int, dport: Int): Verdict {
            val acc = Acc()
            if (name != null) matchName(name, acc)
            if (!fake) matchAddr(dst, acc)
            val m = acc.cats and mandatory
            if (m != 0L) return Verdict(true, true, Level.MANDATORY, firstBit(m))
            if (acc.flags and RULE_PARENT_BLOCK != 0) return Verdict(true, true, Level.PARENT_BLOCK, 0)
            val f = flags
            val strict = (f and FLAG_STRICT_DOT != 0 && dport == 853) ||
                (f and FLAG_STRICT_QUIC != 0 && proto == 17 && dport == 443) ||
                (f and FLAG_STRICT_ALT_DNS != 0 && dport == 53 && !fake) ||
                (f and FLAG_STRICT_DIRECT_IP != 0 && name == null && !fake)
            if (strict) return Verdict(true, true, Level.STRICT, 0)
            return judge(acc)
        }

        companion object {
            /// Full validation (the same checks as native); throws
            /// [InvalidSnapshot] for anything off.
            fun parse(b: ByteArray): Reader {
                fun bad(m: String): Nothing = throw InvalidSnapshot(m)
                if (b.size < HEADER_LEN) bad("too short")
                if (String(b, 0, 8, Charsets.US_ASCII) != MAGIC) bad("bad magic")
                val bb = ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN)
                if (bb.getShort(8).toInt() != VERSION) bad("bad version")
                if (bb.getShort(10).toInt() != HEADER_LEN) bad("bad header length")
                val flags = bb.getInt(12)
                if (flags and KNOWN_FLAGS.inv() != 0) bad("unknown flags")
                for (i in 72 until 96) if (b[i].toInt() != 0) bad("reserved bytes")
                if (bb.getInt(16) != b.size) bad("length mismatch")
                val dc = bb.getInt(48).toLong() and 0xffffffffL
                val bc = bb.getInt(52).toLong() and 0xffffffffL
                val v4 = bb.getInt(56).toLong() and 0xffffffffL
                val v6 = bb.getInt(60).toLong() and 0xffffffffL
                val sl = bb.getInt(64).toLong() and 0xffffffffL
                if (bc == 0L || bc and (bc - 1) != 0L || dc >= bc) bad("bad bucket count")
                val total = HEADER_LEN + dc * ENTRY_LEN + bc * 4 + v4 * V4_LEN + v6 * V6_LEN + sl
                if (total != b.size.toLong()) bad("layout mismatch")
                val copy = b.copyOf()
                java.util.Arrays.fill(copy, 96, 128, 0)
                val d = MessageDigest.getInstance("SHA-256").digest(copy)
                if (!d.contentEquals(b.copyOfRange(96, 128))) bad("checksum mismatch")
                val r = Reader(b)
                r.validateBody()
                return r
            }
        }

        private fun validateBody() {
            fun bad(m: String): Nothing = throw InvalidSnapshot(m)
            for (i in 0 until domainCount) {
                val e = entriesOff + i * ENTRY_LEN
                val off = bb.getInt(e + 8).toLong() and 0xffffffffL
                val len = bb.getShort(e + 12).toInt() and 0xffff
                if (bb.getShort(e + 14).toInt() != 0) bad("entry reserved")
                if (off + len > stringsLen) bad("entry string out of range")
                val name = String(b, stringsOff + off.toInt(), len, Charsets.US_ASCII)
                if (!DomainNames.valid(name)) bad("entry name invalid")
                if (bb.getLong(e) != fnv1a64(name.toByteArray(Charsets.US_ASCII))) bad("entry hash")
                if ((bb.getInt(e + 16) or bb.getInt(e + 20)) and KNOWN_RULE_FLAGS.inv() != 0) bad("entry flags")
                if (find(name) != i) bad("entry unreachable or duplicate")
            }
            var used = 0
            for (k in 0 until buckets) {
                val v = bb.getInt(bucketsOff + k * 4)
                if (v == 0) continue
                if (v < 0 || v > domainCount) bad("bucket out of range")
                used++
            }
            if (used != domainCount) bad("bucket count mismatch")
            for (v6 in listOf(false, true)) {
                val n = if (v6) v6n else v4n
                val rl = if (v6) V6_LEN else V4_LEN
                val al = if (v6) 16 else 4
                val base = if (v6) v6Off else v4Off
                var prev: ByteArray? = null
                var prevPrefix = 0
                for (i in 0 until n) {
                    val r = base + i * rl
                    val a = b.copyOfRange(r, r + al)
                    val prefix = b[r + al].toInt() and 0xff
                    if (prefix > al * 8) bad("cidr prefix")
                    for (z in r + al + 1 until r + al + 4) if (b[z].toInt() != 0) bad("cidr padding")
                    if (bb.getInt(r + al + 4) and KNOWN_RULE_FLAGS.inv() != 0) bad("cidr flags")
                    if (!v6 && bb.getInt(r + 12) != 0) bad("cidr padding")
                    for (bit in prefix until al * 8) {
                        if ((a[bit / 8].toInt() shr (7 - bit % 8)) and 1 != 0) bad("cidr host bits")
                    }
                    val p = prev
                    if (p != null) {
                        if (prefix < prevPrefix) bad("cidr order")
                        if (prefix == prevPrefix && compareUnsigned(p, a) >= 0) bad("cidr order")
                    }
                    prev = a
                    prevPrefix = prefix
                }
            }
        }
    }
}
