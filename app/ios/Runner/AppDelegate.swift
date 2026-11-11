import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var platformChannel: PlatformChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ArcanumPlatform") {
      platformChannel = PlatformChannel(messenger: registrar.messenger())
    }
  }
}

/// The "pm/platform" channel, iOS side: saving a file where the user picks.
final class PlatformChannel: NSObject, UIDocumentPickerDelegate {
  private let channel: FlutterMethodChannel
  private var pendingSave: (result: FlutterResult, file: URL)?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "pm/platform", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "saveFile":
        self?.saveFile(call.arguments as? [String: Any], result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func saveFile(_ args: [String: Any]?, result: @escaping FlutterResult) {
    guard pendingSave == nil,
      let name = args?["name"] as? String,
      let bytes = args?["bytes"] as? FlutterStandardTypedData,
      let presenter = Self.topViewController()
    else {
      result(FlutterError(code: "save_failed", message: "invalid request", details: nil))
      return
    }
    // The picker copies a local file to the destination the user chooses.
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let file = dir.appendingPathComponent((name as NSString).lastPathComponent)
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      try bytes.data.write(to: file, options: [.atomic, .completeFileProtection])
    } catch {
      result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
      return
    }
    pendingSave = (result, file)
    let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
    picker.delegate = self
    presenter.present(picker, animated: true)
  }

  private func finishSave(_ saved: Bool) {
    guard let pending = pendingSave else { return }
    pendingSave = nil
    // The export holds vault data: don't leave a copy behind.
    try? FileManager.default.removeItem(at: pending.file.deletingLastPathComponent())
    pending.result(saved)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finishSave(!urls.isEmpty)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishSave(false)
  }

  private static func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}
