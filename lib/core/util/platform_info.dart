import 'package:flutter/foundation.dart';

/// Платформа для текстов и разделов интерфейса, которые различаются между
/// Android и iOS (инструкции, доступные функции). Визуальной логики здесь нет.
bool get isIOS => defaultTargetPlatform == TargetPlatform.iOS;
