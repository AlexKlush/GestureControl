#!/bin/bash
set -e

APP_NAME="GestureControl"
DMG_NAME="${APP_NAME}.dmg"
TMP_DMG="tmp_${DMG_NAME}"
MOUNT_DIR="/Volumes/${APP_NAME}"
APP_PATH="./build/${APP_NAME}.app"
BACKGROUND="./dmg_background.png"
VOLUME_NAME="${APP_NAME}"

echo "➤ Создаём временный DMG..."
hdiutil create -size 200m -fs HFS+ -volname "${VOLUME_NAME}" "${TMP_DMG}" -ov -quiet

echo "➤ Монтируем..."
hdiutil attach "${TMP_DMG}" -mountpoint "${MOUNT_DIR}" -quiet

echo "➤ Копируем приложение..."
cp -R "${APP_PATH}" "${MOUNT_DIR}/"

echo "➤ Создаём симлинк на Applications..."
ln -s /Applications "${MOUNT_DIR}/Applications"

echo "➤ Копируем фоновое изображение..."
mkdir -p "${MOUNT_DIR}/.background"
cp "${BACKGROUND}" "${MOUNT_DIR}/.background/background.png"

echo "➤ Настраиваем вид окна через AppleScript..."
sleep 2
osascript << APPLESCRIPT
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 900, 600}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set background picture of viewOptions to file ".background:background.png"
        set position of item "${APP_NAME}.app" of container window to {185, 250}
        set position of item "Applications" of container window to {600, 250}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

echo "➤ Размонтируем..."
hdiutil detach "${MOUNT_DIR}" -quiet

echo "➤ Конвертируем в финальный DMG..."
hdiutil convert "${TMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${DMG_NAME}" -ov -quiet

echo "➤ Удаляем временный файл..."
rm -f "${TMP_DMG}"

echo "✅ Готово: ${DMG_NAME}"
