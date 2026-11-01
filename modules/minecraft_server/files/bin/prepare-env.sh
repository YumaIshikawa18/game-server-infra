#!/usr/bin/env bash
# minecraft.service の起動前に実行する。秘匿値を root だけが読める env ファイルにまとめる。
# - whitelist: 本人が SSM SecureString に登録したプレイヤー名（カンマ区切り）
# - RCON パスワード: コンテナ内の localhost だけで使うため、初回にホストで生成してワールド EBS に保存する
set -euo pipefail
MC_BIN=${MC_BIN:-$(dirname "${BASH_SOURCE[0]}")}
# shellcheck source=common.sh
. "$MC_BIN/common.sh"

SECRETS_ENV=${SECRETS_ENV:-/etc/minecraft/secrets.env}
RCON_FILE=${RCON_FILE:-$MC_ROOT/.rcon-password}

# env ファイルへの注入を防ぐため、Minecraft のユーザー名として正しい文字だけを許可する。
valid_whitelist() {
  [[ $1 =~ ^[A-Za-z0-9_]{3,16}(,[A-Za-z0-9_]{3,16})*$ ]]
}

main() {
  local whitelist
  umask 077
  if ! whitelist=$(aws ssm get-parameter --region "$MC_REGION" --name "${MC_PARAM_PREFIX}/whitelist" \
    --with-decryption --query Parameter.Value --output text); then
    log error "event=whitelist_unavailable"
    notify start_failed error "whitelist を SSM から読めないため、起動を中止しました。"
    return 1
  fi
  whitelist=${whitelist//[[:space:]]/}
  if ! valid_whitelist "$whitelist"; then
    log error "event=whitelist_invalid"
    notify start_failed error "whitelist の形式が正しくないため、起動を中止しました（英数字と _ の名前をカンマ区切り）。"
    return 1
  fi
  if [[ ! -s $RCON_FILE ]]; then
    openssl rand -hex 24 >"$RCON_FILE"
  fi
  mkdir -p "$(dirname "$SECRETS_ENV")"
  printf 'WHITELIST=%s\nRCON_PASSWORD=%s\n' "$whitelist" "$(cat "$RCON_FILE")" >"$SECRETS_ENV.new"
  chmod 600 "$SECRETS_ENV.new"
  mv "$SECRETS_ENV.new" "$SECRETS_ENV"
  log info "event=env_prepared players=$(($(tr -cd ',' <<<"$whitelist" | wc -c) + 1))"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
