#!/usr/bin/env bash
# Готовит сборку «Реплика AI» для iPhone (запускать на macOS с Flutter и Xcode).
#
# Что делает — и ТОЛЬКО в рабочей копии, не меняя pubspec.yaml в репозитории:
#   1) копирует слой ИИ из ai_edition/ в lib/ai/ и lib/main_ai.dart;
#   2) добавляет зависимости llamadart (движок llama.cpp) и его iOS-компаньон;
#   3) готовит iOS-часть с минимальной версией iOS 16.4 (требование llamadart;
#      все iPhone 14 и новее на неё обновляются).
# Общий код приложения (lib/app, lib/features) знает про ИИ только через
# интерфейс AutoReplyEngine и без llamadart компилируется как раньше.
# Обычные сборки (Android и iOS 14+) этот скрипт не затрагивает.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$(uname)" != "Darwin" ]; then
  echo "Нужен macOS." >&2
  exit 1
fi

echo "→ Слой ИИ"
mkdir -p lib/ai
cp ai_edition/lib/ai/*.dart lib/ai/
cp ai_edition/lib/main_ai.dart lib/main_ai.dart

echo "→ Swift Package Manager (iOS-компаньон llamadart линкуется через него)"
flutter config --enable-swift-package-manager

echo "→ Зависимости llamadart"
flutter pub add llamadart:^0.10.0 llamadart_llama_cpp_flutter:^0.0.20

echo "→ iOS-часть (iOS 16.4+)"
IOS_MIN_VERSION=16.4 bash tool/prepare_ios.sh

echo "Готово. Дальше: flutter build ios --release --no-codesign -t lib/main_ai.dart"
