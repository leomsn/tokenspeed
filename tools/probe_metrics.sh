#!/bin/zsh
# 在真实负载下按固定间隔抓 /metrics 的 live 全段，落成 jsonl 对照字段口径。
# 改取数代码前先跑这个，别照抄 CLAUDE.md 第三节的指标名（指标随服务端版本变）。
# 会打一合成长提示词请求（reading 段只有提示词够长才抓得住），用完即弃。
#
#   export STRATA_API_KEY=...   # 见 CLAUDE.md 第五节；脚本不存 key
#   tools/probe_metrics.sh [采样次数] [间隔秒]
set -u
: "${STRATA_API_KEY:?先 export STRATA_API_KEY（CLAUDE.md 第五节），脚本里不写明文 key}"
BASE_URL="${BASE_URL:-http://10.10.1.1:8008}"
N="${1:-100}"
INTERVAL="${2:-0.12}"
OUT="${TMPDIR:-/tmp}/tokenspeed-probe.jsonl"
BODY="${TMPDIR:-/tmp}/tokenspeed-probe-body.json"
export BODY
: > "$OUT"

# --noproxy '' 是给 Claude Code 沙箱里的 curl 用的；正常终端里加不加都一样。
python3 -Ic "
import json, os
unit = '从前有座山，山里有座庙，庙里有个老和尚在讲故事。'
prompt = unit * 1500 + chr(10) + '请只回答一句：这个故事讲完了吗？'
open(os.environ['BODY'],'w').write(json.dumps(
    {'model':'PowerAI','messages':[{'role':'user','content':prompt}],
     'max_tokens':240,'stream':False}, ensure_ascii=False))
"

curl -s --noproxy '' -H "Authorization: Bearer $STRATA_API_KEY" -H 'Content-Type: application/json' \
  -d "@$BODY" "$BASE_URL/v1/chat/completions" -o "${OUT%.jsonl}-resp.json" &

for i in $(seq "$N"); do
  curl -s --noproxy '' -H "Authorization: Bearer $STRATA_API_KEY" "$BASE_URL/metrics" | python3 -Ic "
import sys, json
try: m = json.load(sys.stdin)
except Exception: raise SystemExit
live = m.get('live') or {}
live.pop('slots', None)
print(json.dumps(live, ensure_ascii=False))
" >> "$OUT"
  sleep "$INTERVAL"
done
wait
echo "PROBE_DONE $OUT"
