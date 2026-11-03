#!/bin/zsh
# SwiftPM 只产出一个裸可执行文件；菜单栏 app 要能被 Finder/launchd 正常对待，得套一层 .app。
# 版本号与 bundle 标识只有一个来源：Sources/TokenSpeed/AppInfo.swift，这里把它们抄进 Info.plist，
# 所以关于窗里、Finder「显示简介」里、bundle 里必然是同一个字符串。
set -e
cd "$(dirname "$0")/.."
APP=TokenSpeed.app
VER=$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/TokenSpeed/AppInfo.swift)
BUILD=$(sed -n 's/.*static let build = "\(.*\)".*/\1/p' Sources/TokenSpeed/AppInfo.swift)
RIGHTS=$(sed -n 's/.*static let copyright = "\(.*\)".*/\1/p' Sources/TokenSpeed/AppInfo.swift)
BUNDLE=$(sed -n 's/.*static let bundleID = "\(.*\)".*/\1/p' Sources/TokenSpeed/AppInfo.swift)
[ -n "$VER" ] || { echo "读不到版本号，AppInfo.swift 改格式了？"; exit 1; }
[ -n "$BUNDLE" ] || { echo "读不到 bundleID，AppInfo.swift 改格式了？"; exit 1; }

swift build -c release
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TokenSpeed "$APP/Contents/MacOS/TokenSpeed"
chmod +x "$APP/Contents/MacOS/TokenSpeed"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>TokenSpeed</string>
	<key>CFBundleDisplayName</key><string>TokenSpeed</string>
	<key>CFBundleExecutable</key><string>TokenSpeed</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VER</string>
	<key>CFBundleVersion</key><string>$BUILD</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSUIElement</key><true/>
	<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
	<key>NSHumanReadableCopyright</key><string>$RIGHTS</string>
	<key>NSSupportsAutomaticTermination</key><false/>
	<key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
EOF
echo 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist"

# 图标现场画，不往仓库里塞二进制资源。中间产物放 .build/（已 gitignore），不做递归删除
swift tools/make_icon.swift ".build/AppIcon.iconset" > /dev/null
iconutil -c icns ".build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

# 没开发者证书，就至少做 ad-hoc 签名：macOS 对未签名二进制的权限记忆更差
codesign --force --sign - "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | tail -1

echo "ok: $APP $VER ($BUILD)"
