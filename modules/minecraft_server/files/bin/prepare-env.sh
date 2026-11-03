#!/usr/bin/env bash
# minecraft.service の起動前に実行する。秘匿値を root だけが読める env ファイルにまとめる。
# - whitelist: 本人が SSM SecureString に登録したプレイヤー名（カンマ区切り）
# - オペレーターの一覧: 本人が SSM SecureString に登録したプレイヤー名（カンマ区切り）。未登録なら 0 人
# - RCON パスワード: コンテナ内の localhost だけで使うため、初回にホストで生成してワールド EBS に保存する
set -euo pipefail
MC_BIN=${MC_BIN:-$(dirname "${BASH_SOURCE[0]}")}
# shellcheck source=common.sh
. "$MC_BIN/common.sh"

SECRETS_ENV=${SECRETS_ENV:-/etc/minecraft/secrets.env}
RCON_FILE=${RCON_FILE:-$MC_ROOT/.rcon-password}
OPS_FILE=${OPS_FILE:-$MC_ROOT/data/ops.json}
# コンテナ内で Minecraft を動かすユーザー（イメージの既定値）。
MC_CONTAINER_OWNER=1000:1000
# 一覧のパラメータが未登録であることを示す終了コード。
OPS_UNREGISTERED=3

# env ファイルへの注入を防ぐため、Minecraft のユーザー名として正しい文字だけを許可する。
valid_player_names() {
  [[ $1 =~ ^[A-Za-z0-9_]{3,16}(,[A-Za-z0-9_]{3,16})*$ ]]
}

count_names() {
  if [[ -z $1 ]]; then
    printf '0'
    return
  fi
  printf '%s' "$(($(tr -cd ',' <<<"$1" | wc -c) + 1))"
}

# 一覧の値を標準出力に返す。未登録は OPS_UNREGISTERED、そのほかの読み取り失敗は 1 で返す。
read_ops_parameter() {
  local error_file value="" status=0
  error_file=$(mktemp) || return 1
  value=$(aws ssm get-parameter --region "$MC_REGION" --name "${MC_PARAM_PREFIX}/ops" \
    --with-decryption --query Parameter.Value --output text 2>"$error_file") || status=$?
  # エラー出力には識別子が含まれる可能性があるため、種類の判定だけに使い、ログと通知には出さない。
  if ((status != 0)); then
    if grep -q '(ParameterNotFound)' "$error_file"; then
      status=$OPS_UNREGISTERED
    else
      status=1
    fi
  fi
  rm -f "$error_file"
  printf '%s' "$value"
  return "$status"
}

# 1 人でもホワイトリストにいなければ 1 を返す。Minecraft の名前は大文字と小文字を区別しない。
names_in_whitelist() {
  local whitelist=$2 name
  local -a names
  IFS=, read -ra names <<<"$1"
  for name in "${names[@]}"; do
    [[ ",${whitelist,,}," == *",${name,,},"* ]] || return 1
  done
}

# 重複はエラーにせず、最初の 1 件にまとめる（大文字と小文字の違いも同じ名前として扱う）。
unique_names() {
  local name
  local -a names unique=()
  local -A seen=()
  IFS=, read -ra names <<<"$1"
  for name in "${names[@]}"; do
    if [[ -z ${seen[${name,,}]:-} ]]; then
      seen[${name,,}]=1
      unique+=("$name")
    fi
  done
  (
    IFS=,
    printf '%s' "${unique[*]}"
  )
}

# 検査済みの一覧を標準出力に返す。未登録なら空を返す。失敗は通知まで行って 1 を返す。
load_ops() {
  local whitelist=$1 ops status=0
  ops=$(read_ops_parameter) || status=$?
  if ((status == OPS_UNREGISTERED)); then
    return 0
  fi
  if ((status != 0)); then
    log error "event=ops_unavailable"
    notify start_failed error "オペレーターの一覧を SSM から読めないため、起動を中止しました。"
    return 1
  fi
  ops=${ops//[[:space:]]/}
  if ! valid_player_names "$ops"; then
    log error "event=ops_invalid"
    notify start_failed error "オペレーターの一覧の形式が正しくないため、起動を中止しました（英数字と _ の名前をカンマ区切り）。"
    return 1
  fi
  if ! names_in_whitelist "$ops" "$whitelist"; then
    log error "event=ops_not_whitelisted"
    notify start_failed error "オペレーターの一覧にホワイトリストにない名前があるため、起動を中止しました。"
    return 1
  fi
  unique_names "$ops"
}

# ops.json の種を一時ファイルに書き、そのパスを標準出力に返す。
# data はコンテナのユーザーも書ける場所のため、固定の名前ではなく mktemp で新しいファイルを作る。
# イメージの新規の項目はレベル 4 になるため、レベル 3 の項目を先に置く。UUID はイメージが補う。
write_ops_seed() {
  local target
  target=$(mktemp "$OPS_FILE.XXXXXX") || return 1
  if ! jq -n --arg names "$1" '$names | split(",") | map({uuid: "", name: ., level: 3})' >"$target" \
    || ! chown "$MC_CONTAINER_OWNER" "$target"; then
    rm -f "$target"
    return 1
  fi
  printf '%s' "$target"
}

write_secrets_env() {
  local whitelist=$1 ops=$2 rcon_password
  if [[ ! -s $RCON_FILE ]]; then
    openssl rand -hex 24 >"$RCON_FILE" || return 1
  fi
  rcon_password=$(cat "$RCON_FILE") || return 1
  mkdir -p "$(dirname "$SECRETS_ENV")" || return 1
  printf 'WHITELIST=%s\nOPS=%s\nRCON_PASSWORD=%s\n' "$whitelist" "$ops" "$rcon_password" >"$SECRETS_ENV.new" || return 1
  chmod 600 "$SECRETS_ENV.new"
}

# 両方の一時ファイルを作ってから置き換える。2 回の mv の間で失敗してもコンテナは起動せず、次の起動で両方を書き直す。
# OPS= を常に書くのは、未設定だとイメージが同期を行わず、ops.json が残るため。
write_start_files() {
  local whitelist=$1 ops=$2 ops_new
  ops_new=$(write_ops_seed "$ops") || return 1
  if ! write_secrets_env "$whitelist" "$ops" || ! mv -T "$ops_new" "$OPS_FILE"; then
    rm -f "$ops_new" "$SECRETS_ENV.new"
    return 1
  fi
  if ! mv -T "$SECRETS_ENV.new" "$SECRETS_ENV"; then
    rm -f "$SECRETS_ENV.new"
    return 1
  fi
}

main() {
  local whitelist ops
  umask 077
  if ! whitelist=$(aws ssm get-parameter --region "$MC_REGION" --name "${MC_PARAM_PREFIX}/whitelist" \
    --with-decryption --query Parameter.Value --output text); then
    log error "event=whitelist_unavailable"
    notify start_failed error "whitelist を SSM から読めないため、起動を中止しました。"
    return 1
  fi
  whitelist=${whitelist//[[:space:]]/}
  if ! valid_player_names "$whitelist"; then
    log error "event=whitelist_invalid"
    notify start_failed error "whitelist の形式が正しくないため、起動を中止しました（英数字と _ の名前をカンマ区切り）。"
    return 1
  fi
  ops=$(load_ops "$whitelist") || return 1
  if ! write_start_files "$whitelist" "$ops"; then
    log error "event=ops_seed_failed"
    notify start_failed error "ops.json または secrets.env を書けないため、起動を中止しました。"
    return 1
  fi
  log info "event=env_prepared players=$(count_names "$whitelist") ops=$(count_names "$ops")"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
