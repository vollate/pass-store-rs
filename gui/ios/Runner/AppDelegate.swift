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
      name: "top.vollate.pars_gui/sensitive_clipboard",
      binaryMessenger: binaryMessenger
    ).setMethodCallHandler { call, result in
      guard let arguments = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "setClipboard":
        guard let text = arguments["text"] as? String,
          let ownerToken = arguments["ownerToken"] as? String
        else {
          result(
            FlutterError(
              code: "INVALID_CLIPBOARD",
              message: "Missing clipboard text",
              details: nil))
          return
        }
        var options: [UIPasteboard.OptionsKey: Any] = [.localOnly: true]
        if let seconds = arguments["expiresAfterSeconds"] as? NSNumber,
          seconds.doubleValue > 0
        {
          options[.expirationDate] = Date(timeIntervalSinceNow: seconds.doubleValue)
        }
        UIPasteboard.general.setItems(
          [[
            "public.utf8-plain-text": text,
            "top.vollate.pars.clipboard-owner": Data(ownerToken.utf8),
          ]],
          options: options)
        result(nil)
      case "clearIfMatches":
        guard let expected = arguments["expectedText"] as? String,
          let ownerToken = arguments["ownerToken"] as? String
        else {
          result(
            FlutterError(
              code: "INVALID_CLIPBOARD",
              message: "Missing expected clipboard text",
              details: nil))
          return
        }
        let ownerData =
          UIPasteboard.general.items.first?["top.vollate.pars.clipboard-owner"] as? Data
        let currentOwner = ownerData.flatMap { String(data: $0, encoding: .utf8) }
        if UIPasteboard.general.string == expected && currentOwner == ownerToken {
          UIPasteboard.general.items = []
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

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
        ParsAutofillSharedState.clear { clearResult in
          switch clearResult {
          case .success:
            result(nil)
          case .failure(let error):
            result(
              FlutterError(
                code: "AUTOFILL_STATE_CLEAR_FAILED",
                message: error.localizedDescription,
                details: nil))
          }
        }
      case "openSettings":
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
          result(
            FlutterError(
              code: "SETTINGS_UNAVAILABLE",
              message: "System settings URL is unavailable",
              details: nil))
          return
        }
        UIApplication.shared.open(url) { opened in
          result(opened)
        }
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
      ParsAutofillSharedState.syncCredentialIdentities { success in
        if success {
          result(nil)
        } else {
          result(
            FlutterError(
              code: "AUTOFILL_IDENTITY_SYNC_FAILED",
              message: "Credential identities could not be synchronized",
              details: nil))
        }
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
