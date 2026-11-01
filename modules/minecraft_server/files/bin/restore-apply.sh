#!/usr/bin/env bash
# mc-restore-apply ドキュメントから呼ばれる。復元モード（Minecraft 停止中）でだけ実行できる。
# 使い方: restore-apply.sh <stop/... または hourly/... の .tar.zst キー>
# 取得 → S3 の SHA-256 と照合 → アーカイブの中身を検査 → 現在のワールドを data.pre-restore に退避 → 展開。
# どの段階で失敗しても、現在のワールドはそのまま残す。
set -euo pipefail
MC_BIN=${MC_BIN:-$(dirname "${BASH_SOURCE[0]}")}
# shellcheck source=common.sh
. "$MC_BIN/common.sh"

valid_key() {
  [[ $1 =~ ^(stop|hourly)/[0-9]{8}-[0-9]{6}\.tar\.zst$ ]]
}

# 通常のファイルとディレクトリだけを許し、絶対パスと .. を含む名前を拒否する。
archive_is_safe() {
  local archive=$1 types names
  types=$(tar --zstd -tvf "$archive" | cut -c1 | sort -u | tr -d '\n')
  if [[ ! $types =~ ^[-d]+$ ]]; then
    return 1
  fi
  names=$(tar --zstd -tf "$archive")
  if grep -qE '^/|(^|/)\.\.(/|$)' <<<"$names"; then
    return 1
  fi
}

main() {
  local key=${1:-} work archive expected actual
  if ! valid_key "$key"; then
    log error "event=restore_rejected reason=invalid_key"
    return 2
  fi
  if ! world_mounted; then
    log error "event=restore_rejected reason=world_not_mounted"
    return 1
  fi
  if [[ ! -e $MC_STATE_DIR/restore ]] || container_running; then
    log error "event=restore_rejected reason=not_in_restore_mode"
    return 2
  fi
  exec 9>"$MC_LOCK_FILE"
  flock -w 60 9
  work=$(mktemp -d -p "$MC_ROOT" ".restore.XXXXXX")
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" EXIT
  archive="$work/archive.tar.zst"
  # バックアップ時に保存した SHA-256（メタデータ）。転送の完全性は --checksum-mode で S3 の CRC も検証する。
  expected=$(aws s3api head-object --region "$MC_REGION" --bucket "$MC_BUCKET" --key "$key" \
    --query Metadata.sha256 --output text)
  aws s3api get-object --region "$MC_REGION" --bucket "$MC_BUCKET" --key "$key" \
    --checksum-mode ENABLED "$archive" >/dev/null
  actual=$(sha256sum "$archive" | cut -d' ' -f1)
  if [[ ! $expected =~ ^[0-9a-f]{64}$ || $actual != "$expected" ]]; then
    log error "event=restore_rejected reason=checksum_mismatch"
    notify restore_failed error "復元用バックアップの照合に失敗しました。ワールドは変更していません。"
    return 1
  fi
  if ! archive_is_safe "$archive"; then
    log error "event=restore_rejected reason=unsafe_archive"
    notify restore_failed error "復元用バックアップに許可しない内容が含まれていました。ワールドは変更していません。"
    return 1
  fi
  mkdir "$work/data"
  tar --zstd -xf "$archive" -C "$work/data" --no-same-owner
  rm -rf "$MC_ROOT/data.pre-restore"
  if [[ -d $MC_ROOT/data ]]; then
    mv "$MC_ROOT/data" "$MC_ROOT/data.pre-restore"
  fi
  mv "$work/data" "$MC_ROOT/data"
  log info "event=restore_applied object=${key##*/}"
  notify restore_applied info "バックアップ ${key##*/} を復元しました。以前のワールドは data.pre-restore に退避しています。"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
