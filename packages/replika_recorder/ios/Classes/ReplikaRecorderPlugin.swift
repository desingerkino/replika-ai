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

  /// Маршрут, который должен держаться, пока идёт разговор. nil — не в разговоре.
  private var wantSpeaker: Bool?
  private var routeObserver: NSObjectProtocol?
  private var resetObserver: NSObjectProtocol?

  /// Разговор: playAndRecord + голосовой режим уводят звук в разговорный
  /// динамик; громкая связь — переопределение выхода на динамик телефона.
  /// Другие плагины (камера, запись, плеер) после нас переключают категорию
  /// на «defaultToSpeaker», поэтому маршрут не просто выставляется, а
  /// удерживается: любое изменение маршрута проверяется и при расхождении
  /// выставляется заново.
  private func setSpeaker(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let on = (args?["on"] as? Bool) ?? false
    wantSpeaker = on
    startObservingRoute()
    do {
      try applyRoute(on)
      result(true)
    } catch {
      result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
    }
  }

  private func applyRoute(_ on: Bool) throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
    try session.setActive(true)
    try session.overrideOutputAudioPort(on ? .speaker : .none)
  }

  /// Внешние наушники и Bluetooth пользователь выбрал сам — с ними не спорим.
  private func routeMismatch(_ on: Bool) -> Bool {
    let session = AVAudioSession.sharedInstance()
    if session.category != .playAndRecord { return true }
    let outputs = session.currentRoute.outputs.map { $0.portType }
    let external: [AVAudioSession.Port] = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio, .airPlay, .carAudio]
    if outputs.contains(where: { external.contains($0) }) { return false }
    let onSpeaker = outputs.contains(.builtInSpeaker)
    return on ? !onSpeaker : onSpeaker
  }

  private func startObservingRoute() {
    if routeObserver != nil { return }
    let center = NotificationCenter.default
    routeObserver = center.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.enforceRoute() }
    resetObserver = center.addObserver(
      forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.enforceRoute() }
  }

  private func stopObservingRoute() {
    let center = NotificationCenter.default
    if let o = routeObserver { center.removeObserver(o) }
    if let o = resetObserver { center.removeObserver(o) }
    routeObserver = nil
    resetObserver = nil
  }

  /// Вызывается на каждое изменение маршрута; без расхождения ничего не делает,
  /// поэтому собственная перенастройка не зацикливается.
  private func enforceRoute() {
    guard let on = wantSpeaker, routeMismatch(on) else { return }
    try? applyRoute(on)
  }

  /// После разговора возвращаем обычное воспроизведение.
  private func releaseAudioRoute(_ result: @escaping FlutterResult) {
    wantSpeaker = nil
    stopObservingRoute()
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
