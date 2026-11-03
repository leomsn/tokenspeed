#!/bin/zsh
# 把 TokenSpeed 装成 LaunchAgent：登录即起，进程被杀 launchd 几秒内重拉。
# key 只从环境变量取，绝不进仓库；生成的 plist 权限 600（本机用户可读，与"key 只在本机局域网用"一致）。
set -e
cd "$(dirname "$0")/.."
BIN="$PWD/TokenSpeed.app/Contents/MacOS/TokenSpeed"
[ -x "$BIN" ] || { echo "先跑 tools/make_app.sh 生成 TokenSpeed.app"; exit 1; }
[ -n "$STRATA_API_KEY" ] || { echo "先 export STRATA_API_KEY=<服务端 key>；plist 里必须有它，否则菜单栏只会是 !"; exit 1; }

# label 与 bundle 标识同源（plist 文件名必须等于 label，launchd 按文件名找 agent）
LABEL=$(sed -n 's/.*static let bundleID = "\(.*\)".*/\1/p' Sources/TokenSpeed/AppInfo.swift)
[ -n "$LABEL" ] || { echo "读不到 bundleID，AppInfo.swift 改格式了？"; exit 1; }
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key>
	<array><string>$BIN</string></array>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
	<key>EnvironmentVariables</key>
	<dict><key>STRATA_API_KEY</key><string>$STRATA_API_KEY</string></dict>
	<key>StandardOutPath</key><string>$HOME/Library/Logs/TokenSpeed.log</string>
	<key>StandardErrorPath</key><string>$HOME/Library/Logs/TokenSpeed.log</string>
</dict>
</plist>
EOF
chmod 600 "$PLIST"

# 先卸再装：换 bundle 路径时不留两个实例（两个实例会同时打 /metrics，菜单栏还会多出两个图标）
# bootout 是异步的：紧接着 bootstrap 会撞上半摘除的 label，报 "Bootstrap failed: 5: Input/output error"
# （2026-11-02 实测踩过）。首次安装时 bootout 报 "No such process" 属正常，所以吞掉它的错误。
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
sleep 1
launchctl bootstrap "gui/$UID" "$PLIST"
launchctl kickstart -k "gui/$UID/$LABEL"
sleep 1
echo "pid: $(pgrep -x TokenSpeed | tr '\n' ' ')"
