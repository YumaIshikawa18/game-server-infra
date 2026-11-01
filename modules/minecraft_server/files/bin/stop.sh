#!/usr/bin/env bash
# 停止処理（mc-stop ドキュメント、idle / unresponsive、start-failed から呼ばれる）。
# 使い方: stop.sh <reason> [require_backup]
#   require_backup=true のときは、バックアップと照合に失敗したら停止せず失敗を返す（置き換えの保護）。
set -euo pipefail
MC_BIN=${MC_BIN:-$(dirname "${BASH_SOURCE[0]}")}
# shellcheck source=common.sh
. "$MC_BIN/common.sh"
# shellcheck source=backup-lib.sh
. "$MC_BIN/backup-lib.sh"

STOP_LOCK_WAIT=${STOP_LOCK_WAIT:-600}
STOP_DELAY=${STOP_DELAY:-15}

valid_reason() {
  [[ $1 =~ ^(manual|idle|unresponsive|replace|start-failed)$ ]]
}

# SSM の実行結果を返してから EC2 を止めるため、停止は少し遅らせて別プロセスで行う。
schedule_instance_stop() {
  systemd-run --quiet --unit=mc-instance-stop --on-active="${STOP_DELAY}s" \
    /usr/bin/aws ec2 stop-instances --region "$MC_REGION" --instance-ids "$(instance_id)"
}

main() {
  local reason=${1:-} require_backup=${2:-false} key="" backup_ok=false
  if ! valid_reason "$reason" || [[ ! $require_backup =~ ^(true|false)$ ]]; then
    log error "event=stop_rejected reason=invalid_arguments"
    return 2
  fi
  tag_self mc:stopping true || log warn "event=tag_failed tag=mc:stopping"
  # health.sh が停止処理を重ねて呼ばないようにする（/run なので再起動で消える）。
  mkdir -p "$MC_STATE_DIR"
  : >"$MC_STATE_DIR/stopping"
  exec 9>"$MC_LOCK_FILE"
  if ! flock -w "$STOP_LOCK_WAIT" 9; then
    log error "event=stop_lock_timeout"
    rm -f "$MC_STATE_DIR/stopping"
    return 1
  fi
  if container_running; then
    rcon save-off >/dev/null || true
    rcon save-all flush >/dev/null || true
  fi
  if key=$(upload_world stop); then
    backup_ok=true
    trim_generations stop "$STOP_KEEP" || log warn "event=trim_failed kind=stop"
    metric BackupFailures 0
  else
    metric BackupFailures 1
  fi
  if [[ $require_backup == true && $backup_ok != true ]]; then
    # 停止しないので保存を再開し、置き換えを止める。
    if container_running; then
      rcon save-on >/dev/null || true
    fi
    untag_self mc:stopping || true
    rm -f "$MC_STATE_DIR/stopping"
    notify stop_refused error "バックアップに失敗したため、置き換え前の停止を中止しました（理由: ${reason}）。"
    return 1
  fi
  if container_running; then
    docker stop -t 60 "$MC_CONTAINER" >/dev/null || log warn "event=container_stop_failed"
  fi
  if [[ $backup_ok == true ]]; then
    notify server_stopping info "サーバーを停止します（理由: ${reason}、バックアップ: ${key##*/}）。"
  else
    notify server_stopping warn "バックアップに失敗しましたが、サーバーを停止します（理由: ${reason}）。"
  fi
  log info "event=stop_scheduled reason=${reason} backup_ok=${backup_ok}"
  schedule_instance_stop
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
