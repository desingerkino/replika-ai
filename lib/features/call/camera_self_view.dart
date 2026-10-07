import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../app/operator_toast.dart';
import '../../core/design/tokens.dart';
import 'camera_cover.dart';

/// Управление камерой в видеозвонке снаружи: кнопка «Перевернуть» на экране звонка.
class CameraSelfController extends ChangeNotifier {
  _CameraSelfViewState? _view;
  bool _canFlip = false;
  bool _front = true;

  /// У телефона есть и фронтальная, и задняя камеры, и камера сейчас работает.
  bool get canFlip => _canFlip;

  /// Сейчас включена фронтальная камера.
  bool get isFront => _front;

  /// Переключает фронтальную ↔ основную камеру, не прерывая звонок.
  Future<void> flip() async => _view?._flip();

  void _update({required bool canFlip, required bool front}) {
    if (canFlip == _canFlip && front == _front) return;
    _canFlip = canFlip;
    _front = front;
    notifyListeners();
  }
}

/// Своё изображение с камеры в видеозвонке (по умолчанию фронтальная).
///
/// Разрешение на камеру Android спрашивает при первом запуске. При отказе
/// звонок продолжается, а вместо изображения видна понятная подсказка.
/// При сворачивании приложения камера освобождается и включается снова
/// при возврате.
class CameraSelfView extends StatefulWidget {
  const CameraSelfView({super.key, this.width = 112, this.height = 160, this.controller});

  final double width;
  final double height;
  final CameraSelfController? controller;

  @override
  State<CameraSelfView> createState() => _CameraSelfViewState();
}

class _CameraSelfViewState extends State<CameraSelfView> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _problem;
  bool _starting = false;
  bool _flipping = false;
  List<CameraDescription> _cameras = const [];
  CameraLensDirection _facing = CameraLensDirection.front;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller?._view = this;
    unawaited(_start());
  }

  @override
  void didUpdateWidget(CameraSelfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._view = null;
      widget.controller?._view = this;
    }
  }

  CameraDescription? _pick(CameraLensDirection direction) =>
      _cameras.where((c) => c.lensDirection == direction).firstOrNull;

  void _publish() {
    if (!mounted) return;
    final ready = _controller?.value.isInitialized ?? false;
    final both = _pick(CameraLensDirection.front) != null && _pick(CameraLensDirection.back) != null;
    widget.controller?._update(canFlip: ready && both && !_flipping, front: _facing == CameraLensDirection.front);
  }

  /// Переключение на лету: тот же CameraController получает другую камеру
  /// (setDescription), звонок, звук и экран не трогаются. Если плагин не
  /// смог — пересоздаём контроллер; если и это не вышло — возвращаем прежнюю.
  Future<void> _flip() async {
    final controller = _controller;
    if (_flipping || _starting || controller == null || !controller.value.isInitialized) return;
    final target = _facing == CameraLensDirection.front ? CameraLensDirection.back : CameraLensDirection.front;
    final next = _pick(target);
    if (next == null) {
      showOperatorToast('На телефоне нет такой камеры');
      return;
    }
    _flipping = true;
    _publish();
    try {
      try {
        await controller.setDescription(next);
      } catch (_) {
        await _restartWith(next);
      }
      _facing = target;
    } catch (_) {
      // Не получилось: пробуем вернуть прежнюю камеру, чтобы картинка не пропала.
      showOperatorToast('Не удалось переключить камеру');
      final previous = _pick(_facing);
      if (previous != null && _controller == null) {
        try {
          await _restartWith(previous);
        } catch (_) {
          _fail('Камера недоступна');
        }
      }
    } finally {
      _flipping = false;
      if (mounted) setState(() {});
      _publish();
    }
  }

  Future<void> _restartWith(CameraDescription description) async {
    final old = _controller;
    _controller = null;
    if (mounted) setState(() {});
    await old?.dispose();
    final fresh = CameraController(description, ResolutionPreset.medium, enableAudio: false);
    try {
      await fresh.initialize();
    } catch (_) {
      await fresh.dispose();
      rethrow;
    }
    if (!mounted) {
      await fresh.dispose();
      return;
    }
    setState(() {
      _controller = fresh;
      _problem = null;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      unawaited(_stop());
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _fail('На телефоне нет камеры');
        return;
      }
      _cameras = cameras;
      // Выбранная камера запоминается: после сворачивания возвращается она же.
      final chosen = _pick(_facing) ?? cameras.first;
      _facing = chosen.lensDirection == CameraLensDirection.back ? CameraLensDirection.back : CameraLensDirection.front;
      final controller = CameraController(chosen, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _problem = null;
      });
      _publish();
    } on CameraException catch (error) {
      _fail(error.code.contains('Access') || error.code.contains('ermission')
          ? 'Нет доступа к камере. Разрешите его в настройках устройства'
          : 'Камера недоступна');
    } catch (_) {
      _fail('Камера недоступна');
    } finally {
      _starting = false;
    }
  }

  void _fail(String text) {
    if (mounted) setState(() => _problem = text);
  }

  Future<void> _stop() async {
    final controller = _controller;
    _controller = null;
    if (mounted) setState(() {});
    _publish();
    await controller?.dispose();
  }

  @override
  void dispose() {
    if (widget.controller?._view == this) widget.controller?._view = null;
    widget.controller?._canFlip = false; // без уведомлений: экран уже закрывается
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    unawaited(controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    Widget child;
    if (controller != null && controller.value.isInitialized) {
      child = CameraCover(controller: controller);
    } else {
      child = Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.s),
          child: _problem == null
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(
                  _problem!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.card),
      child: Container(
        width: widget.width,
        height: widget.height,
        color: const Color(0xFF26313A),
        child: child,
      ),
    );
  }
}
