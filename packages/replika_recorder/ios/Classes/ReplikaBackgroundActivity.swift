import Flutter
import UIKit

/// Штатное продление работы приложения после ухода в фон
/// (UIApplication.beginBackgroundTask).
///
/// Зачем: уведомления «Реплики» локальные — их показывает сам Dart-код,
/// когда наступает событие сцены (задержка, «печатает…», сообщение).
/// После блокировки экрана iOS через ~5 секунд приостанавливает
/// приложение, и уже начатый шаг сцены не доходил до уведомления.
/// Пока Dart держит «активность», iOS даёт доделать начатое (обычно до
/// ~30 секунд, точное время решает система). Это не бесконечная фоновая
/// работа: по истечении времени задача закрывается, приложение
/// приостанавливается как обычно.
///
/// Канал: ru.kinoprop.replika/background
///   begin {name}  → Int? (номер активности; nil — система отказала)
///   end   {id}    → nil
final class ReplikaBackgroundActivity: NSObject {

  private var tasks: [Int: UIBackgroundTaskIdentifier] = [:]
  private var nextId = 1

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "ru.kinoprop.replika/background",
      binaryMessenger: registrar.messenger())
    let instance = ReplikaBackgroundActivity()
    // Замыкание держит обработчик, статическое поле — сам канал.
    channel.setMethodCallHandler { call, result in
      instance.handle(call, result: result)
    }
    ReplikaBackgroundActivity.channel = channel
  }

  private static var channel: FlutterMethodChannel?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "begin":
      let name = (args?["name"] as? String) ?? "Реплика"
      result(begin(name: name))
    case "end":
      if let id = args?["id"] as? Int { end(id) }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func begin(name: String) -> Int? {
    let id = nextId
    nextId += 1
    let task = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
      // Время вышло: задачу обязательно закрыть, иначе iOS завершит приложение.
      self?.end(id)
    }
    if task == .invalid { return nil }
    tasks[id] = task
    return id
  }

  private func end(_ id: Int) {
    guard let task = tasks.removeValue(forKey: id) else { return }
    UIApplication.shared.endBackgroundTask(task)
  }
}
