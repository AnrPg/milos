package app.milos.member

import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.Ndef
import android.nfc.tech.NdefFormatable
import android.os.Handler
import android.os.Looper
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin

/**
 * ADR-173: writes a location's NFC door tag (`MilosNfc`, the same interface
 * as on iOS). `write` waits up to a minute for a tag near the phone and
 * writes one URL record (`/c/<location>/n/<code>`). Reading needs no code:
 * the link opens the app through the NDEF intent filter on MainActivity.
 */
@CapacitorPlugin(name = "MilosNfc")
class MilosNfcPlugin : Plugin() {
    private val handler = Handler(Looper.getMainLooper())
    private var pending: PluginCall? = null

    @PluginMethod
    fun isAvailable(call: PluginCall) {
        val adapter = NfcAdapter.getDefaultAdapter(context)
        call.resolve(JSObject().put("available", adapter != null).put("enabled", adapter?.isEnabled == true))
    }

    @PluginMethod
    fun write(call: PluginCall) {
        val url = call.getString("url")
        val adapter = NfcAdapter.getDefaultAdapter(context)
        when {
            url.isNullOrEmpty() || !url.startsWith("https://") -> return call.reject("An https link is required")
            adapter == null -> return call.reject("NFC is not available", "unavailable")
            !adapter.isEnabled -> return call.reject("NFC is off", "disabled")
        }
        stop()
        pending = call
        val flags = NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or NfcAdapter.FLAG_READER_NFC_F or
            NfcAdapter.FLAG_READER_NFC_V or NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK
        adapter!!.enableReaderMode(activity, { tag -> onTag(tag, url!!) }, flags, null)
        handler.postDelayed({ finish(error = "No tag was found", code = "timeout") }, TIMEOUT_MS)
    }

    override fun handleOnPause() {
        finish(error = "Writing was interrupted", code = "cancelled")
        super.handleOnPause()
    }

    private fun onTag(tag: Tag, url: String) {
        val message = NdefMessage(arrayOf(NdefRecord.createUri(url)))
        val error = try {
            val ndef = Ndef.get(tag)
            if (ndef != null) {
                ndef.connect()
                try {
                    when {
                        !ndef.isWritable -> "This tag is read-only"
                        ndef.maxSize < message.byteArrayLength -> "This tag is too small"
                        else -> {
                            ndef.writeNdefMessage(message)
                            null
                        }
                    }
                } finally {
                    ndef.close()
                }
            } else {
                val formatable = NdefFormatable.get(tag) ?: return finish(error = "This tag can't hold a link", code = "unsupported")
                formatable.connect()
                try {
                    formatable.format(message)
                    null
                } finally {
                    formatable.close()
                }
            }
        } catch (exception: Exception) {
            exception.message ?: "The tag wasn't written"
        }
        finish(error = error, code = "write_failed")
    }

    private fun finish(error: String?, code: String) {
        val call = pending ?: return
        pending = null
        handler.post {
            stop()
            if (error == null) call.resolve() else call.reject(error, code)
        }
    }

    private fun stop() {
        handler.removeCallbacksAndMessages(null)
        val adapter = NfcAdapter.getDefaultAdapter(context) ?: return
        activity?.let { runCatching { adapter.disableReaderMode(it) } }
    }

    companion object {
        private const val TIMEOUT_MS = 60_000L
    }
}
