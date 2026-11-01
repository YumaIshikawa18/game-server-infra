#!/usr/bin/env bash
# 1 分ごとのヘルスチェック（health.timer）。ServerUp / PlayersOnline を送り、
# 無人 30 分で idle、無応答 60 分で unresponsive の停止処理を呼ぶ。
set -euo pipefail
MC_BIN=${MC_BIN:-$(dirname "${BASH_SOURCE[0]}")}
# shellcheck source=common.sh
. "$MC_BIN/common.sh"

IDLE_LIMIT=${IDLE_LIMIT:-1800}
DOWN_LIMIT=${DOWN_LIMIT:-3600}
GRACE_SECONDS=${GRACE_SECONDS:-600}
STATE_FILE=${STATE_FILE:-$MC_STATE_DIR/state}

read_state() {
  idle_since="" down_since=""
  if [[ -r $STATE_FILE ]]; then
    idle_since=$(sed -n 's/^idle_since=\([0-9]*\)$/\1/p' "$STATE_FILE")
    down_since=$(sed -n 's/^down_since=\([0-9]*\)$/\1/p' "$STATE_FILE")
  fi
}

write_state() {
  mkdir -p "$(dirname "$STATE_FILE")"
  printf 'idle_since=%s\ndown_since=%s\n' "$idle_since" "$down_since" >"$STATE_FILE.new"
  mv "$STATE_FILE.new" "$STATE_FILE"
}

# 状態を更新し、必要な停止理由（idle / unresponsive）を出力する。不要なら何も出さない。
# 引数: 現在時刻（秒）、起動からの経過秒、応答の有無（1/0）、人数（不明なら空）
evaluate() {
  local now=$1 uptime=$2 up=$3 players=$4
  read_state
  if [[ $up == 1 ]]; then
    down_since=""
    if [[ $players == 0 ]]; then
      idle_since=${idle_since:-$now}
    else
      idle_since=""
    fi
  else
    idle_since=""
    # 起動直後はワールドの読み込み中なので、無応答として数えない。
    if ((uptime < GRACE_SECONDS)); then
      down_since=""
    else
      down_since=${down_since:-$now}
    fi
  fi
  write_state
  if [[ -n $down_since ]] && ((now - down_since >= DOWN_LIMIT)); then
    printf 'unresponsive\n'
  elif [[ -n $idle_since ]] && ((now - idle_since >= IDLE_LIMIT)); then
    printf 'idle\n'
  fi
}

main() {
  local up=0 players="" uptime action
  if [[ -e $MC_STATE_DIR/stopping ]]; then
    return 0
  fi
  if ping_server; then
    up=1
    players=$(players_online) || players=""
  fi
  metric ServerUp "$up"
  if [[ -n $players ]]; then
    metric PlayersOnline "$players"
  fi
  uptime=$(cut -d. -f1 /proc/uptime)
  action=$(evaluate "$(date +%s)" "$uptime" "$up" "$players")
  if [[ -n $action ]]; then
    log info "event=auto_stop reason=${action}"
    "$MC_BIN/stop.sh" "$action"
  fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
