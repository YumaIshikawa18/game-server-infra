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

# 置き換えの前提が満たせないので停止しない。保存を再開し、停止中の印を戻す。
refuse_stop() {
  local reason=$1 step=$2
  if container_running; then
    rcon save-on >/dev/null || log warn "event=save_on_failed"
  fi
  untag_self mc:stopping || true
  rm -f "$MC_STATE_DIR/stopping"
  notify stop_refused error "${step}に失敗したため、置き換え前の停止を中止しました（理由: ${reason}）。"
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
  local save_ok=true uploaded=false
  if container_running; then
    if ! rcon save-off >/dev/null || ! rcon save-all flush >/dev/null; then
      save_ok=false
      log error "event=save_failed reason=${reason}"
    fi
  fi
  # 置き換えでは、保存できていない状態のバックアップを有効とみなさない（アップロードもしない）。
  if [[ $require_backup == true && $save_ok != true ]]; then
    refuse_stop "$reason" "ワールドの保存"
    return 1
  fi
  if key=$(upload_world stop); then
    uploaded=true
  fi
  if [[ $save_ok == true && $uploaded == true ]]; then
    backup_ok=true
    trim_generations stop "$STOP_KEEP" || log warn "event=trim_failed kind=stop"
    metric BackupFailures 0
  else
    # 保存に失敗した回のアーカイブは整合が保証できないので、古い世代は削除しない。
    metric BackupFailures 1
  fi
  if [[ $require_backup == true && $backup_ok != true ]]; then
    refuse_stop "$reason" "バックアップのアップロードまたは照合"
    return 1
  fi
  if container_running; then
    docker stop -t 60 "$MC_CONTAINER" >/dev/null || log warn "event=container_stop_failed"
  fi
  if [[ $backup_ok == true ]]; then
    notify server_stopping info "サーバーを停止します（理由: ${reason}、バックアップ: ${key##*/}）。"
  elif [[ $uploaded == true ]]; then
    notify server_stopping warn "ワールドの保存に失敗したため、整合が保証できないバックアップ（${key##*/}）だけを残して停止します（理由: ${reason}）。"
  else
    notify server_stopping warn "バックアップに失敗しましたが、サーバーを停止します（理由: ${reason}）。"
  fi
  log info "event=stop_scheduled reason=${reason} backup_ok=${backup_ok}"
  schedule_instance_stop
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
