package com.chakcaad.aethone.shield

import java.security.SecureRandom

/// Family Shield — bypass path (A): the local SOCKS5 listeners.
///
/// Every tunnel core serves a SOCKS5 listener on 127.0.0.1 (1819–1822).
/// Loopback traffic never crosses the TUN, so ANY app on the phone can dial
/// such a listener directly and reach the internet without passing the
/// shield. The fix is per-session random SOCKS username/password: zeptun's
/// client already speaks RFC 1929 (`[handler.socks5] username/password`),
/// but the LISTENER must enforce it. Audit of the pinned cores
/// (2026-11-26, source reading — not device tested):
///
/// | port | served by | auth enforceable? | evidence |
/// |------|-----------|-------------------|----------|
/// | 1819 | Aether core socks server | no | native/aether/aether/src/socks.rs `handshake()`: reads the offered methods and always answers `[5, 0x00]` (no auth); `warn_if_world_reachable` says it "accepts every client without authentication" |
/// | 1820 | Tor mode listener (aether `tor.rs` → `socks::bind_listener`) | no | same aether socks handshake |
/// | 1821 | Psiphon mode listener (psiphon-tunnel-core LocalSocksProxyPort, goptlib SOCKS server; or aether relaying into it) | no (not verified on device) | goptlib reads username/password as pluggable-transport arguments, it does not check them as credentials |
/// | 1822 | Lantern sidecar (Radiance SOCKS inbound via RADIANCE_SOCKS_ADDRESS) | unknown — not wired | native/lanternbridge only passes an address; whether Radiance accepts credentials there was not verified |
///
/// Result: no tunnel can enforce auth today, so none is labelled
/// "protected" against this bypass; Family Shield reports Degraded with
/// `local-socks-unauthenticated:<ports>` and the tunnels keep working
/// exactly as before (nothing is switched on that a listener would refuse).
/// The credential plumbing below is ready for a listener that gains
/// support: flip [Listener.authCapable] only after a device test of that
/// tunnel.
object SocksAuth {
    enum class Listener(val port: Int, val tunnel: String, val authCapable: Boolean) {
        AETHER(1819, "aether", false),
        TOR(1820, "tor", false),
        PSIPHON(1821, "psiphon", false),
        LANTERN(1822, "lantern", false),
        ;

        companion object {
            fun byPort(port: Int): Listener? = entries.firstOrNull { it.port == port }
        }
    }

    data class Credentials(val username: String, val password: String)

    private const val ALPHABET = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    fun newCredentials(random: SecureRandom = SecureRandom()): Credentials {
        fun token(n: Int) = String(CharArray(n) { ALPHABET[random.nextInt(ALPHABET.length)] })
        return Credentials("ae" + token(14), token(32))
    }

    /// Ports the current tunnel exposes that can not enforce auth (the
    /// bypass stays open there).
    fun unprotected(ports: Collection<Int>): List<Int> =
        ports.filter { Listener.byPort(it)?.authCapable != true }.distinct().sorted()

    /// The `[handler.socks5]` lines zeptun needs when a listener enforces
    /// auth (RFC 1929, zeptun config `username` / `password`). Empty when
    /// [c] is null — the unchanged no-auth handshake.
    fun tomlLines(c: Credentials?): String {
        if (c == null) return ""
        require(c.username.all { it.isLetterOrDigit() } && c.password.all { it.isLetterOrDigit() })
        require(c.username.length in 1..255 && c.password.length in 1..255)
        return "username = \"${c.username}\"\npassword = \"${c.password}\""
    }
}
