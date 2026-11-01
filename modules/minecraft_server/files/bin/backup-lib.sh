#!/usr/bin/env bash
# 毎時バックアップ（hourly/）と停止時バックアップ（stop/）の共通処理。
# shellcheck shell=bash

HOURLY_KEEP=${HOURLY_KEEP:-24}
STOP_KEEP=${STOP_KEEP:-7}

# 新しい順に keep 件だけ残し、それより古いバックアップを削除する。
# キーは <kind>/YYYYMMDD-HHMMSS.tar.zst なので、名前順が時刻順になる。
trim_generations() {
  local kind=$1 keep=$2 keys count excess key
  keys=$(aws s3api list-objects-v2 --region "$MC_REGION" --bucket "$MC_BUCKET" --prefix "${kind}/" \
    --query 'Contents[].Key' --output json | jq -r '(. // []) | map(select(test("^[a-z]+/[0-9]{8}-[0-9]{6}\\.tar\\.zst$"))) | sort | .[]')
  count=$(printf '%s' "$keys" | grep -c . || true)
  excess=$((count - keep))
  if ((excess <= 0)); then
    return 0
  fi
  while IFS= read -r key; do
    aws s3api delete-object --region "$MC_REGION" --bucket "$MC_BUCKET" --key "$key" >/dev/null
    log info "event=backup_trimmed kind=${kind}"
  done < <(printf '%s\n' "$keys" | head -n "$excess")
}

# ワールドを圧縮して S3 に送り、S3 側で計算した SHA-256 と照合する。
# 成功したらキーを標準出力に出す。RCON の save-off は呼び出し元が管理する。
# 呼び出し元は `if key=$(upload_world ...)` の形で使うため、Bash の仕様で set -e が効かない。
# そのため、すべての手順の失敗を明示的に判定し、途中で失敗したら何もアップロードせずに失敗を返す。
# サブシェルで実行し、失敗時も一時ファイルを残さない（EXIT trap は呼び出し元に影響しない）。
upload_world() (
  local kind=$1 stamp key archive sum remote started size
  fail() {
    log error "event=backup_failed kind=${kind} step=$1"
    exit 1
  }
  started=$(date +%s) || fail clock
  stamp=$(date -u +%Y%m%d-%H%M%S) || fail clock
  key="${kind}/${stamp}.tar.zst"
  archive=$(mktemp -p "$MC_ROOT" .backup.XXXXXX) || fail tempfile
  # shellcheck disable=SC2064
  trap "rm -f '$archive'" EXIT
  tar --zstd -C "$MC_ROOT/data" -cf "$archive" . || fail archive
  [[ -s $archive ]] || fail archive
  sum=$(set -o pipefail; openssl dgst -sha256 -binary "$archive" | base64) || fail checksum
  [[ -n $sum ]] || fail checksum
  aws s3api put-object --region "$MC_REGION" --bucket "$MC_BUCKET" --key "$key" --body "$archive" \
    --checksum-sha256 "$sum" --server-side-encryption AES256 >/dev/null || fail upload
  # 照合できなかったオブジェクトは世代として数えられないよう削除する。
  discard() {
    aws s3api delete-object --region "$MC_REGION" --bucket "$MC_BUCKET" --key "$key" >/dev/null ||
      log warn "event=backup_discard_failed kind=${kind}"
    fail "$1"
  }
  remote=$(aws s3api head-object --region "$MC_REGION" --bucket "$MC_BUCKET" --key "$key" \
    --checksum-mode ENABLED --query ChecksumSHA256 --output text) || discard verify
  [[ $remote == "$sum" ]] || discard checksum_mismatch
  size=$(stat -c %s "$archive") || fail size
  metric BackupSizeBytes "$size" Bytes
  metric BackupDurationSeconds "$(($(date +%s) - started))" Seconds
  printf '%s\n' "$key"
)

bucket_bytes() {
  aws s3api list-object-versions --region "$MC_REGION" --bucket "$MC_BUCKET" \
    --query 'sum(Versions[].Size)' --output text
}
