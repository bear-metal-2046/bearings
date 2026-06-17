import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  override func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // 1. Register Flutter plugins
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // 2. Safely create the channel using the engineBridge's messenger
    let iconChannel = FlutterMethodChannel(
        name: "org.tahomarobotics.beariscope/icon",
        binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    // 3. Handle the method calls from Dart
    iconChannel.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "changeIcon" {
        guard let args = call.arguments as? [String: Any],
              let iconName = args["iconName"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Icon name missing", details: nil))
          return
        }
        self?.changeAppIcon(to: iconName, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })
  }

  // 4. Call the iOS System APIs
  private func changeAppIcon(to iconName: String?, result: @escaping FlutterResult) {
    if #available(iOS 10.3, *) {
      // If Dart sends "default", we pass nil to reset to the primary icon
      let name = (iconName == "default") ? nil : iconName

      UIApplication.shared.setAlternateIconName(name) { error in
        if let error = error {
          result(FlutterError(code: "ICON_ERROR", message: error.localizedDescription, details: nil))
        } else {
          result(true)
        }
      }
    } else {
      result(FlutterError(code: "UNSUPPORTED", message: "iOS version too low", details: nil))
    }
  }
}