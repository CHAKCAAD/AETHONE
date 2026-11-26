package com.chakcaad.aethone.shield

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey

/// Family Shield — the SQLite source of truth (Android). Lives in
/// noBackupFilesDir and is excluded from Auto Backup / device transfer
/// (res/xml/backup_rules.xml, data_extraction_rules.xml), so a PIN or a
/// policy never travels to another device or a cloud backup.
///
/// Tables: config, age_profiles, parent_rules, app_restrictions,
/// profile_history, protection_events (aggregated, minute buckets), pin_state.
/// Nothing here is read per packet: the engine reads the compiled snapshot.
class ShieldStore(context: Context) :
    SQLiteOpenHelper(context, File(context.noBackupFilesDir, DB_NAME).absolutePath, null, VERSION),
    ShieldRepository {

    companion object {
        const val DB_NAME = "family_shield.db"
        const val VERSION = 1
    }

    override fun onConfigure(db: SQLiteDatabase) {
        db.enableWriteAheadLogging()
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE config (k TEXT PRIMARY KEY, v TEXT NOT NULL)")
        db.execSQL(
            "CREATE TABLE age_profiles (id TEXT PRIMARY KEY, name TEXT NOT NULL, preset TEXT NOT NULL, " +
                "categories TEXT NOT NULL, allow_categories TEXT NOT NULL, unknown_policy TEXT NOT NULL, " +
                "strict INTEGER NOT NULL, updated_at INTEGER NOT NULL)",
        )
        db.execSQL(
            "CREATE TABLE parent_rules (id TEXT PRIMARY KEY, profile_id TEXT NOT NULL, kind TEXT NOT NULL, " +
                "value TEXT NOT NULL, action TEXT NOT NULL, note TEXT, created_at INTEGER NOT NULL)",
        )
        db.execSQL("CREATE INDEX parent_rules_profile ON parent_rules(profile_id)")
        db.execSQL(
            "CREATE TABLE app_restrictions (profile_id TEXT NOT NULL, package TEXT NOT NULL, " +
                "created_at INTEGER NOT NULL, PRIMARY KEY (profile_id, package))",
        )
        db.execSQL(
            "CREATE TABLE profile_history (id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER NOT NULL, " +
                "from_id TEXT, to_id TEXT, reason TEXT NOT NULL)",
        )
        db.execSQL(
            "CREATE TABLE protection_events (minute INTEGER NOT NULL, kind TEXT NOT NULL, level INTEGER NOT NULL, " +
                "category TEXT NOT NULL, app TEXT NOT NULL, domain TEXT NOT NULL, count INTEGER NOT NULL, " +
                "PRIMARY KEY (minute, kind, level, category, app, domain))",
        )
        db.execSQL(
            "CREATE TABLE pin_state (id INTEGER PRIMARY KEY CHECK (id = 1), iterations INTEGER NOT NULL, " +
                "salt BLOB NOT NULL, hash BLOB NOT NULL, fail_count INTEGER NOT NULL, locked_until INTEGER NOT NULL, " +
                "rsalt BLOB, rhash BLOB, rused INTEGER NOT NULL, bio INTEGER NOT NULL, created_at INTEGER NOT NULL)",
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // v1 is the first schema; future versions migrate here.
    }

    // ---- config --------------------------------------------------------

    private fun cfgGet(db: SQLiteDatabase, k: String): String? =
        db.rawQuery("SELECT v FROM config WHERE k = ?", arrayOf(k)).use { if (it.moveToFirst()) it.getString(0) else null }

    private fun cfgPut(db: SQLiteDatabase, k: String, v: String) {
        db.insertWithOnConflict("config", null, ContentValues().apply { put("k", k); put("v", v) }, SQLiteDatabase.CONFLICT_REPLACE)
    }

    @Synchronized override fun config(): ShieldConfig {
        val db = readableDatabase
        return ShieldConfig(
            enabled = cfgGet(db, "enabled") == "1",
            activeProfileId = cfgGet(db, "active_profile"),
            logDomains = cfgGet(db, "log_domains") == "1",
            retentionDays = cfgGet(db, "retention_days")?.toIntOrNull() ?: 30,
            generation = cfgGet(db, "generation")?.toIntOrNull() ?: 0,
            updatedAt = cfgGet(db, "updated_at")?.toLongOrNull() ?: 0L,
        )
    }

    @Synchronized override fun saveConfig(c: ShieldConfig) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            cfgPut(db, "enabled", if (c.enabled) "1" else "0")
            if (c.activeProfileId != null) cfgPut(db, "active_profile", c.activeProfileId)
            else db.delete("config", "k = ?", arrayOf("active_profile"))
            cfgPut(db, "log_domains", if (c.logDomains) "1" else "0")
            cfgPut(db, "retention_days", c.retentionDays.toString())
            cfgPut(db, "generation", c.generation.toString())
            cfgPut(db, "updated_at", c.updatedAt.toString())
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    // ---- profiles --------------------------------------------------------

    private fun packStrict(s: StrictOptions): Int =
        (if (s.enabled) 1 else 0) or (if (s.blockDot) 2 else 0) or (if (s.blockQuic) 4 else 0) or
            (if (s.blockAltDns) 8 else 0) or (if (s.blockDirectIp) 16 else 0)

    private fun unpackStrict(v: Int) = StrictOptions(v and 1 != 0, v and 2 != 0, v and 4 != 0, v and 8 != 0, v and 16 != 0)

    private fun cats(s: String): Set<ShieldCategory> = s.split(',').mapNotNull { ShieldCategory.byKey(it.trim()) }.toSet()

    @Synchronized override fun profiles(): List<AgeProfile> {
        val out = ArrayList<AgeProfile>()
        readableDatabase.rawQuery(
            "SELECT id, name, preset, categories, allow_categories, unknown_policy, strict, updated_at FROM age_profiles ORDER BY rowid",
            null,
        ).use { c ->
            while (c.moveToNext()) {
                out += AgeProfile(
                    id = c.getString(0),
                    name = c.getString(1),
                    preset = AgePreset.byKey(c.getString(2)) ?: AgePreset.CUSTOM,
                    categories = cats(c.getString(3)),
                    allowCategories = cats(c.getString(4)),
                    unknownPolicy = if (c.getString(5) == "block") UnknownPolicy.BLOCK else UnknownPolicy.ALLOW,
                    strict = unpackStrict(c.getInt(6)),
                    updatedAt = c.getLong(7),
                )
            }
        }
        return out
    }

    @Synchronized override fun upsertProfile(p: AgeProfile) {
        writableDatabase.insertWithOnConflict(
            "age_profiles", null,
            ContentValues().apply {
                put("id", p.id)
                put("name", p.name)
                put("preset", p.preset.key)
                put("categories", p.categories.joinToString(",") { it.key })
                put("allow_categories", p.allowCategories.joinToString(",") { it.key })
                put("unknown_policy", if (p.unknownPolicy == UnknownPolicy.BLOCK) "block" else "allow")
                put("strict", packStrict(p.strict))
                put("updated_at", p.updatedAt)
            },
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    @Synchronized override fun deleteProfile(id: String) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete("age_profiles", "id = ?", arrayOf(id))
            db.delete("parent_rules", "profile_id = ?", arrayOf(id))
            db.delete("app_restrictions", "profile_id = ?", arrayOf(id))
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    // ---- rules -------------------------------------------------------------

    @Synchronized override fun rules(profileId: String): List<ParentRule> {
        val out = ArrayList<ParentRule>()
        readableDatabase.rawQuery(
            "SELECT id, kind, value, action, note, created_at FROM parent_rules WHERE profile_id = ? ORDER BY created_at",
            arrayOf(profileId),
        ).use { c ->
            while (c.moveToNext()) {
                val kind = runCatching { RuleKind.valueOf(c.getString(1)) }.getOrNull() ?: continue
                val action = runCatching { RuleAction.valueOf(c.getString(3)) }.getOrNull() ?: continue
                out += ParentRule(c.getString(0), profileId, kind, c.getString(2), action, c.getString(4), c.getLong(5))
            }
        }
        return out
    }

    @Synchronized override fun addRule(r: ParentRule) {
        writableDatabase.insertWithOnConflict(
            "parent_rules", null,
            ContentValues().apply {
                put("id", r.id); put("profile_id", r.profileId); put("kind", r.kind.name)
                put("value", r.value); put("action", r.action.name); put("note", r.note); put("created_at", r.createdAt)
            },
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    @Synchronized override fun removeRule(id: String) {
        writableDatabase.delete("parent_rules", "id = ?", arrayOf(id))
    }

    @Synchronized override fun appRestrictions(profileId: String): List<AppRestriction> {
        val out = ArrayList<AppRestriction>()
        readableDatabase.rawQuery(
            "SELECT package, created_at FROM app_restrictions WHERE profile_id = ?", arrayOf(profileId),
        ).use { c -> while (c.moveToNext()) out += AppRestriction(profileId, c.getString(0), c.getLong(1)) }
        return out
    }

    @Synchronized override fun addAppRestriction(a: AppRestriction) {
        writableDatabase.insertWithOnConflict(
            "app_restrictions", null,
            ContentValues().apply { put("profile_id", a.profileId); put("package", a.packageName); put("created_at", a.createdAt) },
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    @Synchronized override fun removeAppRestriction(profileId: String, packageName: String) {
        writableDatabase.delete("app_restrictions", "profile_id = ? AND package = ?", arrayOf(profileId, packageName))
    }

    @Synchronized override fun appendHistory(c: ProfileChange) {
        writableDatabase.insert(
            "profile_history", null,
            ContentValues().apply { put("at", c.at); put("from_id", c.fromProfileId); put("to_id", c.toProfileId); put("reason", c.reason) },
        )
    }

    @Synchronized override fun history(limit: Int): List<ProfileChange> {
        val out = ArrayList<ProfileChange>()
        readableDatabase.rawQuery(
            "SELECT at, from_id, to_id, reason FROM profile_history ORDER BY id DESC LIMIT ?", arrayOf(limit.toString()),
        ).use { c -> while (c.moveToNext()) out += ProfileChange(c.getLong(0), c.getString(1), c.getString(2), c.getString(3)) }
        return out
    }

    // ---- PIN ---------------------------------------------------------------

    @Synchronized override fun pinState(): PinState? =
        readableDatabase.rawQuery(
            "SELECT iterations, salt, hash, fail_count, locked_until, rsalt, rhash, rused, bio, created_at FROM pin_state WHERE id = 1",
            null,
        ).use { c ->
            if (!c.moveToFirst()) null
            else PinState(
                iterations = c.getInt(0), salt = c.getBlob(1), hash = c.getBlob(2), failCount = c.getInt(3),
                lockedUntil = c.getLong(4), recoverySalt = if (c.isNull(5)) null else c.getBlob(5),
                recoveryHash = if (c.isNull(6)) null else c.getBlob(6), recoveryUsed = c.getInt(7) != 0,
                biometricEnabled = c.getInt(8) != 0, createdAt = c.getLong(9),
            )
        }

    @Synchronized override fun savePinState(s: PinState?) {
        val db = writableDatabase
        if (s == null) {
            db.delete("pin_state", null, null)
            return
        }
        db.insertWithOnConflict(
            "pin_state", null,
            ContentValues().apply {
                put("id", 1); put("iterations", s.iterations); put("salt", s.salt); put("hash", s.hash)
                put("fail_count", s.failCount); put("locked_until", s.lockedUntil)
                put("rsalt", s.recoverySalt); put("rhash", s.recoveryHash)
                put("rused", if (s.recoveryUsed) 1 else 0); put("bio", if (s.biometricEnabled) 1 else 0)
                put("created_at", s.createdAt)
            },
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    // ---- events (batched; UPDATE-then-INSERT: UPSERT needs API 30) ----------

    @Synchronized override fun addEvents(rows: List<EventBucket>) {
        if (rows.isEmpty()) return
        val db = writableDatabase
        db.beginTransaction()
        try {
            for (r in rows) {
                val args = arrayOf(r.minute.toString(), r.kind, r.level.toString(), r.category ?: "", r.app ?: "", r.domain ?: "")
                db.execSQL(
                    "UPDATE protection_events SET count = count + ${r.count} WHERE minute = ? AND kind = ? AND level = ? " +
                        "AND category = ? AND app = ? AND domain = ?",
                    args,
                )
                val changed = db.compileStatement("SELECT changes()").simpleQueryForLong()
                if (changed == 0L) {
                    db.insert(
                        "protection_events", null,
                        ContentValues().apply {
                            put("minute", r.minute); put("kind", r.kind); put("level", r.level)
                            put("category", r.category ?: ""); put("app", r.app ?: ""); put("domain", r.domain ?: "")
                            put("count", r.count)
                        },
                    )
                }
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    @Synchronized override fun events(from: Long, to: Long): List<EventBucket> {
        val out = ArrayList<EventBucket>()
        readableDatabase.rawQuery(
            "SELECT minute, kind, level, category, app, domain, count FROM protection_events WHERE minute >= ? AND minute < ? ORDER BY minute",
            arrayOf(from.toString(), to.toString()),
        ).use { c ->
            while (c.moveToNext()) {
                out += EventBucket(
                    c.getLong(0), c.getString(1), c.getInt(2), c.getString(3).ifEmpty { null },
                    c.getString(4).ifEmpty { null }, c.getString(5).ifEmpty { null }, c.getLong(6),
                )
            }
        }
        return out
    }

    @Synchronized override fun pruneEvents(before: Long) {
        writableDatabase.delete("protection_events", "minute < ?", arrayOf(before.toString()))
    }
}

/// The PIN pepper: an HMAC-SHA256 key generated inside the Android Keystore
/// (StrongBox when the device has one). It never leaves the secure hardware,
/// so the stored PIN hash is useless off this device. Clearing app data
/// deletes the key — and with it the PIN (documented recovery path).
class KeystorePepper : Pepper {
    companion object {
        private const val ALIAS = "aethone_family_shield_pepper_v1"
    }

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        fun generate(strongBox: Boolean): SecretKey {
            val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, "AndroidKeyStore")
            val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
            if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) spec.setIsStrongBoxBacked(true)
            gen.init(spec.build())
            return gen.generateKey()
        }
        return try {
            generate(strongBox = true)
        } catch (_: Exception) {
            generate(strongBox = false)
        }
    }

    override fun mac(data: ByteArray): ByteArray {
        val m = Mac.getInstance("HmacSHA256")
        m.init(key())
        return m.doFinal(data)
    }
}
