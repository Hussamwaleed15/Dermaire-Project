package com.example.dermaire_app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.system.Os
import android.system.OsConstants
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.KeyStore
import java.security.SecureRandom
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        JournalKeyBridge(applicationContext).register(engine)
    }
}

// Device qualification and production activation remain separate gates.
private class JournalKeyBridge(context: Context) {
    private val root = File(context.noBackupFilesDir, "journal-v1")
    companion object { private val worker = Executors.newSingleThreadExecutor() }
    private val main = Handler(Looper.getMainLooper())
    private val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private fun sync(file: File) {
        val fd = Os.open(file.path, OsConstants.O_RDONLY or
            (if (file.isDirectory) OsConstants.O_DIRECTORY else 0), 0)
        try { Os.fsync(fd) } finally { Os.close(fd) }
    }
    private fun write(file: File, data: ByteArray) {
        val temp = File(file.parentFile, file.name + ".tmp")
        FileOutputStream(temp).use { it.write(data); it.flush(); it.fd.sync() }
        check(temp.renameTo(file))
        sync(file.parentFile!!)
    }
    private fun key(alias: String, create: Boolean): SecretKey {
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        check(create) // A missing/invalidated key never silently regenerates.
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or
                KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setUserAuthenticationRequired(false).build())
            generateKey()
        }
    }
    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "dermaire/journal-keys-v1")
            .setMethodCallHandler { call, result ->
                worker.execute {
                    try {
                        val ns = call.argument<String>("namespace") ?: error("namespace")
                        check(Regex("^[a-f0-9]{64}$").matches(ns))
                        check(root.isDirectory || root.mkdirs())
                        sync(root.parentFile!!)
                        val fence = File(root, "$ns.fence")
                        val dir = File(root, ns)
                        val alias = "dermaire.journal.v1.$ns"
                        val output: Any? = when (call.method) {
                            "epoch" -> {
                                val epoch = File(root, "installation.epoch")
                                if (!epoch.exists()) {
                                    check(root.listFiles()?.isEmpty() == true)
                                    write(epoch, ByteArray(32).also { SecureRandom().nextBytes(it) })
                                }
                                epoch.readBytes().also { check(it.size == 32) }
                            }
                            "protectFiles" -> {
                                check(!fence.exists() && dir.isDirectory)
                                dir.listFiles()?.forEach { check(!it.isDirectory); sync(it) }
                                sync(dir); null
                            }
                            "eraseFiles" -> {
                                check(fence.exists())
                                if (dir.exists()) { check(dir.deleteRecursively()); sync(root) }
                                null // Fence retained permanently; namespace cannot be reused.
                            }
                            "fence" -> { write(fence, byteArrayOf(1)); null }
                            "destroyKey" -> {
                                check(fence.exists())
                                if (store.containsAlias(alias)) store.deleteEntry(alias)
                                for (name in listOf("wrapped.key", "wrapped.key.tmp")) {
                                    val file = File(dir, name)
                                    check(!file.exists() || file.delete())
                                }
                                if (dir.exists()) sync(dir)
                                null
                            }
                            "directory", "loadKey", "createKey" -> {
                                check(!fence.exists())
                                check(dir.isDirectory || dir.mkdir())
                                sync(root)
                                if (call.method == "directory") dir.path else {
                                    val wrapped = File(dir, "wrapped.key")
                                    if (call.method == "createKey") check(!wrapped.exists())
                                    if (!wrapped.exists()) {
                                        check(call.method == "createKey")
                                        check(dir.listFiles()?.isEmpty() == true)
                                        check(!store.containsAlias(alias))
                                        // Dart adapter must forbid createKey if any DB/WAL exists.
                                        val raw = ByteArray(32).also { SecureRandom().nextBytes(it) }
                                        try {
                                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                            cipher.init(Cipher.ENCRYPT_MODE, key(alias, true))
                                            cipher.updateAAD(ns.toByteArray(Charsets.US_ASCII))
                                            val ciphertext = cipher.doFinal(raw)
                                            check(cipher.iv.size == 12)
                                            write(wrapped, byteArrayOf(1) + cipher.iv + ciphertext)
                                        } finally { raw.fill(0) }
                                    }
                                    sync(wrapped); sync(dir)
                                    val bytes = wrapped.readBytes()
                                    check(bytes.size == 61 && bytes[0] == 1.toByte())
                                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                    cipher.init(Cipher.DECRYPT_MODE, key(alias, false),
                                        GCMParameterSpec(128, bytes.copyOfRange(1, 13)))
                                    cipher.updateAAD(ns.toByteArray(Charsets.US_ASCII))
                                    cipher.doFinal(bytes.copyOfRange(13, bytes.size)).also { check(it.size == 32) }
                                }
                            }
                            else -> error("unsupported")
                        }
                        main.post { result.success(output) }
                    } catch (_: Exception) {
                        main.post { result.error("journal_key_unavailable", "Protected journal key unavailable", null) }
                    }
                }
            }
    }
}
