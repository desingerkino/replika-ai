import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Превью камеры, заполняющее весь родительский размер без растяжения
/// (как BoxFit.cover): лишнее обрезается по краям.
///
/// CameraPreview сам выбирает пропорции по ориентации устройства, поэтому
/// и здесь пропорции считаются по той же ориентации. Иначе в портрете
/// изображение растягивается по ширине.
class CameraCover extends StatelessWidget {
  const CameraCover({super.key, required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    final orientation = value.isRecordingVideo
        ? (value.recordingOrientation ?? value.deviceOrientation)
        : (value.previewPauseOrientation ?? value.lockedCaptureOrientation ?? value.deviceOrientation);
    final landscape =
        orientation == DeviceOrientation.landscapeLeft || orientation == DeviceOrientation.landscapeRight;
    final ratio = landscape ? value.aspectRatio : 1 / value.aspectRatio;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(width: ratio * 1000, height: 1000, child: CameraPreview(controller)),
    );
  }
}
