#!/usr/bin/env bash
# ホスト上のスクリプトが共通で使う関数。各スクリプトから source する。
# 識別子（バケット名・トピック ARN など）は /etc/minecraft/host.env から読み、ログには出さない。
# shellcheck shell=bash

MC_ROOT=${MC_ROOT:-/srv/minecraft}
MC_HOST_ENV=${MC_HOST_ENV:-/etc/minecraft/host.env}
MC_STATE_DIR=${MC_STATE_DIR:-/run/minecraft}
MC_LOCK_FILE=${MC_LOCK_FILE:-$MC_ROOT/.lock}
MC_LOG_FILE=${MC_LOG_FILE:-/var/log/minecraft/scripts.log}
MC_CONTAINER=${MC_CONTAINER:-mc}

if [[ -r $MC_HOST_ENV ]]; then
  # shellcheck source=/dev/null
  . "$MC_HOST_ENV"
fi

# key=value 形式で 1 行ずつ記録する（CloudWatch Agent が scripts ロググループへ送る）。
log() {
  local level=$1
  shift
  local line
  line="$(date -u +%Y-%m-%dT%H:%M:%SZ) level=${level} script=${0##*/} session_id=$(session_id) $*"
  printf '%s\n' "$line" >&2
  if mkdir -p "$(dirname "$MC_LOG_FILE")" 2>/dev/null; then
    printf '%s\n' "$line" >>"$MC_LOG_FILE" 2>/dev/null || true
  fi
}

# 1 回の稼働（ブート）を追うための ID。
session_id() {
  cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf 'unknown'
}

imds() {
  local token
  token=$(curl -fsS --max-time 2 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' \
    http://169.254.169.254/latest/api/token)
  curl -fsS --max-time 2 -H "X-aws-ec2-metadata-token: ${token}" \
    "http://169.254.169.254/latest/meta-data/$1"
}

instance_id() {
  imds instance-id
}

# SNS の events トピックへ独自 JSON を送る。失敗しても呼び出し元の処理は止めない。
notify() {
  local event=$1 severity=$2 message=$3 body attributes
  body=$(jq -cn --arg e "$event" --arg s "$severity" --arg m "$message" --arg sid "$(session_id)" \
    '{source: "host", event: $e, severity: $s, message: $m, session_id: $sid}')
  attributes=$(jq -cn --arg e "$event" --arg s "$severity" \
    '{event: {DataType: "String", StringValue: $e}, severity: {DataType: "String", StringValue: $s}}')
  if ! aws sns publish --region "$MC_REGION" --topic-arn "$MC_TOPIC_ARN" \
    --message "$body" --message-attributes "$attributes" >/dev/null; then
    log warn "event=notify_failed notify_event=${event}"
  fi
}

metric() {
  local name=$1 value=$2 unit=${3:-Count}
  if ! aws cloudwatch put-metric-data --region "$MC_REGION" --namespace Minecraft \
    --metric-name "$name" --value "$value" --unit "$unit" >/dev/null; then
    log warn "event=metric_failed metric=${name}"
  fi
}

container_running() {
  [[ $(docker inspect -f '{{.State.Running}}' "$MC_CONTAINER" 2>/dev/null) == true ]]
}

rcon() {
  docker exec "$MC_CONTAINER" rcon-cli "$@"
}

# server list ping。成功したときだけ 0 を返す。
ping_server() {
  timeout 10 docker exec "$MC_CONTAINER" mc-monitor status --host localhost --port 25565 >/dev/null 2>&1
}

# rcon の list から接続人数を取り出す。取れなければ失敗を返す。
players_online() {
  local reply count
  reply=$(rcon list 2>/dev/null) || return 1
  count=$(printf '%s' "$reply" | sed -nE 's/^There are ([0-9]+) of a max.*/\1/p')
  [[ -n $count ]] || return 1
  printf '%s\n' "$count"
}

tag_self() {
  aws ec2 create-tags --region "$MC_REGION" --resources "$(instance_id)" --tags "Key=$1,Value=$2" >/dev/null
}

untag_self() {
  aws ec2 delete-tags --region "$MC_REGION" --resources "$(instance_id)" --tags "Key=$1" >/dev/null
}
