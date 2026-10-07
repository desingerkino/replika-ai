import Flutter
import UIKit
import ReplayKit
import Photos
import AVFoundation

/// Запись экрана приложения (ReplayKit) и сохранение готового видео в «Фото».
public class ReplikaRecorderPlugin: NSObject, FlutterPlugin {

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "ru.kinoprop.replika/recorder",
      binaryMessenger: registrar.messenger())
    let instance = ReplikaRecorderPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(RPScreenRecorder.shared().isAvailable)
    case "requestGalleryAccess":
      requestGalleryAccess(result)
    case "start":
      start(call, result)
    case "stop":
      stop(result)
    case "saveToGallery":
      saveToGallery(call, result)
    case "setSpeaker":
      setSpeaker(call, result)
    case "releaseAudioRoute":
      releaseAudioRoute(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Маршрут звука

  /// Разговор: playAndRecord по умолчанию уводит звук в разговорный динамик;
  /// громкая связь — переопределение выхода на динамик телефона.
  private func setSpeaker(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let on = (args?["on"] as? Bool) ?? false
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth])
      try session.setActive(true)
      try session.overrideOutputAudioPort(on ? .speaker : .none)
      result(true)
    } catch {
      result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
    }
  }

  /// После разговора возвращаем обычное воспроизведение.
  private func releaseAudioRoute(_ result: @escaping FlutterResult) {
    let session = AVAudioSession.sharedInstance()
    try? session.overrideOutputAudioPort(.none)
    try? session.setCategory(.playback, mode: .default, options: [])
    result(nil)
  }

  // MARK: - Запись

  private func start(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let recorder = RPScreenRecorder.shared()
    guard recorder.isAvailable else {
      result(FlutterError(code: "unavailable", message: "Запись экрана сейчас недоступна", details: nil))
      return
    }
    if recorder.isRecording {
      result(nil)
      return
    }
    let args = call.arguments as? [String: Any]
    recorder.isMicrophoneEnabled = (args?["microphone"] as? Bool) ?? true
    recorder.startRecording { error in
      DispatchQueue.main.async {
        if let error = error as NSError? {
          // -5801: пользователь отказался в системном окне ReplayKit.
          let code = error.code == -5801 ? "denied" : "failed"
          result(FlutterError(code: code, message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
    }
  }

  private func stop(_ result: @escaping FlutterResult) {
    let recorder = RPScreenRecorder.shared()
    guard recorder.isRecording else {
      result(nil)
      return
    }
    let name = "replika_call_\(Int(Date().timeIntervalSince1970)).mp4"
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
    try? FileManager.default.removeItem(at: url)
    recorder.stopRecording(withOutput: url) { error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
        } else {
          result(url.path)
        }
      }
    }
  }

  // MARK: - Галерея

  private func isAllowed(_ status: PHAuthorizationStatus) -> Bool {
    return status == .authorized || status == .limited
  }

  private func requestGalleryAccess(_ result: @escaping FlutterResult) {
    let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    if status == .notDetermined {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
        DispatchQueue.main.async { result(self.isAllowed(newStatus)) }
      }
    } else {
      result(isAllowed(status))
    }
  }

  private func saveToGallery(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
      result(FlutterError(code: "save_failed", message: "Не указан файл", details: nil))
      return
    }
    let name = (args["name"] as? String) ?? "Replika.mp4"
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else {
      result(FlutterError(code: "save_failed", message: "Файл записи не найден", details: nil))
      return
    }

    func save() {
      PHPhotoLibrary.shared().performChanges({
        let request = PHAssetCreationRequest.forAsset()
        let options = PHAssetResourceCreationOptions()
        options.originalFilename = name
        options.shouldMoveFile = false
        request.addResource(with: .video, fileURL: url, options: options)
      }) { success, error in
        DispatchQueue.main.async {
          if success {
            result(true)
          } else {
            result(FlutterError(
              code: "save_failed",
              message: error?.localizedDescription ?? "Не удалось сохранить видео в Фото",
              details: nil))
          }
        }
      }
    }

    let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    if isAllowed(status) {
      save()
    } else if status == .notDetermined {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
        if self.isAllowed(newStatus) {
          save()
        } else {
          DispatchQueue.main.async {
            result(FlutterError(code: "no_access", message: "Нет доступа к Фото", details: nil))
          }
        }
      }
    } else {
      result(FlutterError(code: "no_access", message: "Нет доступа к Фото", details: nil))
    }
  }
}
