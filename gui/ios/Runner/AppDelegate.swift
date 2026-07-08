import AuthenticationServices
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    configureParsPlatformChannels()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func configureParsPlatformChannels() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    FlutterMethodChannel(
      name: "top.vollate.pars_gui/ios_runtime",
      binaryMessenger: controller.binaryMessenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "appGroupSupportPath":
        do {
          result(try ParsAutofillSharedState.supportDirectoryURL().path)
        } catch {
          result(FlutterError(
            code: "APP_GROUP_UNAVAILABLE",
            message: error.localizedDescription,
            details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    FlutterMethodChannel(
      name: "top.vollate.pars_gui/autofill",
      binaryMessenger: controller.binaryMessenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "publishState":
        self.publishAutofillState(call: call, result: result)
      case "clearState":
        ParsAutofillSharedState.clear()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func publishAutofillState(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let configPath = args["configPath"] as? String,
      let indexPath = args["indexPath"] as? String
    else {
      result(FlutterError(
        code: "INVALID_AUTOFILL_STATE",
        message: "Missing configPath or indexPath",
        details: nil))
      return
    }

    do {
      try ParsAutofillSharedState.publish(
        configPath: configPath,
        indexPath: indexPath,
        storeRoot: args["storeRoot"] as? String,
        passphrase: args["passphrase"] as? String)
      ParsAutofillSharedState.syncCredentialIdentities { _ in
        result(nil)
      }
    } catch {
      result(FlutterError(
        code: "AUTOFILL_STATE_PUBLISH_FAILED",
        message: error.localizedDescription,
        details: nil))
    }
  }
}
