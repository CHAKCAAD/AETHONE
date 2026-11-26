package com.chakcaad.aethone.shield

import java.net.IDN
import java.net.Inet6Address
import java.net.InetAddress

/// Family Shield — name and address normalization (pure JVM). The output is
/// exactly what the native matcher (flow/shield.zig `validName`) accepts:
/// lowercase ASCII / punycode, labels of 1–63 [a-z0-9-_], at most 253 bytes,
/// no trailing dot.
object DomainNames {
    const val MAX_NAME = 253

    fun normalize(raw: String?): String? {
        if (raw == null) return null
        var s = raw.trim()
        if (s.endsWith(".")) s = s.dropLast(1)
        if (s.isEmpty() || s.contains(' ') || s.contains('/') || s.contains(':')) return null
        val ascii = try {
            IDN.toASCII(s, IDN.ALLOW_UNASSIGNED)
        } catch (_: IllegalArgumentException) {
            return null
        }.lowercase()
        if (!valid(ascii)) return null
        // an IPv4 literal is an address rule, not a domain
        if (Cidr.parseV4(ascii) != null) return null
        return ascii
    }

    fun valid(s: String): Boolean {
        if (s.isEmpty() || s.length > MAX_NAME) return false
        var label = 0
        for (c in s) {
            if (c == '.') {
                if (label == 0) return false
                label = 0
                continue
            }
            val ok = c in 'a'..'z' || c in '0'..'9' || c == '-' || c == '_'
            if (!ok) return false
            label++
            if (label > 63) return false
        }
        return label != 0
    }

    /// The suffixes the native matcher probes for [name] (itself first, then
    /// every parent cut at a label boundary) — used by the Kotlin reader and
    /// conflict reports; `notexample.com` never yields `example.com`.
    fun suffixes(name: String): List<String> {
        val out = ArrayList<String>()
        out += name
        var i = name.indexOf('.')
        while (i >= 0 && i + 1 < name.length) {
            out += name.substring(i + 1)
            i = name.indexOf('.', i + 1)
        }
        return out
    }
}

/// An IPv4 / IPv6 network. Host bits must be zero (same rule as the hybrid
/// routing editor); a bare address is a /32 or /128.
data class Cidr(val address: ByteArray, val prefix: Int) {
    val v6: Boolean get() = address.size == 16

    fun contains(a: ByteArray): Boolean {
        if (a.size != address.size) return false
        var bits = prefix
        var i = 0
        while (bits > 0) {
            val take = minOf(8, bits)
            val mask = (0xff shl (8 - take)) and 0xff
            if ((a[i].toInt() and mask) != (address[i].toInt() and mask)) return false
            bits -= take
            i++
        }
        return true
    }

    override fun toString(): String {
        val host = if (v6) {
            (InetAddress.getByAddress(address) as Inet6Address).hostAddress!!.substringBefore('%')
        } else {
            address.joinToString(".") { (it.toInt() and 0xff).toString() }
        }
        return "$host/$prefix"
    }

    override fun equals(other: Any?): Boolean =
        other is Cidr && prefix == other.prefix && address.contentEquals(other.address)

    override fun hashCode(): Int = address.contentHashCode() * 31 + prefix

    companion object {
        fun parse(raw: String?): Cidr? {
            val s = raw?.trim() ?: return null
            if (s.isEmpty()) return null
            val slash = s.indexOf('/')
            val host = if (slash >= 0) s.substring(0, slash) else s
            val bytes = (if (host.contains(':')) parseV6(host) else parseV4(host)) ?: return null
            val max = bytes.size * 8
            val prefix = if (slash >= 0) s.substring(slash + 1).toIntOrNull() ?: return null else max
            if (prefix !in 0..max) return null
            val c = Cidr(bytes, prefix)
            // host bits must be zero
            for (bit in prefix until max) {
                if ((bytes[bit / 8].toInt() shr (7 - bit % 8)) and 1 != 0) return null
            }
            return c
        }

        fun parseV4(s: String): ByteArray? {
            val parts = s.split('.')
            if (parts.size != 4) return null
            val out = ByteArray(4)
            for ((i, p) in parts.withIndex()) {
                if (p.isEmpty() || p.length > 3 || !p.all { it in '0'..'9' }) return null
                val v = p.toInt()
                if (v > 255) return null
                out[i] = v.toByte()
            }
            return out
        }

        /// IPv6 literal only (never a DNS lookup: the input must contain ':').
        fun parseV6(s: String): ByteArray? {
            if (!s.contains(':') || s.contains('%')) return null
            if (!s.all { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' || it == ':' || it == '.' }) return null
            return try {
                val a = InetAddress.getByName(s)
                if (a is Inet6Address) a.address else null
            } catch (_: Exception) {
                null
            }
        }
    }
}
