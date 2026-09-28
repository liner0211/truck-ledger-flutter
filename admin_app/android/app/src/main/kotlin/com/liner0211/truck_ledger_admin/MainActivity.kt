package com.liner0211.truck_ledger_admin

import android.os.Build
import android.provider.Settings
import android.view.WindowInsets
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.liner0211.truckledger/system_nav",
        ).setMethodCallHandler { call, result ->
            if (call.method == "getBottomNavInfo") {
                result.success(
                    mapOf(
                        "mode" to navigationMode(),
                        "heightPx" to navigationBarHeightPx(),
                    ),
                )
            } else {
                result.notImplemented()
            }
        }
    }

    /** 0=三键, 1=两键, 2=手势 */
    private fun navigationMode(): Int {
        return try {
            Settings.Secure.getInt(contentResolver, "navigation_mode")
        } catch (_: Settings.SettingNotFoundException) {
            val id = resources.getIdentifier(
                "config_navBarInteractionMode",
                "integer",
                "android",
            )
            if (id > 0) resources.getInteger(id) else 0
        } catch (_: Exception) {
            0
        }
    }

    private fun navigationBarHeightPx(): Int {
        val insets = window.decorView.rootWindowInsets ?: return 0
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            insets.getInsets(WindowInsets.Type.navigationBars()).bottom
        } else {
            @Suppress("DEPRECATION")
            insets.systemWindowInsetBottom
        }
    }
}
