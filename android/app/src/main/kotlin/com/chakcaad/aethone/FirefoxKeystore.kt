package com.chakcaad.aethone

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/// Firefox VPN session vault crypto (Phase 1, docs/FIREFOX_VPN_SECURITY.md).
///
/// The session OAuth pair is stored ONLY as Android-Keystore-encrypted
/// bytes in <filesDir>/firefox/session.vault (the Dart side owns the
/// file): AES/GCM with a non-exportable key held in AndroidKeyStore.
/// A Keystore reset (fresh install / cleared keymaster) makes old vaults
/// undecryptable — the Dart store treats that as ABSENT and wipes the
/// file (honest, never a crash).
object FirefoxKeystore {
    private const val KEY_ALIAS = "aethone_firefox_session_vault"
    private const val TRANSFORM = "AES/GCM/NoPadding"
    private const val GCM_TAG_BITS = 128
    private const val IV_LEN = 12

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore",
        )
        gen.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return gen.generateKey()
    }

    /// AES/GCM output = IV(12) || ciphertext+tag. Random IV per call
    /// (setRandomizedEncryptionRequired), prefixed for the decrypt side.
    fun encrypt(plaintext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORM)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val iv = cipher.iv
        val body = cipher.doFinal(plaintext)
        return iv + body
    }

    fun decrypt(blob: ByteArray): ByteArray {
        require(blob.size > IV_LEN) { "vault blob too short" }
        val iv = blob.copyOfRange(0, IV_LEN)
        val body = blob.copyOfRange(IV_LEN, blob.size)
        val cipher = Cipher.getInstance(TRANSFORM)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(GCM_TAG_BITS, iv))
        return cipher.doFinal(body)
    }
}
