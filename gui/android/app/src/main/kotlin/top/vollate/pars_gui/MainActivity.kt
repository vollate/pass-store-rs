package top.vollate.pars_gui

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import top.vollate.pars_gui.autofill.ParsAutofillStateStore

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                else -> result.notImplemented()
            }
        }
    }
}
