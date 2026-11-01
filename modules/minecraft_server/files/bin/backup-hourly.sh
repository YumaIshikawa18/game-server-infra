#!/usr/bin/env bash
# 毎時バックアップ（backup-hourly.timer から起動）。停止処理などがロックを持っていればスキップする。
set -euo pipefail
MC_BIN=${MC_BIN:-$(dirname "${BASH_SOURCE[0]}")}
# shellcheck source=common.sh
. "$MC_BIN/common.sh"
# shellcheck source=backup-lib.sh
. "$MC_BIN/backup-lib.sh"

restore_saving() {
  if container_running; then
    rcon save-on >/dev/null 2>&1 || log warn "event=save_on_failed"
  fi
}

backup_failed() {
  metric BackupFailures 1
  notify backup_failed error "毎時バックアップに失敗しました（${1}）。サーバーは稼働を続けます。"
  return 1
}

run_backup() {
  local key bytes
  if ! container_running; then
    log info "event=backup_skipped reason=server_not_running"
    return 0
  fi
  # save-off を送った後は、どこで失敗しても必ず save-on に戻す。
  trap restore_saving EXIT
  # 保存できていない状態のアーカイブは、整合が取れないので作らない。
  if ! rcon save-off >/dev/null || ! rcon save-all flush >/dev/null; then
    log error "event=backup_failed kind=hourly step=save"
    backup_failed "ワールドの保存"
    return 1
  fi
  if ! key=$(upload_world hourly); then
    backup_failed "圧縮またはアップロード"
    return 1
  fi
  restore_saving
  trap - EXIT
  trim_generations hourly "$HOURLY_KEEP"
  if bytes=$(bucket_bytes) && [[ $bytes =~ ^[0-9]+$ ]]; then
    metric BackupBucketBytes "$bytes" Bytes
  fi
  metric BackupFailures 0
  log info "event=backup_completed kind=hourly object=${key##*/}"
}

main() {
  exec 9>"$MC_LOCK_FILE"
  if ! flock -n 9; then
    log info "event=backup_skipped reason=locked"
    return 0
  fi
  run_backup
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
