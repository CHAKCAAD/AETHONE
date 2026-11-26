package com.chakcaad.aethone.shield

/// Minimal, strict JSON reader/writer (pure JVM — org.json is not available
/// in the JVM unit tests). Used for the settings export/import file and the
/// self-test reports. Objects keep insertion order; numbers are Long when
/// integral, Double otherwise. Depth and size are bounded by the caller.
object MiniJson {
    class ParseError(msg: String) : IllegalArgumentException(msg)

    fun write(v: Any?): String = StringBuilder().also { w(it, v) }.toString()

    private fun w(sb: StringBuilder, v: Any?) {
        when (v) {
            null -> sb.append("null")
            is Boolean -> sb.append(v)
            is Int, is Long, is Short, is Byte -> sb.append(v.toString())
            is Float, is Double -> {
                val d = (v as Number).toDouble()
                require(!d.isNaN() && !d.isInfinite()) { "non-finite number" }
                sb.append(d.toString())
            }
            is String -> str(sb, v)
            is Map<*, *> -> {
                sb.append('{')
                var first = true
                for ((k, x) in v) {
                    if (!first) sb.append(',')
                    first = false
                    str(sb, k.toString())
                    sb.append(':')
                    w(sb, x)
                }
                sb.append('}')
            }
            is Iterable<*> -> {
                sb.append('[')
                var first = true
                for (x in v) {
                    if (!first) sb.append(',')
                    first = false
                    w(sb, x)
                }
                sb.append(']')
            }
            is Array<*> -> w(sb, v.toList())
            else -> str(sb, v.toString())
        }
    }

    private fun str(sb: StringBuilder, s: String) {
        sb.append('"')
        for (c in s) {
            when (c) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> if (c < ' ') sb.append(String.format("\\u%04x", c.code)) else sb.append(c)
            }
        }
        sb.append('"')
    }

    fun parse(text: String, maxDepth: Int = 32): Any? {
        val p = P(text, maxDepth)
        p.ws()
        val v = p.value(0)
        p.ws()
        if (p.i != text.length) throw ParseError("trailing data at ${p.i}")
        return v
    }

    private class P(val s: String, val maxDepth: Int) {
        var i = 0
        fun ws() { while (i < s.length && s[i] in " \t\r\n") i++ }
        fun fail(m: String): Nothing = throw ParseError("$m at $i")
        fun value(depth: Int): Any? {
            if (depth > maxDepth) fail("too deep")
            if (i >= s.length) fail("unexpected end")
            return when (s[i]) {
                '{' -> obj(depth)
                '[' -> arr(depth)
                '"' -> string()
                't' -> lit("true", true)
                'f' -> lit("false", false)
                'n' -> lit("null", null)
                else -> num()
            }
        }
        fun lit(w: String, v: Any?): Any? {
            if (!s.startsWith(w, i)) fail("bad literal")
            i += w.length
            return v
        }
        fun obj(depth: Int): Map<String, Any?> {
            val m = LinkedHashMap<String, Any?>()
            i++
            ws()
            if (i < s.length && s[i] == '}') { i++; return m }
            while (true) {
                ws()
                if (i >= s.length || s[i] != '"') fail("key expected")
                val k = string()
                ws()
                if (i >= s.length || s[i] != ':') fail("':' expected")
                i++
                ws()
                if (m.containsKey(k)) fail("duplicate key '$k'")
                m[k] = value(depth + 1)
                ws()
                if (i >= s.length) fail("unexpected end")
                if (s[i] == ',') { i++; continue }
                if (s[i] == '}') { i++; return m }
                fail("',' or '}' expected")
            }
        }
        fun arr(depth: Int): List<Any?> {
            val l = ArrayList<Any?>()
            i++
            ws()
            if (i < s.length && s[i] == ']') { i++; return l }
            while (true) {
                ws()
                l += value(depth + 1)
                ws()
                if (i >= s.length) fail("unexpected end")
                if (s[i] == ',') { i++; continue }
                if (s[i] == ']') { i++; return l }
                fail("',' or ']' expected")
            }
        }
        fun string(): String {
            i++
            val sb = StringBuilder()
            while (true) {
                if (i >= s.length) fail("unterminated string")
                val c = s[i++]
                when {
                    c == '"' -> return sb.toString()
                    c == '\\' -> {
                        if (i >= s.length) fail("bad escape")
                        when (val e = s[i++]) {
                            '"' -> sb.append('"'); '\\' -> sb.append('\\'); '/' -> sb.append('/')
                            'b' -> sb.append('\b'); 'f' -> sb.append('\u000c'); 'n' -> sb.append('\n')
                            'r' -> sb.append('\r'); 't' -> sb.append('\t')
                            'u' -> {
                                if (i + 4 > s.length) fail("bad \\u escape")
                                val h = s.substring(i, i + 4).toIntOrNull(16) ?: fail("bad \\u escape")
                                sb.append(h.toChar()); i += 4
                            }
                            else -> fail("bad escape '$e'")
                        }
                    }
                    c < ' ' -> fail("control character in string")
                    else -> sb.append(c)
                }
            }
        }
        fun num(): Any {
            val start = i
            if (i < s.length && s[i] == '-') i++
            while (i < s.length && (s[i].isDigit() || s[i] in ".eE+-")) i++
            val t = s.substring(start, i)
            if (t.isEmpty() || t == "-") fail("value expected")
            return if (t.all { it.isDigit() || it == '-' }) (t.toLongOrNull() ?: fail("integer out of range"))
            else (t.toDoubleOrNull() ?: fail("bad number"))
        }
    }
}
