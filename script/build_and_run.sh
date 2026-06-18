#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="DeepListen"
BUNDLE_ID="com.chengzhong.DeepListen"
MIN_SYSTEM_VERSION="26.0"
APP_VERSION="${APP_VERSION:-0.1.0}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"

write_info_plist() {
  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>DeepListen</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>DeepListen</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.education</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Audio and Video Files</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.audio</string>
        <string>public.movie</string>
        <string>public.audiovisual-content</string>
      </array>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>mp3</string>
        <string>m4a</string>
        <string>aac</string>
        <string>wav</string>
        <string>aiff</string>
        <string>aif</string>
        <string>caf</string>
        <string>flac</string>
        <string>mp4</string>
        <string>m4v</string>
        <string>mov</string>
        <string>avi</string>
        <string>mkv</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST
}

package_app_from_binary() {
  local build_binary="$1"
  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$build_binary" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  if [[ -f "$ICON_SOURCE" ]]; then
    cp "$ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
  fi

  write_info_plist
}

sign_app_adhoc() {
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
}

create_dmg() {
  local arch="$1"
  local dmg_path="$DIST_DIR/${APP_NAME}-${arch}-${APP_VERSION}.dmg"
  rm -f "$dmg_path"

  # 临时目录：包含 app + Applications 符号链接，支持拖拽安装
  local staging_dir
  staging_dir="$(mktemp -d)"
  trap 'rm -rf "${staging_dir:-}"' RETURN
  cp -R "$APP_BUNDLE" "$staging_dir/"
  ln -s /Applications "$staging_dir/Applications"

  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$staging_dir" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$dmg_path" >/dev/null
  trap - RETURN
  rm -rf "$staging_dir"
  echo "$dmg_path"
}

build_only() {
  local arch="${1:-universal}"
  local do_sign=0
  local do_dmg=0
  shift || true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sign) do_sign=1 ;;
      --dmg) do_dmg=1 ;;
      *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
  done

  local build_args=(-c release)
  case "$arch" in
    universal) build_args+=(--arch arm64 --arch x86_64) ;;
    arm64)     build_args+=(--arch arm64) ;;
    x86_64)    build_args+=(--arch x86_64) ;;
    *) echo "unknown arch: $arch (expected universal|arm64|x86_64)" >&2; exit 2 ;;
  esac

  echo "==> Building $arch (version $APP_VERSION)"
  swift build --product "$APP_NAME" "${build_args[@]}"
  local build_binary
  build_binary="$(swift build --show-bin-path "${build_args[@]}")/$APP_NAME"

  package_app_from_binary "$build_binary"

  if [[ $do_sign -eq 1 ]]; then
    echo "==> Ad-hoc signing"
    sign_app_adhoc
  fi

  if [[ $do_dmg -eq 1 ]]; then
    echo "==> Creating DMG"
    create_dmg "$arch"
  fi

  echo "==> Done: $APP_BUNDLE"
}

register_app() {
  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [[ -x "$lsregister" ]]; then
    "$lsregister" -f "$APP_BUNDLE" >/dev/null 2>&1 || true
  fi
}

open_app() {
  register_app
  /usr/bin/open -n "$APP_BUNDLE"
}

# Local development modes (build debug + launch GUI)
build_and_launch_debug() {
  swift build --product "$APP_NAME"
  local build_binary
  build_binary="$(swift build --show-bin-path)/$APP_NAME"
  package_app_from_binary "$build_binary"
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

case "$MODE" in
  --build-only|build-only)
    build_only "${@:2}"
    ;;
  run)
    build_and_launch_debug
    open_app
    ;;
  --debug|debug)
    build_and_launch_debug
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    build_and_launch_debug
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    build_and_launch_debug
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    build_and_launch_debug
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build-only <arch> [--sign] [--dmg]|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
