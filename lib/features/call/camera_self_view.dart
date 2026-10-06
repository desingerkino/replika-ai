import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import 'camera_cover.dart';

/// Своё изображение с фронтальной камеры в видеозвонке.
///
/// Разрешение на камеру Android спрашивает при первом запуске. При отказе
/// звонок продолжается, а вместо изображения видна понятная подсказка.
/// При сворачивании приложения камера освобождается и включается снова
/// при возврате.
class CameraSelfView extends StatefulWidget {
  const CameraSelfView({super.key, this.width = 112, this.height = 160});

  final double width;
  final double height;

  @override
  State<CameraSelfView> createState() => _CameraSelfViewState();
}

class _CameraSelfViewState extends State<CameraSelfView> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _problem;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
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
      final front = cameras.where((c) => c.lensDirection == CameraLensDirection.front).firstOrNull ?? cameras.first;
      final controller = CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _problem = null;
      });
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
    await controller?.dispose();
  }

  @override
  void dispose() {
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
