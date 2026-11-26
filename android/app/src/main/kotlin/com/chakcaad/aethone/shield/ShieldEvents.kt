package com.chakcaad.aethone.shield

/// Family Shield — protection events, aggregated in memory and written in
/// batches (pure JVM). Nothing is written per flow or per query; no URL is
/// ever seen (no TLS interception) and a domain name is kept only when the
/// parent opted in (ShieldConfig.logDomains). Everything stays on the device.
class ShieldEvents(
    private val clock: () -> Long = System::currentTimeMillis,
) {
    @Volatile var logDomains: Boolean = false

    private data class Key(val minute: Long, val kind: String, val level: Int, val category: String?, val app: String?, val domain: String?)

    private val pending = HashMap<Key, Long>()
    private val lock = Any()

    /// kind: flow_block | dns_block | flow_killed | pin_fail | config_change |
    /// vpn_revoked | snapshot_rejected
    fun record(kind: String, level: Int = 0, category: ShieldCategory? = null, app: String? = null, domain: String? = null, count: Long = 1) {
        val minute = clock() / 60_000L * 60_000L
        val d = if (logDomains) domain?.lowercase()?.trimEnd('.')?.take(DomainNames.MAX_NAME) else null
        val k = Key(minute, kind, level, category?.key, app, d)
        synchronized(lock) { pending[k] = (pending[k] ?: 0L) + count }
    }

    fun pendingCount(): Int = synchronized(lock) { pending.size }

    /// Hands every pending row to [sink] (one batch) and clears the buffer;
    /// on a sink failure the rows are kept for the next flush.
    fun flush(sink: (List<EventBucket>) -> Unit) {
        val rows = synchronized(lock) {
            val r = pending.map { (k, v) -> EventBucket(k.minute, k.kind, k.level, k.category, k.app, k.domain, v) }
            pending.clear()
            r
        }
        if (rows.isEmpty()) return
        try {
            sink(rows)
        } catch (t: Throwable) {
            synchronized(lock) {
                for (r in rows) {
                    val k = Key(r.minute, r.kind, r.level, r.category, r.app, r.domain)
                    pending[k] = (pending[k] ?: 0L) + r.count
                }
            }
            throw t
        }
    }
}
