#!/usr/bin/env bash
# Готовит iOS-часть проекта «Реплика» (запускать на macOS с Flutter и Xcode).
# 1) Если папки ios/ ещё нет — создаёт её штатной командой flutter create.
# 2) Название, Bundle ID, минимальная версия iOS, русские тексты разрешений,
#    иконка, делегат уведомлений.
# Скрипт можно запускать повторно — он ничего не ломает.
set -euo pipefail
cd "$(dirname "$0")/.."
. tool/app_config.sh   # APP_LABEL, ORG, PROJECT_NAME, BUNDLE_ID, IOS_MIN_VERSION

if [ "$(uname)" != "Darwin" ]; then
  echo "Нужен macOS (PlistBuddy, Xcode)." >&2
  exit 1
fi

if [ ! -f ios/Runner/Info.plist ]; then
  echo "→ Создаю ios/ (flutter create)…"
  flutter create --platforms=ios --org "$ORG" --project-name "$PROJECT_NAME" .
fi

PLIST="ios/Runner/Info.plist"
PB=/usr/libexec/PlistBuddy

# plist_set <ключ> <тип> <значение>: создаёт ключ или меняет значение.
plist_set() {
  "$PB" -c "Set :$1 $3" "$PLIST" 2>/dev/null || "$PB" -c "Add :$1 $2 $3" "$PLIST"
}

echo "→ Название: $APP_LABEL, Bundle ID: $BUNDLE_ID"
plist_set CFBundleDisplayName string "$APP_LABEL"
plist_set CFBundleName string "$APP_LABEL"
plist_set CFBundleDevelopmentRegion string ru
"$PB" -c "Delete :CFBundleLocalizations" "$PLIST" 2>/dev/null || true
"$PB" -c "Add :CFBundleLocalizations array" "$PLIST"
"$PB" -c "Add :CFBundleLocalizations:0 string ru" "$PLIST"
export BUNDLE_ID
perl -pi -e 's/(PRODUCT_BUNDLE_IDENTIFIER = )(?![^;]*RunnerTests)[^;]+;/$1$ENV{BUNDLE_ID};/g' \
  ios/Runner.xcodeproj/project.pbxproj

echo "→ Минимальная версия iOS: $IOS_MIN_VERSION"
perl -pi -e "s/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;/IPHONEOS_DEPLOYMENT_TARGET = $IOS_MIN_VERSION;/g" \
  ios/Runner.xcodeproj/project.pbxproj
if [ -f ios/Podfile ]; then
  if grep -qE "^\s*#?\s*platform :ios" ios/Podfile; then
    perl -pi -e "s/^\s*#?\s*platform :ios.*/platform :ios, '$IOS_MIN_VERSION'/" ios/Podfile
  else
    perl -0pi -e "s/^/platform :ios, '$IOS_MIN_VERSION'\n/" ios/Podfile
  fi
fi

# Системный экран запуска (до первого кадра Flutter) — того же тёмно-синего
# цвета #070A18, что и фон стартового экрана: без белой вспышки.
LAUNCH="ios/Runner/Base.lproj/LaunchScreen.storyboard"
if [ -f "$LAUNCH" ]; then
  echo "→ Экран запуска: фон #070A18"
  perl -pi -e 's/<color key="backgroundColor"[^>]*\/>/<color key="backgroundColor" red="0.0275" green="0.0392" blue="0.0941" alpha="1" colorSpace="custom" customColorSpace="sRGB"\/>/g' "$LAUNCH"
fi

echo "→ Разрешения (только для реальных функций приложения)"
# Камера: своё изображение в постановочном видеозвонке, запись видеосообщений.
plist_set NSCameraUsageDescription string \
  "Камера нужна, чтобы показывать ваше изображение в видеозвонке и записывать видеосообщения в чате."
# Микрофон: голосовые и видеосообщения.
plist_set NSMicrophoneUsageDescription string \
  "Микрофон нужен, чтобы записывать голосовые и видеосообщения в чате."
# Локальная сеть: Connect — управление телефоном-реквизитом с Prop Controller по Wi-Fi.
plist_set NSLocalNetworkUsageDescription string \
  "Локальная сеть нужна, чтобы Prop Controller мог управлять сценой по Wi-Fi без интернета."
# Выбор фото, видео и музыки из медиатеки устройства (file_picker).
plist_set NSPhotoLibraryUsageDescription string \
  "Доступ к фото и видео нужен, чтобы добавлять их в медиатеку приложения для сцен и чатов."
# Только добавление записи видеозвонка в «Фото» (без чтения медиатеки).
plist_set NSPhotoLibraryAddUsageDescription string \
  "Реплика сохраняет запись видеозвонка в «Фото»."
plist_set NSAppleMusicUsageDescription string \
  "Доступ к музыке нужен, чтобы добавлять аудиофайлы в медиатеку приложения для сцен и чатов."
# Своё шифрование Connect (X25519, AES-GCM, чистый Dart) — это не экспортное
# шифрование в смысле App Store: вопрос при загрузке не задаётся.
plist_set ITSAppUsesNonExemptEncryption bool false

echo "→ Иконка"
rm -rf ios/Runner/Assets.xcassets/AppIcon.appiconset
cp -R tool/ios_res/AppIcon.appiconset ios/Runner/Assets.xcassets/AppIcon.appiconset

echo "→ Локальные уведомления: делегат в AppDelegate"
APPDELEGATE="ios/Runner/AppDelegate.swift"
if ! grep -q "UNUserNotificationCenter" "$APPDELEGATE"; then
  perl -0pi -e 's/(didFinishLaunchingWithOptions[^\{]*\{\n)/$1    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate\n/' "$APPDELEGATE"
  perl -0pi -e 's/import UIKit\n/import UIKit\nimport UserNotifications\n/' "$APPDELEGATE"
fi
if ! grep -q "UNUserNotificationCenter" "$APPDELEGATE"; then
  echo "ВНИМАНИЕ: не удалось добавить делегат уведомлений в $APPDELEGATE." >&2
  echo "Добавьте вручную в application(_:didFinishLaunchingWithOptions:):" >&2
  echo "  UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate" >&2
  exit 1
fi

echo "Готово. Дальше: flutter pub get && flutter build ios --no-codesign"
echo "Для запуска на iPhone: cd ios && pod install && open Runner.xcworkspace, затем выберите Team в Signing & Capabilities."
