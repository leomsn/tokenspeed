#!/bin/zsh
# 三态截图台：跑一个本地构建的 TokenSpeed，打一合成长提示词请求，
# 每种 live.state 截一张菜单栏浮窗图（首张是空闲），用于肉眼验收 CLAUDE.md 3.3 的三态。
# 状态由脚本自己另开一条 curl 判定，与 App 的下一次轮询最多差一个刷新周期，
# 忙态很短时可能截到 App 仍显示空闲的一帧——某张图里没有浮窗不代表脚本坏了，重跑即可。
#
#   export STRATA_API_KEY=...   # 见 CLAUDE.md 第五节；脚本不存 key
#   tools/shot_states.sh
#
# 注意它会**临时摘掉 launchd 常驻实例**：常驻那个跑的是 .build/release，直接并跑会有两个
# 状态项抢菜单栏，而且验收时容易看到旧代码。跑完按原样补回，panelPinned 同样先存后还；
# 测试实例只按自己的 pid 收尾，不用 pkill -x TokenSpeed。截图区域按当前菜单栏位置写死，
# 挪了菜单栏就改 REGION。
set -u
: "${STRATA_API_KEY:?先 export STRATA_API_KEY（CLAUDE.md 第五节），脚本里不写明文 key}"
BASE_URL="${BASE_URL:-http://10.10.1.1:8008}"
ROOT="$(cd "${0:A:h}/.." && pwd)"
APP="$ROOT/.build/debug/TokenSpeed"
LABEL=$(sed -n 's/.*static let bundleID = "\(.*\)".*/\1/p' "$ROOT/Sources/TokenSpeed/AppInfo.swift")
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
REGION="${REGION:-1150,0,620,420}"
OUT="${TMPDIR:-/tmp}/tokenspeed-states"
BODY="${TMPDIR:-/tmp}/tokenspeed-shot-body.json"
export BODY
APP_PID=""
WAS_LOADED=0
PIN_SAVED=""

[[ -x $APP ]] || { echo "先构建：swift build（缺 $APP）" && exit 1; }

rm -rf "$OUT"; mkdir -p "$OUT"

cleanup() {
  [[ -n $APP_PID ]] && kill "$APP_PID" 2>/dev/null
  if [[ -n $PIN_SAVED ]]; then
    case "$PIN_SAVED" in
      1) defaults write TokenSpeed panelPinned -bool YES ;;
      0) defaults write TokenSpeed panelPinned -bool NO ;;
    esac
  else
    defaults delete TokenSpeed panelPinned 2>/dev/null
  fi
  (( WAS_LOADED )) && launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null
  echo "已恢复常驻与 panelPinned；截图在 $OUT"
}
trap cleanup EXIT INT TERM

if launchctl list "$LABEL" >/dev/null 2>&1; then
  WAS_LOADED=1
  launchctl bootout "gui/$(id -u)/$LABEL"
  sleep 0.5
fi
PIN_SAVED="$(defaults read TokenSpeed panelPinned 2>/dev/null || true)"
defaults write TokenSpeed panelPinned -bool YES

"$APP" >"$OUT/app.log" 2>&1 &
APP_PID=$!
sleep 2
osascript -e 'tell application "System Events" to tell process "TokenSpeed" to perform action "AXPress" of menu bar item 1 of menu bar 1' >/dev/null
sleep 0.8
screencapture -x -t png -R"$REGION" "$OUT/00-idle.png"

python3 -Ic "
import json, os
unit = '从前有座山，山里有座庙，庙里有个老和尚在讲故事。'
prompt = unit * 1700 + chr(10) + '请只回答一句：这个故事讲完了吗？'
open(os.environ['BODY'],'w').write(json.dumps(
    {'model':'PowerAI','messages':[{'role':'user','content':prompt}],
     'max_tokens':400,'stream':False}, ensure_ascii=False))
"
curl -s --noproxy '' -H "Authorization: Bearer $STRATA_API_KEY" -H 'Content-Type: application/json' \
  -d "@$BODY" "$BASE_URL/v1/chat/completions" -o "$OUT/resp.json" &
LOAD_PID=$!

typeset -A SEEN
SEEN[idle]=1 SEEN[parse_fail]=1 SEEN[none]=1   # 空闲那张进循环前已截过；解析失败的帧截了也没用
for i in $(seq 90); do
  S=$(curl -s --noproxy '' -H "Authorization: Bearer $STRATA_API_KEY" "$BASE_URL/metrics" | python3 -Ic "
import sys, json
try: print((json.load(sys.stdin).get('live') or {}).get('state'))
except Exception: print('parse_fail')
")
  if (( ! ${+SEEN[$S]} )); then
    SEEN[$S]=1
    screencapture -x -t png -R"$REGION" "$OUT/$(printf '%02d' "$i")-$S.png"
    echo "采到 $S"
  fi
  sleep 0.2
done
wait $LOAD_PID 2>/dev/null
ls "$OUT"
