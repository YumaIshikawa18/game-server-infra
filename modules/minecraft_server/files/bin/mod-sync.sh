#!/usr/bin/env bash
# MOD 一覧（config/mods.json）に従って jar を取得し、sha256 を照合してから mods/ に配置する。
# - 照合済みの jar は EBS 上のキャッシュ（mods-cache/<sha256>.jar）から再利用する
# - sha256 が一致しない jar は配置せず、全体を失敗にする（minecraft.service は起動しない）
# - side が client の MOD はサーバーに置かない
set -euo pipefail
MC_BIN=${MC_BIN:-$(dirname "${BASH_SOURCE[0]}")}
# shellcheck source=common.sh
. "$MC_BIN/common.sh"

MODS_JSON=${MODS_JSON:-/opt/minecraft/config/mods.json}
CACHE_DIR=${CACHE_DIR:-$MC_ROOT/mods-cache}
MODS_DIR=${MODS_DIR:-$MC_ROOT/data/mods}
PARALLEL=${PARALLEL:-4}

# サーバーに置く MOD を「sha256<TAB>url<TAB>name」で出力する。形式が不正なら失敗する。
server_mods() {
  # -e は空の一覧（vanilla）を失敗にしてしまうため使わない。不正な形式は error() で失敗する。
  jq -r '
    if type != "array" then error("mods.json must be an array") else . end
    | map(select(.side != "client"))
    | map(
        if (.name | type == "string" and test("^[A-Za-z0-9._-]{1,64}$"))
          and (.url | type == "string" and startswith("https://"))
          and (.sha256 | type == "string" and test("^[0-9a-f]{64}$"))
          and (.side | IN("server", "both"))
        then . else error("invalid mod entry") end)
    | .[] | [.sha256, .url, .name] | @tsv' "$MODS_JSON"
}

# 1 件を取得してキャッシュに入れる。照合に失敗したら一時ファイルを消して失敗する。
# `fetch_one ... || ...` の形で呼ぶため set -e が効かない。各手順の失敗を明示的に判定する。
fetch_one() {
  local sum=$1 url=$2 name=$3 target temp actual
  target="$CACHE_DIR/${sum}.jar"
  if [[ -f $target ]] && [[ $(sha256sum "$target" | cut -d' ' -f1) == "$sum" ]]; then
    return 0
  fi
  temp=$(mktemp -p "$CACHE_DIR" ".download.XXXXXX") || return 1
  if ! curl -fsSL --proto '=https' --max-time 300 --retry 2 -o "$temp" "$url"; then
    rm -f "$temp"
    log error "event=mod_download_failed mod=${name}"
    return 1
  fi
  actual=$(sha256sum "$temp" | cut -d' ' -f1)
  if [[ $actual != "$sum" ]]; then
    rm -f "$temp"
    log error "event=mod_checksum_mismatch mod=${name}"
    return 1
  fi
  if ! mv "$temp" "$target"; then
    rm -f "$temp"
    log error "event=mod_cache_failed mod=${name}"
    return 1
  fi
}

# 同時実行を PARALLEL 件までに抑えて全件を取得する。1 件でも失敗したら失敗を返す。
# 終了状態の取りこぼしを避けるため、失敗は印のファイルで集計する。
fetch_all() {
  local list=$1 marks sum url name
  marks=$(mktemp -d -p "$CACHE_DIR" ".failed.XXXXXX")
  while IFS=$'\t' read -r sum url name; do
    [[ -n $sum ]] || continue
    while (($(jobs -rp | wc -l) >= PARALLEL)); do
      wait -n || true
    done
    { fetch_one "$sum" "$url" "$name" || : >"$marks/$sum"; } &
  done <<<"$list"
  wait
  if [[ -n $(ls -A "$marks") ]]; then
    rm -rf "$marks"
    return 1
  fi
  rm -rf "$marks"
}

# mods/ を一覧と同じ内容に作り直す（一覧にない jar は残さない）。
install_mods() {
  local list=$1 staging sum name
  staging=$(mktemp -d -p "$MC_ROOT" ".mods.XXXXXX")
  while IFS=$'\t' read -r sum _ name; do
    [[ -n $sum ]] || continue
    cp "$CACHE_DIR/${sum}.jar" "$staging/${name}.jar"
  done <<<"$list"
  rm -rf "$MODS_DIR.old"
  if [[ -d $MODS_DIR ]]; then
    mv "$MODS_DIR" "$MODS_DIR.old"
  fi
  mv "$staging" "$MODS_DIR"
  rm -rf "$MODS_DIR.old"
}

main() {
  local list failed=0 count
  mkdir -p "$CACHE_DIR" "$(dirname "$MODS_DIR")"
  if ! list=$(server_mods); then
    log error "event=mods_config_invalid"
    notify mod_sync_failed error "MOD 一覧の形式が正しくないため、起動を中止しました。"
    return 1
  fi
  count=$(grep -c . <<<"$list" || true)
  if ((count > 0)); then
    fetch_all "$list" || failed=1
  fi
  if ((failed)); then
    notify mod_sync_failed error "MOD の取得または sha256 の照合に失敗したため、起動を中止しました。詳細はサーバーのログを確認してください。"
    return 1
  fi
  install_mods "$list"
  log info "event=mods_synced count=${count}"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
