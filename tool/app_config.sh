# Общая конфигурация сборки «Реплики» для Android и iOS.
# Подключается скриптами tool/prepare_android.sh и tool/prepare_ios.sh.
# Идентификатор приложения (applicationId на Android, Bundle ID на iOS)
# задаётся только здесь: ORG + имя проекта.
APP_LABEL="Реплика"
ORG="ru.kinoprop"
PROJECT_NAME="replika"
BUNDLE_ID="${ORG}.${PROJECT_NAME}"
# Минимальная версия iOS (file_picker 12 требует не ниже 14.0).
IOS_MIN_VERSION="${IOS_MIN_VERSION:-14.0}"
