#!/usr/bin/env bash
# Готовит Android-часть проекта «Реплика».
# 1) Если папки android/ ещё нет — создаёт её штатной командой flutter create
#    (под установленную версию Flutter, поэтому версии Gradle всегда совместимы).
# 2) Ставит название под иконкой и фирменные иконки.
# Скрипт можно запускать повторно — он ничего не ломает.
set -euo pipefail
cd "$(dirname "$0")/.."

. tool/app_config.sh   # APP_LABEL, ORG, PROJECT_NAME

if [ ! -f android/app/src/main/AndroidManifest.xml ]; then
  echo "→ Создаю android/ (flutter create)…"
  flutter create --platforms=android --org "$ORG" --project-name "$PROJECT_NAME" .
fi

MANIFEST="android/app/src/main/AndroidManifest.xml"
echo "→ Название приложения: $APP_LABEL"
perl -pi -e "s/android:label=\"[^\"]*\"/android:label=\"$APP_LABEL\"/" "$MANIFEST"

echo "→ Разрешения"
# Камера — для своего изображения в постановочном видеозвонке. Телефон без
# камеры приложение всё равно установит (required="false").
if ! grep -q 'android.permission.CAMERA' "$MANIFEST"; then
  perl -0pi -e 's#<application#<uses-permission android:name="android.permission.CAMERA"/>\n    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n    <application#' "$MANIFEST"
fi

# Микрофон — для записи голосовых и видеосообщений в чате.
if ! grep -q 'android.permission.RECORD_AUDIO' "$MANIFEST"; then
  perl -0pi -e 's#<application#<uses-permission android:name="android.permission.RECORD_AUDIO"/>\n    <application#' "$MANIFEST"
fi

# Уведомления (Android 13+ спрашивает разрешение при первом показе).
if ! grep -q 'android.permission.POST_NOTIFICATIONS' "$MANIFEST"; then
  perl -0pi -e 's#<application#<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <uses-permission android:name="android.permission.VIBRATE"/>\n    <application#' "$MANIFEST"
fi

# Connect: локальная сеть в релизной сборке. Шаблон Flutter объявляет INTERNET
# только для debug/profile — без этого релизный APK не откроет даже локальный сокет.
for PERM in INTERNET ACCESS_NETWORK_STATE ACCESS_WIFI_STATE CHANGE_NETWORK_STATE \
            CHANGE_WIFI_MULTICAST_STATE WAKE_LOCK FOREGROUND_SERVICE FOREGROUND_SERVICE_CONNECTED_DEVICE \
            REQUEST_IGNORE_BATTERY_OPTIMIZATIONS; do
  if ! grep -q "android.permission.$PERM\"" "$MANIFEST"; then
    perl -0pi -e "s#<application#<uses-permission android:name=\"android.permission.$PERM\"/>\n    <application#" "$MANIFEST"
  fi
done
# Фоновая служба Connect (flutter_foreground_task). Тип connectedDevice —
# обязателен с Android 14: управление телефоном-реквизитом по локальной сети.
if ! grep -q 'flutter_foreground_task.service.ForegroundService' "$MANIFEST"; then
  perl -0pi -e 's#</application>#    <service\n            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"\n            android:foregroundServiceType="connectedDevice"\n            android:exported="false" />\n    </application>#' "$MANIFEST"
fi

echo "→ Gradle: core library desugaring (нужно плагину уведомлений)"
GRADLE_KTS="android/app/build.gradle.kts"
GRADLE_GROOVY="android/app/build.gradle"
if [ -f "$GRADLE_KTS" ]; then
  if ! grep -q 'isCoreLibraryDesugaringEnabled' "$GRADLE_KTS"; then
    perl -0pi -e 's/compileOptions\s*\{/compileOptions {\n        isCoreLibraryDesugaringEnabled = true/' "$GRADLE_KTS"
  fi
  if ! grep -q 'isCoreLibraryDesugaringEnabled' "$GRADLE_KTS"; then
    perl -0pi -e 's/\nandroid\s*\{/\nandroid {\n    compileOptions {\n        isCoreLibraryDesugaringEnabled = true\n    }/' "$GRADLE_KTS"
  fi
  if ! grep -q 'desugar_jdk_libs' "$GRADLE_KTS"; then
    printf '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n' >> "$GRADLE_KTS"
  fi
elif [ -f "$GRADLE_GROOVY" ]; then
  if ! grep -q 'coreLibraryDesugaringEnabled' "$GRADLE_GROOVY"; then
    perl -0pi -e 's/compileOptions\s*\{/compileOptions {\n        coreLibraryDesugaringEnabled true/' "$GRADLE_GROOVY"
  fi
  if ! grep -q 'coreLibraryDesugaringEnabled' "$GRADLE_GROOVY"; then
    perl -0pi -e 's/\nandroid\s*\{/\nandroid {\n    compileOptions {\n        coreLibraryDesugaringEnabled true\n    }/' "$GRADLE_GROOVY"
  fi
  if ! grep -q 'desugar_jdk_libs' "$GRADLE_GROOVY"; then
    printf "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n" >> "$GRADLE_GROOVY"
  fi
fi

echo "→ Иконки"
cp -R tool/android_res/. android/app/src/main/res/

echo "Готово. Дальше: flutter pub get && flutter build apk --release"
