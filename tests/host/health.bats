#!/usr/bin/env bats
# 自動停止の判定（reliability-design.md §4）。無人 30 分、無応答 60 分、起動直後 10 分の猶予。

load helpers

setup() {
  setup_host
  export STATE_FILE="$MC_STATE_DIR/state"
}

evaluate() {
  bash -c '. "$MC_BIN/health.sh"; evaluate "$@"' health "$@"
}

@test "無人 29 分では止めず、30 分で idle にする" {
  evaluate 1000 3600 1 0
  [ "$(evaluate $((1000 + 29 * 60)) 3600 1 0)" = "" ]
  [ "$(evaluate $((1000 + 30 * 60)) 3600 1 0)" = "idle" ]
}

@test "誰かが接続すると無人の計測をやり直す" {
  evaluate 1000 3600 1 0
  evaluate 2000 3600 1 2
  [ "$(evaluate $((2000 + 30 * 60 - 1)) 3600 1 0)" = "" ]
}

@test "無応答 59 分では止めず、60 分で unresponsive にする" {
  evaluate 1000 3600 0 ""
  [ "$(evaluate $((1000 + 59 * 60)) 7200 0 "")" = "" ]
  [ "$(evaluate $((1000 + 60 * 60)) 7200 0 "")" = "unresponsive" ]
}

@test "起動から 10 分以内の無応答は数えない" {
  evaluate 1000 599 0 ""
  [ "$(evaluate $((1000 + 60 * 60)) 599 0 "")" = "" ]
}

@test "人数が取れないときは無人として数えない" {
  evaluate 1000 3600 1 ""
  [ "$(evaluate $((1000 + 31 * 60)) 3600 1 "")" = "" ]
}

@test "停止処理中は判定もメトリクス送信もしない" {
  : >"$MC_STATE_DIR/stopping"
  run "$MC_BIN/health.sh"
  [ "$status" -eq 0 ]
  [ "$(count_calls 'put-metric-data')" -eq 0 ]
}

@test "応答があれば ServerUp=1 と人数を送る" {
  export STUB_PLAYERS=3
  run "$MC_BIN/health.sh"
  [ "$status" -eq 0 ]
  grep -q 'metric-name ServerUp --value 1' "$CALLS"
  grep -q 'metric-name PlayersOnline --value 3' "$CALLS"
}
