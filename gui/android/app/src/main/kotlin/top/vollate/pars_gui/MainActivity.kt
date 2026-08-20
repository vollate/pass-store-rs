package top.vollate.pars_gui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import top.vollate.pars_gui.autofill.ParsAutofillStateStore

class MainActivity : FlutterFragmentActivity() {
    private lateinit var managedStoreImporter: ManagedStoreImporter
    private val clipboardHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        managedStoreImporter = ManagedStoreImporter(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ManagedStoreImporter.CHANNEL_NAME,
        ).setMethodCallHandler(managedStoreImporter::handleMethodCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "top.vollate.pars_gui/sensitive_clipboard",
        ).setMethodCallHandler { call, result ->
            val args = call.arguments as? Map<*, *>
            when (call.method) {
                "setClipboard" -> {
                    val text = args?.get("text") as? String
                    if (text == null) {
                        result.error("INVALID_CLIPBOARD", "Missing clipboard text", null)
                        return@setMethodCallHandler
                    }
                    val ownerToken = args["ownerToken"] as? String
                    if (ownerToken == null) {
                        result.error("INVALID_CLIPBOARD", "Missing clipboard owner token", null)
                        return@setMethodCallHandler
                    }
                    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val clip = ClipData.newPlainText(parsClipboardLabel(ownerToken), text)
                    if (args["sensitive"] == true) {
                        clip.description.extras = PersistableBundle().apply {
                            putBoolean("android.content.extra.IS_SENSITIVE", true)
                        }
                    }
                    clipboard.setPrimaryClip(clip)
                    val expiresAfterSeconds = (args["expiresAfterSeconds"] as? Number)?.toLong() ?: 0L
                    if (expiresAfterSeconds > 0) {
                        clipboardHandler.postDelayed(
                            { clearClipboardIfMatches(text, ownerToken) },
                            expiresAfterSeconds * 1000L,
                        )
                    }
                    result.success(null)
                }
                "clearIfMatches" -> {
                    val expected = args?.get("expectedText") as? String
                    val ownerToken = args?.get("ownerToken") as? String
                    if (expected == null || ownerToken == null) {
                        result.error("INVALID_CLIPBOARD", "Missing expected clipboard ownership", null)
                        return@setMethodCallHandler
                    }
                    clearClipboardIfMatches(expected, ownerToken)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "top.vollate.pars_gui/autofill",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "publishState" -> {
                    val args = call.arguments as? Map<*, *>
                    ParsAutofillStateStore.publish(
                        context = this,
                        configPath = args?.get("configPath") as? String,
                        indexPath = args?.get("indexPath") as? String,
                        storeRoot = args?.get("storeRoot") as? String,
                        passphrase = args?.get("passphrase") as? String,
                    )
                    result.success(null)
                }
                "clearState" -> {
                    ParsAutofillStateStore.clear(this)
                    result.success(null)
                }
                "openSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE).apply {
                            data = Uri.parse("package:$packageName")
                        },
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun clearClipboardIfMatches(expectedText: String, ownerToken: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val currentClip = clipboard.primaryClip
        val currentText =
            currentClip
                ?.takeIf { it.itemCount > 0 }
                ?.getItemAt(0)
                ?.coerceToText(this)
                ?.toString()
        val currentLabel = currentClip?.description?.label?.toString()
        if (!parsClipboardMatches(currentText, currentLabel, expectedText, ownerToken)) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            clipboard.clearPrimaryClip()
        } else {
            clipboard.setPrimaryClip(ClipData.newPlainText("Pars", ""))
        }
    }

    override fun onDestroy() {
        if (::managedStoreImporter.isInitialized) {
            managedStoreImporter.dispose()
        }
        super.onDestroy()
    }
}

internal fun parsClipboardLabel(ownerToken: String): String = "Pars:$ownerToken"

internal fun parsClipboardMatches(
    currentText: String?,
    currentLabel: String?,
    expectedText: String,
    ownerToken: String,
): Boolean =
    currentText == expectedText && currentLabel == parsClipboardLabel(ownerToken)
