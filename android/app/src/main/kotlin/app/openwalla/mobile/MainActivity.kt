package app.openwalla.mobile

import android.os.Build
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        setupEdgeToEdge()
    }

    private fun setupEdgeToEdge() {
        WindowCompat.setDecorFitsSystemWindows(window, false)

        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller?.let {
            it.isAppearanceLightStatusBars = false
            it.isAppearanceLightNavigationBars = false
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            enableModernEdgeToEdge()
        }
    }

    private fun enableModernEdgeToEdge() {
        try {
            val edgeToEdgeClass = Class.forName("androidx.activity.EdgeToEdge")
            val enableMethod =
                edgeToEdgeClass.getMethod(
                    "enable",
                    androidx.activity.ComponentActivity::class.java,
                )
            enableMethod.invoke(null, this)
        } catch (_: Exception) {
            // WindowCompat already provides the fallback behavior.
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
    }
}
