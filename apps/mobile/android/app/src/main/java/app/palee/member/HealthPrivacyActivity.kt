package app.milos.member

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import com.getcapacitor.CapConfig

/**
 * ADR-172: Health Connect's «why does this app need access» link (the
 * permissions rationale on Android 13 and lower, and the permission-usage
 * entry on Android 14+). It opens the web page that explains what is read
 * and how it is kept, then closes.
 */
class HealthPrivacyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val base = (CapConfig.loadDefault(this).serverUrl ?: DEFAULT_URL).trimEnd('/')
        val page = getString(R.string.palee_health_privacy_path)
        runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(base + page))) }
        finish()
    }

    companion object {
        private const val DEFAULT_URL = "https://milos.4kq.net"
    }
}
