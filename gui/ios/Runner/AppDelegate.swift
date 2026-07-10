import AuthenticationServices
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    configureParsPlatformChannels(
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
  }

  private func configureParsPlatformChannels(binaryMessenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(
      name: "top.vollate.pars_gui/ios_runtime",
      binaryMessenger: binaryMessenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "appGroupSupportPath":
        do {
          result(try ParsAutofillSharedState.supportDirectoryURL().path)
        } catch {
          result(
            FlutterError(
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
      binaryMessenger: binaryMessenger
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
      result(
        FlutterError(
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
      result(
        FlutterError(
          code: "AUTOFILL_STATE_PUBLISH_FAILED",
          message: error.localizedDescription,
          details: nil))
    }
  }
}
