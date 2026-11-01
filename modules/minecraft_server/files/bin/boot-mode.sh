#!/usr/bin/env bash
# 起動時に 1 回だけ実行する（boot-mode.service）。
# - 前回の停止で付けた mc:stopping タグを外す
# - タグ mc:mode=restore なら /run/minecraft/restore を作り、mod-sync と minecraft を起動しない
set -euo pipefail
MC_BIN=${MC_BIN:-$(dirname "${BASH_SOURCE[0]}")}
# shellcheck source=common.sh
. "$MC_BIN/common.sh"

boot_mode() {
  aws ec2 describe-tags --region "$MC_REGION" \
    --filters "Name=resource-id,Values=$(instance_id)" "Name=key,Values=mc:mode" \
    --query 'Tags[0].Value' --output text
}

main() {
  local mode
  mkdir -p "$MC_STATE_DIR"
  rm -f "$MC_STATE_DIR/restore" "$MC_STATE_DIR/stopping"
  untag_self mc:stopping || log warn "event=untag_failed tag=mc:stopping"
  mode=$(boot_mode)
  if [[ $mode == restore ]]; then
    : >"$MC_STATE_DIR/restore"
    log info "event=boot_mode mode=restore"
    notify boot_restore_mode info "復元モードで起動しました。Minecraft は起動しません。"
  else
    log info "event=boot_mode mode=normal"
  fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
