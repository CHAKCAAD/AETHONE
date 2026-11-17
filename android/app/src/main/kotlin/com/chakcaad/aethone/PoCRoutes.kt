package com.chakcaad.aethone

import org.json.JSONArray
import org.json.JSONObject

/// Stage 2 per-app routing (PoC) — the adb-driven route configuration.
///
/// Format (identical for the start intent extra `poc_routes` and the live
/// update broadcast):
/// {
///   "routes": [
///     {"id": "direct", "kind": "direct"},
///     {"id": "psiphon", "kind": "socks5", "server": "127.0.0.1:1821", "strict": true}
///   ],
///   "assignments": {"com.example.app": "psiphon"}
/// }
///
/// Route numbers are POSITIONAL: the i-th entry of `routes` is zeptun route
/// i+1 (route 0 is the default — the active engine mode — and is never
/// listed). The same document builds BOTH sides (the zeptun `[routes]` TOML
/// section and the Kotlin package->route map), so the two can never disagree
/// about numbering. Native-side validation (`config.validateRoutes`) is the
/// authority for every constraint duplicated here.
data class PoCRoute(
    val id: String,
    val kind: String, // "socks5" | "direct"
    val server: String, // host:port, socks5 only
    val strict: Boolean, // sequential handshake (goptlib-style upstreams)
)

data class PoCRoutes(
    val routes: List<PoCRoute>,
    val assignments: Map<String, String>, // package -> route id
) {
    val hasDirect: Boolean get() = routes.any { it.kind == "direct" }

    /** package -> route NUMBER (1..N) for the resolver. */
    fun assignmentNumbers(): Map<String, Int> {
        val index = HashMap<String, Int>()
        routes.forEachIndexed { i, r -> index[r.id] = i + 1 }
        val out = HashMap<String, Int>()
        for ((pkg, id) in assignments) index[id]?.let { out[pkg] = it }
        return out
    }

    companion object {
        fun parse(text: String): PoCRoutes {
            val root = JSONObject(text)
            val routes = ArrayList<PoCRoute>()
            val ids = HashSet<String>()
            val arr = root.optJSONArray("routes") ?: JSONArray()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val id = o.getString("id").trim()
                val kind = o.getString("kind").trim()
                if (id.isEmpty() || id.length > 64 || id.any { it.isWhitespace() }) {
                    throw IllegalArgumentException("route id invalid: '$id'")
                }
                if (!ids.add(id)) throw IllegalArgumentException("duplicate route id: '$id'")
                if (kind != "socks5" && kind != "direct") {
                    throw IllegalArgumentException("route kind must be socks5 or direct, got '$kind'")
                }
                val server = if (kind == "socks5") o.getString("server").trim() else o.optString("server").trim()
                if (kind == "socks5") {
                    if (server.isEmpty()) throw IllegalArgumentException("socks5 route '$id' needs a server")
                    val colon = server.lastIndexOf(':')
                    if (colon <= 0 || colon == server.length - 1) {
                        throw IllegalArgumentException("socks5 route '$id' server must be host:port")
                    }
                    val port = server.substring(colon + 1).toIntOrNull()
                    if (port == null || port !in 1..65535) {
                        throw IllegalArgumentException("socks5 route '$id' has an invalid port")
                    }
                } else if (server.isNotEmpty()) {
                    throw IllegalArgumentException("direct route '$id' must not carry a server")
                }
                routes.add(PoCRoute(id, kind, server, o.optBoolean("strict", false)))
            }
            if (routes.size > 8) throw IllegalArgumentException("at most 8 routes (zeptun max_routes)")
            val assignments = HashMap<String, String>()
            val asg = root.optJSONObject("assignments") ?: JSONObject()
            for (key in asg.keys()) {
                val rid = asg.getString(key).trim()
                if (routes.none { it.id == rid }) {
                    throw IllegalArgumentException("assignment of $key references unknown route '$rid'")
                }
                assignments[key] = rid
            }
            return PoCRoutes(routes, assignments)
        }
    }
}

/// The zeptun `[routes]` TOML section (parallel lists — the document schema
/// zeptun's TOML/JSON parser accepts; see native/zeptun src/config_json.zig).
/// Empty string when there are no routes (the section is simply absent and
/// the config stays byte-identical to the pre-PoC document).
fun pocRoutesToml(routes: List<PoCRoute>): String {
    if (routes.isEmpty()) return ""
    fun quote(s: String) = "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
    return buildString {
        appendLine("[routes]")
        append("ids = [").append(routes.joinToString(",") { quote(it.id) }).appendLine("]")
        append("kinds = [").append(routes.joinToString(",") { quote(it.kind) }).appendLine("]")
        append("servers = [").append(routes.joinToString(",") { if (it.kind == "direct") "\"\"" else quote(it.server) }).appendLine("]")
        append("strict = [").append(routes.joinToString(",") { if (it.strict) "true" else "false" }).appendLine("]")
    }
}
