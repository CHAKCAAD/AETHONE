package com.chakcaad.aethone.analytics

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject
import java.util.TimeZone

/// Traffic Analytics — the on-device store (docs/traffic-analytics.md §4).
///
/// Nothing per packet and nothing per flow is ever written: [TrafficMeter]
/// aggregates the native meter reports in memory and hands this store one
/// batch of hour-bucket DELTAS every flush. Three tables:
///
///  * `usage_hour`  — bytes per (UTC hour, profile, route, app) + flows.
///  * `rate_hour`   — per (hour, profile, kind, key): peak 2-second rates and
///                    the active seconds, for Peak / Average Speed. kind is
///                    `total`, `route` (key = route id) or `app` (key = app).
///  * `domain_day`  — bytes per (local day, profile, route, app, domain) for
///                    flows whose domain zeptun's fake-IP table knew. No URL,
///                    no path, no content: the host name only.
///  * `usage_day` / `rate_day` — the rollup of hours older than [HOUR_KEEP_DAYS].
///
/// App keys: the package name; [APP_UNATTRIBUTED] for a flow whose owner the
/// platform could not name; [APP_UNMEASURED] for bytes the engine moved that
/// no per-flow meter saw (UDP, DNS…; route = "").
class TrafficStore private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, "traffic_analytics.db", null, 1) {

    companion object {
        const val APP_UNATTRIBUTED = "~unattributed"
        const val APP_UNMEASURED = "~unmeasured"
        const val HOUR_MS = 3_600_000L
        const val DAY_MS = 86_400_000L
        /// Hour rows are kept this long, then folded into day rows.
        const val HOUR_KEEP_DAYS = 45

        @Volatile private var instance: TrafficStore? = null
        fun get(context: Context): TrafficStore =
            instance ?: synchronized(this) {
                instance ?: TrafficStore(context).also { instance = it }
            }
    }

    override fun onCreate(db: SQLiteDatabase) {
        for (t in listOf("usage_hour", "usage_day")) db.execSQL(
            """CREATE TABLE $t (
                 b INTEGER NOT NULL, profile TEXT NOT NULL, route TEXT NOT NULL, app TEXT NOT NULL,
                 up INTEGER NOT NULL DEFAULT 0, down INTEGER NOT NULL DEFAULT 0,
                 flows INTEGER NOT NULL DEFAULT 0,
                 PRIMARY KEY (b, profile, route, app)) WITHOUT ROWID""",
        )
        for (t in listOf("rate_hour", "rate_day")) db.execSQL(
            """CREATE TABLE $t (
                 b INTEGER NOT NULL, profile TEXT NOT NULL, kind TEXT NOT NULL, k TEXT NOT NULL,
                 peak_down INTEGER NOT NULL DEFAULT 0, peak_up INTEGER NOT NULL DEFAULT 0,
                 active_s INTEGER NOT NULL DEFAULT 0,
                 PRIMARY KEY (b, profile, kind, k)) WITHOUT ROWID""",
        )
        db.execSQL(
            """CREATE TABLE domain_day (
                 b INTEGER NOT NULL, profile TEXT NOT NULL, route TEXT NOT NULL, app TEXT NOT NULL,
                 domain TEXT NOT NULL, up INTEGER NOT NULL DEFAULT 0, down INTEGER NOT NULL DEFAULT 0,
                 PRIMARY KEY (b, profile, route, app, domain)) WITHOUT ROWID""",
        )
        db.execSQL(
            """CREATE TABLE session (
                 id INTEGER PRIMARY KEY AUTOINCREMENT, profile TEXT NOT NULL,
                 started INTEGER NOT NULL, ended INTEGER, up INTEGER NOT NULL DEFAULT 0,
                 down INTEGER NOT NULL DEFAULT 0, unmeasured INTEGER NOT NULL DEFAULT 0)""",
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}

    override fun onConfigure(db: SQLiteDatabase) {
        db.enableWriteAheadLogging()
    }

    // ------------------------------------------------------------ writes --

    data class UsageKey(val hour: Long, val profile: String, val route: String, val app: String)
    class Usage { var up = 0L; var down = 0L; var flows = 0L }
    data class RateKey(val hour: Long, val profile: String, val kind: String, val key: String)
    class Rate { var peakDown = 0L; var peakUp = 0L; var activeS = 0L }
    data class DomainKey(val day: Long, val profile: String, val route: String, val app: String, val domain: String)

    /// One transaction per flush: every map is a DELTA (bytes, flows, active
    /// seconds add; peaks take the max).
    fun apply(
        usage: Map<UsageKey, Usage>,
        rates: Map<RateKey, Rate>,
        domains: Map<DomainKey, Usage>,
        session: Long,
        sessionUp: Long,
        sessionDown: Long,
        sessionUnmeasured: Long,
    ) {
        if (usage.isEmpty() && rates.isEmpty() && domains.isEmpty() && session <= 0) return
        val db = writableDatabase
        db.beginTransaction()
        try {
            // UPDATE-then-INSERT: SQLite UPSERT needs 3.24 (API 30); minSdk is 24.
            for ((k, v) in usage) addUsage(db, "usage_hour", k.hour, k.profile, k.route, k.app, v.up, v.down, v.flows)
            for ((k, v) in rates) addRate(db, "rate_hour", k.hour, k.profile, k.kind, k.key, v.peakDown, v.peakUp, v.activeS)
            for ((k, v) in domains) {
                val args = arrayOf<Any>(v.up, v.down, k.day, k.profile, k.route, k.app, k.domain)
                val st = db.compileStatement(
                    "UPDATE domain_day SET up=up+?, down=down+? WHERE b=? AND profile=? AND route=? AND app=? AND domain=?",
                )
                bindAll(st, args)
                if (st.executeUpdateDelete() == 0) {
                    db.insertOrThrow("domain_day", null, ContentValues().apply {
                        put("b", k.day); put("profile", k.profile); put("route", k.route); put("app", k.app)
                        put("domain", k.domain); put("up", v.up); put("down", v.down)
                    })
                }
            }
            if (session > 0 && (sessionUp != 0L || sessionDown != 0L || sessionUnmeasured != 0L)) {
                db.execSQL(
                    "UPDATE session SET up=up+?, down=down+?, unmeasured=unmeasured+? WHERE id=?",
                    arrayOf(sessionUp, sessionDown, sessionUnmeasured, session),
                )
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    private fun bindAll(st: android.database.sqlite.SQLiteStatement, args: Array<Any>) {
        st.clearBindings()
        args.forEachIndexed { i, a ->
            when (a) {
                is Long -> st.bindLong(i + 1, a)
                is Int -> st.bindLong(i + 1, a.toLong())
                else -> st.bindString(i + 1, a.toString())
            }
        }
    }

    private fun addUsage(db: SQLiteDatabase, table: String, b: Long, profile: String, route: String, app: String, up: Long, down: Long, flows: Long) {
        val st = db.compileStatement(
            "UPDATE $table SET up=up+?, down=down+?, flows=flows+? WHERE b=? AND profile=? AND route=? AND app=?",
        )
        bindAll(st, arrayOf(up, down, flows, b, profile, route, app))
        if (st.executeUpdateDelete() == 0) {
            db.insertOrThrow(table, null, ContentValues().apply {
                put("b", b); put("profile", profile); put("route", route); put("app", app)
                put("up", up); put("down", down); put("flows", flows)
            })
        }
    }

    private fun addRate(db: SQLiteDatabase, table: String, b: Long, profile: String, kind: String, k: String, peakDown: Long, peakUp: Long, activeS: Long) {
        val st = db.compileStatement(
            """UPDATE $table SET peak_down=max(peak_down,?), peak_up=max(peak_up,?), active_s=active_s+?
               WHERE b=? AND profile=? AND kind=? AND k=?""",
        )
        bindAll(st, arrayOf(peakDown, peakUp, activeS, b, profile, kind, k))
        if (st.executeUpdateDelete() == 0) {
            db.insertOrThrow(table, null, ContentValues().apply {
                put("b", b); put("profile", profile); put("kind", kind); put("k", k)
                put("peak_down", peakDown); put("peak_up", peakUp); put("active_s", activeS)
            })
        }
    }

    fun openSession(profile: String, now: Long): Long =
        writableDatabase.insert(
            "session", null,
            ContentValues().apply { put("profile", profile); put("started", now) },
        )

    fun closeSession(id: Long, now: Long) {
        if (id <= 0) return
        writableDatabase.execSQL("UPDATE session SET ended=? WHERE id=? AND ended IS NULL", arrayOf(now, id))
    }

    /// A session the process died in (no closeSession) ends at its last flush.
    fun closeOrphans(now: Long) {
        writableDatabase.execSQL("UPDATE session SET ended=? WHERE ended IS NULL", arrayOf(now))
    }

    /// Folds hours older than [HOUR_KEEP_DAYS] into local days and drops
    /// everything older than [retentionDays] (0 = keep forever).
    fun compact(now: Long, retentionDays: Int, tz: TimeZone = TimeZone.getDefault()) {
        val db = writableDatabase
        val cutHour = (now - HOUR_KEEP_DAYS * DAY_MS) / HOUR_MS
        val off = tz.getOffset(now).toLong()
        db.beginTransaction()
        try {
            db.rawQuery(
                """SELECT ((b*$HOUR_MS+$off)/$DAY_MS)*$DAY_MS-$off, profile, route, app, sum(up), sum(down), sum(flows)
                   FROM usage_hour WHERE b < $cutHour GROUP BY 1,2,3,4""",
                null,
            ).use { c ->
                while (c.moveToNext()) addUsage(
                    db, "usage_day", c.getLong(0), c.getString(1), c.getString(2), c.getString(3),
                    c.getLong(4), c.getLong(5), c.getLong(6),
                )
            }
            db.rawQuery(
                """SELECT ((b*$HOUR_MS+$off)/$DAY_MS)*$DAY_MS-$off, profile, kind, k, max(peak_down), max(peak_up), sum(active_s)
                   FROM rate_hour WHERE b < $cutHour GROUP BY 1,2,3,4""",
                null,
            ).use { c ->
                while (c.moveToNext()) addRate(
                    db, "rate_day", c.getLong(0), c.getString(1), c.getString(2), c.getString(3),
                    c.getLong(4), c.getLong(5), c.getLong(6),
                )
            }
            db.execSQL("DELETE FROM usage_hour WHERE b < $cutHour")
            db.execSQL("DELETE FROM rate_hour WHERE b < $cutHour")
            if (retentionDays > 0) {
                val cutMs = now - retentionDays * DAY_MS
                for (t in listOf("usage_day", "rate_day", "domain_day")) db.execSQL("DELETE FROM $t WHERE b < $cutMs")
                db.execSQL("DELETE FROM usage_hour WHERE b < ${cutMs / HOUR_MS}")
                db.execSQL("DELETE FROM rate_hour WHERE b < ${cutMs / HOUR_MS}")
                db.execSQL("DELETE FROM session WHERE started < $cutMs")
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun clearAll() {
        val db = writableDatabase
        for (t in listOf("usage_hour", "usage_day", "rate_hour", "rate_day", "domain_day", "session")) {
            db.execSQL("DELETE FROM $t")
        }
        db.execSQL("VACUUM")
    }

    // ------------------------------------------------------------- reads --

    /// The usage rows of [from, to) as ONE virtual table: hour rows with
    /// their epoch ms, plus day rows (older ranges). Bucketing happens in SQL.
    private fun usageUnion(from: Long, to: Long): String =
        """SELECT b*$HOUR_MS AS t, profile, route, app, up, down, flows FROM usage_hour
             WHERE b >= ${from / HOUR_MS} AND b < ${(to + HOUR_MS - 1) / HOUR_MS}
           UNION ALL
           SELECT b AS t, profile, route, app, up, down, flows FROM usage_day
             WHERE b >= $from AND b < $to"""

    private fun rateUnion(from: Long, to: Long): String =
        """SELECT b*$HOUR_MS AS t, profile, kind, k, peak_down, peak_up, active_s FROM rate_hour
             WHERE b >= ${from / HOUR_MS} AND b < ${(to + HOUR_MS - 1) / HOUR_MS}
           UNION ALL
           SELECT b AS t, profile, kind, k, peak_down, peak_up, active_s FROM rate_day
             WHERE b >= $from AND b < $to"""

    /// The Flutter query contract (docs/traffic-analytics.md §5). [q]:
    ///   from, to (epoch ms), bucketMs (3600000 | 86400000), tzOffsetMs,
    ///   profile? (filter), app? (filter), route? (filter).
    fun query(q: JSONObject): JSONObject {
        val from = q.getLong("from")
        val to = q.getLong("to")
        val bucket = q.optLong("bucketMs", HOUR_MS).coerceAtLeast(HOUR_MS)
        val tz = q.optLong("tzOffsetMs", 0L)
        val args = ArrayList<String>()
        val where = StringBuilder("1=1")
        q.optString("profile").takeIf { it.isNotEmpty() }?.let { where.append(" AND profile=?"); args += it }
        q.optString("app").takeIf { it.isNotEmpty() }?.let { where.append(" AND app=?"); args += it }
        q.optString("route").takeIf { it.isNotEmpty() }?.let { where.append(" AND route=?"); args += it }
        val a = args.toTypedArray()
        val db = readableDatabase
        val u = usageUnion(from, to)
        val out = JSONObject()

        // series: measured bytes per bucket (unmeasured separately)
        val series = JSONArray()
        db.rawQuery(
            """SELECT ((t+$tz)/$bucket)*$bucket-$tz AS bk,
                      sum(CASE WHEN app<>'$APP_UNMEASURED' THEN up ELSE 0 END),
                      sum(CASE WHEN app<>'$APP_UNMEASURED' THEN down ELSE 0 END),
                      sum(CASE WHEN app='$APP_UNMEASURED' THEN up+down ELSE 0 END)
               FROM ($u) WHERE $where GROUP BY bk ORDER BY bk""",
            a,
        ).use { c ->
            while (c.moveToNext()) series.put(
                JSONObject().put("t", c.getLong(0)).put("up", c.getLong(1))
                    .put("down", c.getLong(2)).put("unmeasured", c.getLong(3)),
            )
        }
        out.put("series", series)

        // apps (measured only), with their route count
        val apps = JSONArray()
        db.rawQuery(
            """SELECT app, sum(up), sum(down), sum(flows), count(DISTINCT route)
               FROM ($u) WHERE $where AND app<>'$APP_UNMEASURED'
               GROUP BY app ORDER BY sum(up)+sum(down) DESC""",
            a,
        ).use { c ->
            while (c.moveToNext()) apps.put(
                JSONObject().put("app", c.getString(0)).put("up", c.getLong(1)).put("down", c.getLong(2))
                    .put("flows", c.getLong(3)).put("routes", c.getLong(4)),
            )
        }
        out.put("apps", apps)

        // routes (profile + route id), with their app count
        val routes = JSONArray()
        db.rawQuery(
            """SELECT profile, route, sum(up), sum(down), sum(flows),
                      count(DISTINCT CASE WHEN app NOT LIKE '~%' THEN app END)
               FROM ($u) WHERE $where AND app<>'$APP_UNMEASURED'
               GROUP BY profile, route ORDER BY sum(up)+sum(down) DESC""",
            a,
        ).use { c ->
            while (c.moveToNext()) routes.put(
                JSONObject().put("profile", c.getString(0)).put("route", c.getString(1))
                    .put("up", c.getLong(2)).put("down", c.getLong(3)).put("flows", c.getLong(4))
                    .put("apps", c.getLong(5)),
            )
        }
        out.put("routes", routes)

        // per-app trend for the list sparklines (bucket → bytes), one query
        if (q.optBoolean("appSeries")) {
            val m = JSONObject()
            db.rawQuery(
                """SELECT app, ((t+$tz)/$bucket)*$bucket-$tz AS bk, sum(up)+sum(down)
                   FROM ($u) WHERE $where AND app<>'$APP_UNMEASURED' GROUP BY app, bk""",
                a,
            ).use { c ->
                while (c.moveToNext()) {
                    val app = c.getString(0)
                    val o = m.optJSONObject(app) ?: JSONObject().also { m.put(app, it) }
                    o.put(c.getLong(1).toString(), c.getLong(2))
                }
            }
            out.put("appSeries", m)
        }

        // totals + unmeasured
        db.rawQuery(
            """SELECT sum(CASE WHEN app<>'$APP_UNMEASURED' THEN up ELSE 0 END),
                      sum(CASE WHEN app<>'$APP_UNMEASURED' THEN down ELSE 0 END),
                      sum(CASE WHEN app='$APP_UNMEASURED' THEN up ELSE 0 END),
                      sum(CASE WHEN app='$APP_UNMEASURED' THEN down ELSE 0 END),
                      sum(flows), count(*)
               FROM ($u) WHERE $where""",
            a,
        ).use { c ->
            c.moveToFirst()
            out.put("up", c.getLong(0)).put("down", c.getLong(1))
                .put("unmeasuredUp", c.getLong(2)).put("unmeasuredDown", c.getLong(3))
                .put("flows", c.getLong(4)).put("rows", c.getLong(5))
        }

        // rates for the scope asked: app filter → kind app, route → kind
        // route, else total. Peaks are 2-second windows (bytes/s).
        val (kind, key) = when {
            q.optString("app").isNotEmpty() -> "app" to q.getString("app")
            q.optString("route").isNotEmpty() -> "route" to q.getString("route")
            else -> "total" to ""
        }
        val rargs = ArrayList<String>().apply { add(kind); add(key) }
        val rw = StringBuilder("kind=? AND k=?")
        q.optString("profile").takeIf { it.isNotEmpty() }?.let { rw.append(" AND profile=?"); rargs += it }
        db.rawQuery(
            "SELECT max(peak_down), max(peak_up), sum(active_s) FROM (${rateUnion(from, to)}) WHERE $rw",
            rargs.toTypedArray(),
        ).use { c ->
            c.moveToFirst()
            out.put("peakDown", c.getLong(0)).put("peakUp", c.getLong(1)).put("activeS", c.getLong(2))
        }

        // per-route split for an app (App Details) / per-app split for a route
        if (q.optString("app").isNotEmpty() || q.optString("route").isNotEmpty()) {
            val dom = JSONArray()
            val dArgs = ArrayList<String>()
            val dw = StringBuilder("b >= ? AND b < ?")
            dArgs += (from - DAY_MS).toString(); dArgs += to.toString()
            q.optString("profile").takeIf { it.isNotEmpty() }?.let { dw.append(" AND profile=?"); dArgs += it }
            q.optString("app").takeIf { it.isNotEmpty() }?.let { dw.append(" AND app=?"); dArgs += it }
            q.optString("route").takeIf { it.isNotEmpty() }?.let { dw.append(" AND route=?"); dArgs += it }
            db.rawQuery(
                """SELECT domain, sum(up), sum(down) FROM domain_day WHERE $dw
                   GROUP BY domain ORDER BY sum(up)+sum(down) DESC LIMIT 20""",
                dArgs.toTypedArray(),
            ).use { c ->
                while (c.moveToNext()) dom.put(
                    JSONObject().put("domain", c.getString(0)).put("up", c.getLong(1)).put("down", c.getLong(2)),
                )
            }
            out.put("domains", dom)
        }

        // the history this range can be compared against
        db.rawQuery("SELECT min(b) FROM usage_hour", null).use { c ->
            c.moveToFirst()
            val h = if (c.isNull(0)) null else c.getLong(0) * HOUR_MS
            db.rawQuery("SELECT min(b) FROM usage_day", null).use { d ->
                d.moveToFirst()
                val dd = if (d.isNull(0)) null else d.getLong(0)
                val first = listOfNotNull(h, dd).minOrNull()
                out.put("firstRecord", first ?: JSONObject.NULL)
            }
        }
        return out
    }

    /// Per-app change between two ranges (Comparison): the apps with the
    /// largest absolute change, top [limit].
    fun appChanges(a: JSONObject, b: JSONObject, limit: Int = 5): JSONArray {
        fun totals(q: JSONObject): Map<String, Long> {
            val m = HashMap<String, Long>()
            val args = ArrayList<String>()
            val where = StringBuilder("app NOT LIKE '~%'")
            q.optString("profile").takeIf { it.isNotEmpty() }?.let { where.append(" AND profile=?"); args += it }
            readableDatabase.rawQuery(
                "SELECT app, sum(up)+sum(down) FROM (${usageUnion(q.getLong("from"), q.getLong("to"))}) WHERE $where GROUP BY app",
                args.toTypedArray(),
            ).use { c -> while (c.moveToNext()) m[c.getString(0)] = c.getLong(1) }
            return m
        }
        val cur = totals(a)
        val prev = totals(b)
        val out = JSONArray()
        (cur.keys + prev.keys).distinct()
            .map { Triple(it, cur[it] ?: 0L, prev[it] ?: 0L) }
            .sortedByDescending { kotlin.math.abs(it.second - it.third) }
            .take(limit)
            .forEach { (app, c, p) -> out.put(JSONObject().put("app", app).put("current", c).put("previous", p)) }
        return out
    }

    fun sessions(limit: Int = 50): JSONArray {
        val out = JSONArray()
        readableDatabase.rawQuery(
            "SELECT id, profile, started, ended, up, down, unmeasured FROM session ORDER BY id DESC LIMIT $limit",
            null,
        ).use { c ->
            while (c.moveToNext()) out.put(
                JSONObject().put("id", c.getLong(0)).put("profile", c.getString(1)).put("started", c.getLong(2))
                    .put("ended", if (c.isNull(3)) JSONObject.NULL else c.getLong(3))
                    .put("up", c.getLong(4)).put("down", c.getLong(5)).put("unmeasured", c.getLong(6)),
            )
        }
        return out
    }

    /// Export (docs §7): every usage row, hour rows then day rows, plus the
    /// sessions. CSV columns: granularity,bucket_start_utc_ms,profile,route,app,upload_bytes,download_bytes,flows
    fun export(format: String): String {
        val db = readableDatabase
        if (format == "csv") {
            val sb = StringBuilder("granularity,bucket_start_utc_ms,profile,route,app,upload_bytes,download_bytes,flows\n")
            fun dump(table: String, gran: String, mult: Long) {
                db.rawQuery("SELECT b, profile, route, app, up, down, flows FROM $table ORDER BY b", null).use { c ->
                    while (c.moveToNext()) {
                        sb.append(gran).append(',').append(c.getLong(0) * mult).append(',')
                            .append(csv(c.getString(1))).append(',').append(csv(c.getString(2))).append(',')
                            .append(csv(c.getString(3))).append(',').append(c.getLong(4)).append(',')
                            .append(c.getLong(5)).append(',').append(c.getLong(6)).append('\n')
                    }
                }
            }
            dump("usage_day", "day", 1)
            dump("usage_hour", "hour", HOUR_MS)
            return sb.toString()
        }
        val o = JSONObject().put("format", "aethone-traffic-analytics").put("version", 1)
        val rows = JSONArray()
        fun dumpJ(table: String, gran: String, mult: Long) {
            db.rawQuery("SELECT b, profile, route, app, up, down, flows FROM $table ORDER BY b", null).use { c ->
                while (c.moveToNext()) rows.put(
                    JSONObject().put("granularity", gran).put("bucketStartUtcMs", c.getLong(0) * mult)
                        .put("profile", c.getString(1)).put("route", c.getString(2)).put("app", c.getString(3))
                        .put("uploadBytes", c.getLong(4)).put("downloadBytes", c.getLong(5)).put("flows", c.getLong(6)),
                )
            }
        }
        dumpJ("usage_day", "day", 1)
        dumpJ("usage_hour", "hour", HOUR_MS)
        o.put("usage", rows)
        o.put("sessions", sessions(10_000))
        return o.toString(2)
    }

    private fun csv(s: String): String =
        if (s.any { it == ',' || it == '"' || it == '\n' }) "\"" + s.replace("\"", "\"\"") + "\"" else s
}
