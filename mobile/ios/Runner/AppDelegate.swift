import AVKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let volumeButton = VolumeButtonStreamHandler()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    FlutterEventChannel(
      name: "likezzix/volume_button",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setStreamHandler(volumeButton)
  }
}

/// 볼륨 버튼 촬영: Apple 공식 카메라 버튼 API(AVCaptureEventInteraction, iOS 17.2+).
/// 카메라 화면이 듣고 있을 때만 켜고, 아니면 볼륨 버튼의 원래 기능을 유지한다.
private final class VolumeButtonStreamHandler: NSObject, FlutterStreamHandler {
  private var interaction: UIInteraction?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    guard #available(iOS 17.2, *), let view = rootView() else { return nil }
    let capture = AVCaptureEventInteraction { event in
      if event.phase == .began { events(nil) }
    }
    view.addInteraction(capture)
    interaction = capture
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let interaction { interaction.view?.removeInteraction(interaction) }
    interaction = nil
    return nil
  }

  private func rootView() -> UIView? {
    UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.windows.first?.rootViewController?.view }
      .first
  }
}
